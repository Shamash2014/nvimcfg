local state = require("android.state")
local sdk = require("android.sdk")
local devices = require("android.devices")

local M = {}

local function get_gradlew()
  local gradlew = state.get("gradlew")
  if not gradlew then
    gradlew = sdk.find_gradlew()
  end
  return gradlew
end

local function select_module(callback)
  local modules = state.get("modules") or {}
  if #modules <= 1 then
    callback(modules[1] or "app")
    return
  end
  vim.ui.select(modules, {
    prompt = "Select module:",
  }, function(selected)
    if selected then
      state.set("selected_module", selected)
      callback(selected)
    end
  end)
end

local function select_variant(callback)
  local variants = state.get("variants") or {}
  if #variants == 0 then
    sdk.parse_build_gradle()
    variants = state.get("variants") or {}
  end
  if #variants <= 1 then
    callback(variants[1] or "debug")
    return
  end
  vim.ui.select(variants, {
    prompt = "Select variant:",
  }, function(selected)
    if selected then
      state.set("selected_variant", selected)
      state.save()
      callback(selected)
    end
  end)
end

local function find_apk(module, variant)
  local root = state.get("project_root") or vim.fn.getcwd()
  local search_dirs = {
    string.format("%s/%s/build/outputs/apk", root, module),
    string.format("%s/%s/build/outputs/apk/%s", root, module, variant:lower()),
  }

  for _, dir in ipairs(search_dirs) do
    local apks = vim.fn.glob(dir .. "/**/*.apk", false, true)
    if #apks > 0 then
      table.sort(apks, function(a, b)
        return vim.fn.getftime(a) > vim.fn.getftime(b)
      end)
      return apks[1]
    end
  end
  return nil
end

local function capitalize(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

function M.build_and_deploy(opts)
  opts = opts or {}
  local gradlew = get_gradlew()
  if not gradlew then
    vim.notify("gradlew not found", vim.log.levels.ERROR)
    return
  end

  select_module(function(module)
    local variant = opts.variant or state.get("selected_variant")
    local function do_build(var)
      local task_name = string.format(":%s:assemble%s", module, capitalize(var))
      local cmd = gradlew .. " " .. task_name

      state.set("last_build_cmd", cmd)
      state.save()

      local task = {
        name = "android: build " .. var,
        cmd = cmd,
        desc = "Build " .. module .. " " .. var,
        cwd = state.get("project_root"),
      }

      local tasks = require("core.tasks")
      local task_entry = tasks.run_task(task)

      if task_entry and task_entry.term then
        local buf = task_entry.term.buf
        if buf and type(buf) == "number" then
          vim.api.nvim_create_autocmd("TermClose", {
            buffer = buf,
            once = true,
            callback = function(args)
              vim.schedule(function()
                local exit_code = vim.v.event and vim.v.event.status or -1
                if exit_code == 0 then
                  local apk = find_apk(module, var)
                  if apk then
                    state.set("last_apk_path", apk)
                    state.save()
                    vim.notify("Build succeeded, deploying...", vim.log.levels.INFO)
                    devices.install_apk(apk)
                    vim.defer_fn(function()
                      devices.launch_app()
                    end, 3000)
                  else
                    vim.notify("Build succeeded but APK not found", vim.log.levels.WARN)
                  end
                end
              end)
            end,
          })
        end
      end
    end

    if variant then
      do_build(variant)
    else
      select_variant(do_build)
    end
  end)
end

function M.assemble(opts)
  opts = opts or {}
  local gradlew = get_gradlew()
  if not gradlew then
    vim.notify("gradlew not found", vim.log.levels.ERROR)
    return
  end

  select_module(function(module)
    local function do_assemble(variant)
      local task_name = string.format(":%s:assemble%s", module, capitalize(variant))
      local cmd = gradlew .. " " .. task_name

      state.set("last_build_cmd", cmd)
      state.save()

      require("core.tasks").run_task({
        name = "android: assemble " .. variant,
        cmd = cmd,
        desc = "Assemble " .. module .. " " .. variant,
        cwd = state.get("project_root"),
      })
    end

    local variant = opts.variant or state.get("selected_variant")
    if variant then
      do_assemble(variant)
    else
      select_variant(do_assemble)
    end
  end)
end

function M.deploy()
  local apk = state.get("last_apk_path")
  if not apk then
    vim.notify("No APK built yet. Run build first.", vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(apk) == 0 then
    vim.notify("APK not found: " .. apk, vim.log.levels.ERROR)
    return
  end
  devices.install_apk(apk)
  vim.defer_fn(function()
    devices.launch_app()
  end, 3000)
end

function M.clean()
  local gradlew = get_gradlew()
  if not gradlew then
    vim.notify("gradlew not found", vim.log.levels.ERROR)
    return
  end
  require("core.tasks").run_task({
    name = "android: clean",
    cmd = gradlew .. " clean",
    desc = "Clean project",
    cwd = state.get("project_root"),
  })
end

function M.repeat_last()
  local cmd = state.get("last_build_cmd")
  if not cmd then
    vim.notify("No previous build to repeat", vim.log.levels.WARN)
    return
  end
  require("core.tasks").run_task({
    name = "android: repeat",
    cmd = cmd,
    desc = "Repeat last build",
    cwd = state.get("project_root"),
  })
end

function M.parse_build_errors(output)
  local qf_items = {}
  for _, line in ipairs(output) do
    local file, lnum, col, msg = line:match("^e:%s*(.+):(%d+):(%d+):%s*(.+)$")
    if not file then
      file, lnum, msg = line:match("^(.+):(%d+):%s*error:%s*(.+)$")
      col = "1"
    end
    if file and lnum then
      table.insert(qf_items, {
        filename = file,
        lnum = tonumber(lnum),
        col = tonumber(col) or 1,
        text = msg,
        type = "E",
      })
    end
  end
  if #qf_items > 0 then
    vim.fn.setqflist(qf_items)
    vim.cmd("copen")
  end
  return qf_items
end

return M
