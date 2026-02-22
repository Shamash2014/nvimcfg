local state = require("mobile-dev.android.state")
local sdk = require("mobile-dev.android.sdk")
local devices = require("mobile-dev.android.devices")
local build = require("mobile-dev.android.build")
local logcat = require("mobile-dev.android.logcat")

local M = {}

function M.android_menu()
  local items = {
    { text = "Build & Deploy", desc = "Build, install, and launch", action = "build_deploy" },
    { text = "Assemble APK", desc = "Build without deploying", action = "assemble" },
    { text = "Deploy Last APK", desc = "Install + launch last built APK", action = "deploy" },
    { text = "Clean Project", desc = "Run gradle clean", action = "clean" },
    { text = "Repeat Last Build", desc = "Re-run last build command", action = "repeat" },
    { text = "──────────────", desc = "", action = "separator" },
    { text = "Toggle Logcat", desc = "Show/hide logcat panel", action = "logcat" },
    { text = "Logcat by Package", desc = "Filter logcat by app package", action = "logcat_package" },
    { text = "──────────────", desc = "", action = "separator" },
    { text = "Select Device", desc = "Pick connected device or AVD", action = "device" },
    { text = "Launch Emulator", desc = "Start an AVD", action = "emulator_start" },
    { text = "Stop Emulator", desc = "Kill running emulator", action = "emulator_stop" },
    { text = "Clear App Data", desc = "Clear data for current app", action = "clear_data" },
    { text = "Uninstall App", desc = "Remove app from device", action = "uninstall" },
    { text = "Force Stop App", desc = "Force stop the running app", action = "force_stop" },
    { text = "──────────────", desc = "", action = "separator" },
    { text = "Gradle Tasks", desc = "Browse and run gradle tasks", action = "gradle_tasks" },
    { text = "──────────────", desc = "", action = "separator" },
    { text = "Health Check", desc = "Validate SDK and tools", action = "health" },
    { text = "Show State", desc = "Display current configuration", action = "show_state" },
  }

  vim.ui.select(items, {
    prompt = "Android",
    format_item = function(item)
      if item.action == "separator" then
        return item.text
      end
      if item.desc ~= "" then
        return item.text .. "  " .. item.desc
      end
      return item.text
    end,
  }, function(item)
    if not item or item.action == "separator" then return end

    local actions = {
      build_deploy = function() build.build_and_deploy() end,
      assemble = function() build.assemble() end,
      deploy = function() build.deploy() end,
      clean = function() build.clean() end,
      ["repeat"] = function() build.repeat_last() end,
      logcat = function() logcat.toggle() end,
      logcat_package = function()
        logcat.set_package_filter(state.get("application_id"))
        if not logcat._job then logcat.toggle() end
      end,
      device = function() devices.select_device() end,
      emulator_start = function() devices.launch_emulator() end,
      emulator_stop = function() devices.stop_emulator() end,
      clear_data = function() devices.clear_app_data() end,
      uninstall = function() devices.uninstall_app() end,
      force_stop = function() devices.force_stop() end,
      gradle_tasks = function() M.browse_gradle_tasks() end,
      health = function() sdk.health_check() end,
      show_state = function() M.show_state() end,
    }

    local action = actions[item.action]
    if action then action() end
  end)
end

function M.browse_gradle_tasks()
  local gradlew = state.get("gradlew")
  if not gradlew then
    vim.notify("gradlew not found", vim.log.levels.ERROR)
    return
  end

  local cache = state.get("gradle_tasks_cache")
  local cache_time = state.get("gradle_tasks_cache_time") or 0
  local ttl = 300

  if cache and (os.time() - cache_time) < ttl then
    M._show_gradle_picker(cache)
    return
  end

  vim.notify("Loading gradle tasks...", vim.log.levels.INFO)

  local Job = require("plenary.job")
  Job:new({
    command = gradlew,
    args = { "tasks", "--all", "-q" },
    cwd = state.get("project_root"),
    on_exit = function(j, code)
      local output = j:result()
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("Failed to load gradle tasks", vim.log.levels.ERROR)
          return
        end

        local tasks = {}
        for _, line in ipairs(output) do
          local name, desc = line:match("^(%S+)%s+%-%s+(.+)$")
          if name then
            table.insert(tasks, { name = name, desc = desc })
          end
        end

        state.set("gradle_tasks_cache", tasks)
        state.set("gradle_tasks_cache_time", os.time())
        M._show_gradle_picker(tasks)
      end)
    end,
  }):start()
end

function M._show_gradle_picker(tasks)
  if #tasks == 0 then
    vim.notify("No gradle tasks found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, task in ipairs(tasks) do
    table.insert(items, {
      text = task.name,
      desc = task.desc or "",
      gradle_task = task.name,
    })
  end

  vim.ui.select(items, {
    prompt = "Gradle Tasks:",
    format_item = function(item)
      if item.desc ~= "" then
        return item.text .. "  " .. item.desc
      end
      return item.text
    end,
  }, function(item)
    if not item then return end
    local gradlew = state.get("gradlew")
    require("core.tasks").run_task({
      name = "gradle: " .. item.gradle_task,
      cmd = gradlew .. " " .. item.gradle_task,
      desc = item.desc,
      cwd = state.get("project_root"),
    })
  end)
end

function M.show_state()
  local lines = {}

  local device = state.get("selected_device")
  table.insert(lines, "Device: " .. (device or "auto"))

  local module = state.get("selected_module")
  table.insert(lines, "Module: " .. (module or "app"))

  local variant = state.get("selected_variant")
  table.insert(lines, "Variant: " .. (variant or "not set"))

  local app_id = state.get("application_id")
  table.insert(lines, "App ID: " .. (app_id or "unknown"))

  local sdk_path = state.get("sdk_path")
  table.insert(lines, "SDK: " .. (sdk_path or "not found"))

  local root = state.get("project_root")
  table.insert(lines, "Root: " .. (root or vim.fn.getcwd()))

  local last_apk = state.get("last_apk_path")
  if last_apk then
    table.insert(lines, "Last APK: " .. last_apk)
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Android State" })
end

return M
