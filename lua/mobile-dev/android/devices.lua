local state = require("mobile-dev.android.state")

local M = {}

local function get_adb()
  local tools = state.get("tools") or {}
  return tools.adb or vim.fn.exepath("adb") or "adb"
end

local function get_emulator()
  local tools = state.get("tools") or {}
  return tools.emulator or vim.fn.exepath("emulator") or "emulator"
end

local function run_async(cmd, args, callback)
  local Job = require("plenary.job")
  Job:new({
    command = cmd,
    args = args,
    on_exit = function(j, return_val)
      local output = j:result()
      vim.schedule(function()
        callback(output, return_val)
      end)
    end,
  }):start()
end

function M.list_devices(callback)
  run_async(get_adb(), { "devices", "-l" }, function(output, code)
    if code ~= 0 then
      callback({})
      return
    end

    local devices = {}
    for _, line in ipairs(output) do
      if not line:match("^List of") and line:match("%S") then
        local serial = line:match("^(%S+)")
        local dev_state = line:match("^%S+%s+(%w+)")
        local model = line:match("model:(%S+)") or "unknown"
        local device_type = serial:match("^emulator") and "emulator" or "device"
        if serial and dev_state then
          table.insert(devices, {
            serial = serial,
            state = dev_state,
            model = model,
            type = device_type,
          })
        end
      end
    end
    callback(devices)
  end)
end

function M.list_avds(callback)
  run_async(get_emulator(), { "-list-avds" }, function(output, code)
    if code ~= 0 then
      callback({})
      return
    end

    local avds = {}
    for _, line in ipairs(output) do
      local name = line:match("^(%S+)$")
      if name then
        table.insert(avds, name)
      end
    end
    callback(avds)
  end)
end

function M.select_device()
  M.list_devices(function(devices)
    M.list_avds(function(avds)
      local items = {}

      for _, dev in ipairs(devices) do
        table.insert(items, {
          text = string.format("[%s] %s (%s)", dev.type, dev.serial, dev.model),
          device = dev,
          is_connected = true,
        })
      end

      for _, avd in ipairs(avds) do
        local running = false
        for _, dev in ipairs(devices) do
          if dev.model == avd or dev.serial:match("emulator") then
            running = true
            break
          end
        end
        if not running then
          table.insert(items, {
            text = string.format("[avd] %s (not running)", avd),
            avd_name = avd,
            is_connected = false,
          })
        end
      end

      if #items == 0 then
        vim.notify("No devices or AVDs found", vim.log.levels.WARN)
        return
      end

      vim.ui.select(items, {
        prompt = "Select device:",
        format_item = function(item) return item.text end,
      }, function(item)
        if not item then return end
        if item.is_connected then
          state.set("selected_device", item.device.serial)
          state.save()
          vim.notify("Selected: " .. item.device.serial, vim.log.levels.INFO)
        else
          M.launch_emulator(item.avd_name)
        end
      end)
    end)
  end)
end

local function get_device_serial()
  return state.get("selected_device")
end

local function adb_cmd(args, callback)
  local serial = get_device_serial()
  local full_args = {}
  if serial then
    table.insert(full_args, "-s")
    table.insert(full_args, serial)
  end
  for _, a in ipairs(args) do
    table.insert(full_args, a)
  end
  run_async(get_adb(), full_args, callback)
end

function M.launch_emulator(avd_name)
  if not avd_name then
    M.list_avds(function(avds)
      if #avds == 0 then
        vim.notify("No AVDs found", vim.log.levels.WARN)
        return
      end
      vim.ui.select(avds, {
        prompt = "Launch emulator:",
      }, function(selected)
        if selected then
          M.launch_emulator(selected)
        end
      end)
    end)
    return
  end

  vim.notify("Launching emulator: " .. avd_name, vim.log.levels.INFO)
  local emulator = get_emulator()
  vim.fn.jobstart({ emulator, "-avd", avd_name }, {
    detach = true,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("Emulator exited with code " .. code, vim.log.levels.WARN)
        end)
      end
    end,
  })

  local attempts = 0
  local max_attempts = 30
  local timer = vim.loop.new_timer()
  timer:start(2000, 2000, vim.schedule_wrap(function()
    attempts = attempts + 1
    if attempts >= max_attempts then
      timer:stop()
      timer:close()
      vim.notify("Emulator boot timeout", vim.log.levels.WARN)
      return
    end
    M.list_devices(function(devices)
      for _, dev in ipairs(devices) do
        if dev.state == "device" and dev.type == "emulator" then
          timer:stop()
          timer:close()
          state.set("selected_device", dev.serial)
          state.save()
          vim.notify("Emulator ready: " .. dev.serial, vim.log.levels.INFO)
          return
        end
      end
    end)
  end))
end

function M.stop_emulator(serial)
  serial = serial or get_device_serial()
  if not serial then
    vim.notify("No device selected", vim.log.levels.WARN)
    return
  end
  run_async(get_adb(), { "-s", serial, "emu", "kill" }, function(_, code)
    if code == 0 then
      vim.notify("Emulator stopped: " .. serial, vim.log.levels.INFO)
    else
      vim.notify("Failed to stop emulator", vim.log.levels.ERROR)
    end
  end)
end

function M.install_apk(apk_path, serial)
  if not apk_path then
    vim.notify("No APK path provided", vim.log.levels.ERROR)
    return
  end
  local args = {}
  serial = serial or get_device_serial()
  if serial then
    table.insert(args, "-s")
    table.insert(args, serial)
  end
  vim.list_extend(args, { "install", "-r", apk_path })
  run_async(get_adb(), args, function(output, code)
    if code == 0 then
      vim.notify("APK installed", vim.log.levels.INFO)
    else
      vim.notify("Install failed: " .. table.concat(output, "\n"), vim.log.levels.ERROR)
    end
  end)
end

function M.clear_app_data(package, serial)
  package = package or state.get("application_id")
  if not package then
    vim.notify("No package specified", vim.log.levels.WARN)
    return
  end
  adb_cmd({ "shell", "pm", "clear", package }, function(_, code)
    if code == 0 then
      vim.notify("Cleared data: " .. package, vim.log.levels.INFO)
    else
      vim.notify("Failed to clear data", vim.log.levels.ERROR)
    end
  end)
end

function M.uninstall_app(package, serial)
  package = package or state.get("application_id")
  if not package then
    vim.notify("No package specified", vim.log.levels.WARN)
    return
  end
  local args = {}
  serial = serial or get_device_serial()
  if serial then
    table.insert(args, "-s")
    table.insert(args, serial)
  end
  vim.list_extend(args, { "uninstall", package })
  run_async(get_adb(), args, function(_, code)
    if code == 0 then
      vim.notify("Uninstalled: " .. package, vim.log.levels.INFO)
    else
      vim.notify("Failed to uninstall", vim.log.levels.ERROR)
    end
  end)
end

function M.force_stop(package, serial)
  package = package or state.get("application_id")
  if not package then return end
  adb_cmd({ "shell", "am", "force-stop", package }, function() end)
end

function M.launch_app(package, activity, serial)
  package = package or state.get("application_id")
  if not package then
    vim.notify("No package specified", vim.log.levels.WARN)
    return
  end

  if activity then
    adb_cmd({ "shell", "am", "start", "-n", package .. "/" .. activity }, function(_, code)
      if code == 0 then
        vim.notify("Launched: " .. package, vim.log.levels.INFO)
      end
    end)
  else
    adb_cmd({
      "shell", "monkey", "-p", package,
      "-c", "android.intent.category.LAUNCHER", "1",
    }, function(_, code)
      if code == 0 then
        vim.notify("Launched: " .. package, vim.log.levels.INFO)
      else
        vim.notify("Failed to launch app", vim.log.levels.WARN)
      end
    end)
  end
end

return M
