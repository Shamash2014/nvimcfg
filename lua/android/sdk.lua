local state = require("android.state")

local M = {}

function M.find_sdk()
  local candidates = {}

  if vim.env.ANDROID_HOME and vim.env.ANDROID_HOME ~= "" then
    table.insert(candidates, vim.env.ANDROID_HOME)
  end
  if vim.env.ANDROID_SDK_ROOT and vim.env.ANDROID_SDK_ROOT ~= "" then
    table.insert(candidates, vim.env.ANDROID_SDK_ROOT)
  end

  local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  local local_props = root .. "/local.properties"
  if vim.fn.filereadable(local_props) == 1 then
    local lines = vim.fn.readfile(local_props)
    for _, line in ipairs(lines) do
      local sdk = line:match("^sdk%.dir%s*=%s*(.+)$")
      if sdk then
        sdk = sdk:gsub("\\:", ":"):gsub("\\\\", "\\")
        table.insert(candidates, sdk)
        break
      end
    end
  end

  local home = vim.env.HOME or ""
  table.insert(candidates, home .. "/Library/Android/sdk")
  table.insert(candidates, home .. "/Android/Sdk")
  table.insert(candidates, home .. "/android-sdk")

  for _, path in ipairs(candidates) do
    local adb = path .. "/platform-tools/adb"
    if vim.fn.executable(adb) == 1 then
      state.set("sdk_path", path)
      return path
    end
  end

  return nil
end

function M.resolve_tools()
  local sdk = state.get("sdk_path")
  local tools = {}

  local tool_paths = {
    adb = sdk and (sdk .. "/platform-tools/adb"),
    emulator = sdk and (sdk .. "/emulator/emulator"),
    avdmanager = sdk and (sdk .. "/cmdline-tools/latest/bin/avdmanager"),
    sdkmanager = sdk and (sdk .. "/cmdline-tools/latest/bin/sdkmanager"),
  }

  if sdk then
    local build_tools_dir = sdk .. "/build-tools"
    local handle = vim.loop.fs_scandir(build_tools_dir)
    if handle then
      local latest = nil
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if type == "directory" then
          if not latest or name > latest then
            latest = name
          end
        end
      end
      if latest then
        tool_paths.aapt2 = build_tools_dir .. "/" .. latest .. "/aapt2"
      end
    end
  end

  for name, path in pairs(tool_paths) do
    if path and vim.fn.executable(path) == 1 then
      tools[name] = path
    else
      local fallback = vim.fn.exepath(name)
      if fallback ~= "" then
        tools[name] = fallback
      end
    end
  end

  state.set("tools", tools)
  return tools
end

function M.find_gradlew()
  local found = vim.fs.find("gradlew", {
    upward = true,
    path = vim.fn.getcwd(),
    type = "file",
  })
  if found and #found > 0 then
    state.set("gradlew", found[1])
    state.set("project_root", vim.fn.fnamemodify(found[1], ":h"))
    return found[1]
  end
  return nil
end

function M.detect_android_project()
  local root = state.get("project_root") or vim.fs.root(0, { ".git" }) or vim.fn.getcwd()

  local manifest_paths = {
    root .. "/AndroidManifest.xml",
    root .. "/app/src/main/AndroidManifest.xml",
    root .. "/src/main/AndroidManifest.xml",
  }
  for _, path in ipairs(manifest_paths) do
    if vim.fn.filereadable(path) == 1 then
      state.set("is_android_project", true)
      return true
    end
  end

  local gradle_files = { "build.gradle", "build.gradle.kts" }
  for _, name in ipairs(gradle_files) do
    local path = root .. "/" .. name
    if vim.fn.filereadable(path) == 1 then
      local content = table.concat(vim.fn.readfile(path), "\n")
      if content:match("android%s*{") or content:match("android%s*%(") then
        state.set("is_android_project", true)
        return true
      end
    end
  end

  local app_gradle_files = { root .. "/app/build.gradle", root .. "/app/build.gradle.kts" }
  for _, path in ipairs(app_gradle_files) do
    if vim.fn.filereadable(path) == 1 then
      local content = table.concat(vim.fn.readfile(path), "\n")
      if content:match("android%s*{") or content:match("android%s*%(") then
        state.set("is_android_project", true)
        return true
      end
    end
  end

  state.set("is_android_project", false)
  return false
end

function M.parse_build_gradle()
  local root = state.get("project_root") or vim.fn.getcwd()
  local module = state.get("selected_module") or "app"
  local gradle_files = {
    root .. "/" .. module .. "/build.gradle.kts",
    root .. "/" .. module .. "/build.gradle",
  }

  local content = nil
  for _, path in ipairs(gradle_files) do
    if vim.fn.filereadable(path) == 1 then
      content = table.concat(vim.fn.readfile(path), "\n")
      break
    end
  end

  if not content then
    return
  end

  local app_id = content:match('applicationId%s*[=%(]%s*"([^"]+)"')
    or content:match("applicationId%s*[=%(]%s*'([^']+)'")
  if app_id then
    state.set("application_id", app_id)
  end

  local build_types = {}
  local bt_block = content:match("buildTypes%s*{(.-)\n%s*}")
  if bt_block then
    for bt in bt_block:gmatch('(%w+)%s*{') do
      table.insert(build_types, bt)
    end
    for bt in bt_block:gmatch('getByName%s*%(%s*"(%w+)"') do
      if not vim.tbl_contains(build_types, bt) then
        table.insert(build_types, bt)
      end
    end
    for bt in bt_block:gmatch('named%s*%(%s*"(%w+)"') do
      if not vim.tbl_contains(build_types, bt) then
        table.insert(build_types, bt)
      end
    end
  end
  if #build_types == 0 then
    build_types = { "debug", "release" }
  end

  local flavors = {}
  local pf_block = content:match("productFlavors%s*{(.-)\n%s*}")
  if pf_block then
    for flavor in pf_block:gmatch('(%w+)%s*{') do
      if flavor ~= "create" and flavor ~= "register" then
        table.insert(flavors, flavor)
      end
    end
  end

  local variants = {}
  if #flavors > 0 then
    for _, flavor in ipairs(flavors) do
      for _, bt in ipairs(build_types) do
        local variant = flavor .. bt:sub(1, 1):upper() .. bt:sub(2)
        table.insert(variants, variant)
      end
    end
  else
    for _, bt in ipairs(build_types) do
      table.insert(variants, bt)
    end
  end

  state.set("variants", variants)
  return {
    application_id = app_id,
    build_types = build_types,
    flavors = flavors,
    variants = variants,
  }
end

function M.find_modules()
  local root = state.get("project_root") or vim.fn.getcwd()
  local settings_files = {
    root .. "/settings.gradle.kts",
    root .. "/settings.gradle",
  }

  local content = nil
  for _, path in ipairs(settings_files) do
    if vim.fn.filereadable(path) == 1 then
      content = table.concat(vim.fn.readfile(path), "\n")
      break
    end
  end

  if not content then
    state.set("modules", { "app" })
    return { "app" }
  end

  local modules = {}
  for mod in content:gmatch('include%s*%(?%s*"([^"]+)"') do
    mod = mod:gsub("^:", "")
    table.insert(modules, mod)
  end
  for mod in content:gmatch("include%s*%(?%s*'([^']+)'") do
    mod = mod:gsub("^:", "")
    table.insert(modules, mod)
  end

  if #modules == 0 then
    modules = { "app" }
  end

  state.set("modules", modules)
  return modules
end

function M.health_check()
  local lines = {}

  local sdk = state.get("sdk_path")
  table.insert(lines, sdk and ("SDK: " .. sdk) or "SDK: NOT FOUND")

  local tools = state.get("tools") or {}
  for _, name in ipairs({ "adb", "emulator", "avdmanager", "sdkmanager", "aapt2" }) do
    local status = tools[name] and "OK" or "MISSING"
    table.insert(lines, string.format("  %s: %s", name, status))
  end

  local gradlew = state.get("gradlew")
  table.insert(lines, gradlew and ("Gradle: " .. gradlew) or "Gradle: NOT FOUND")

  local is_android = state.get("is_android_project")
  table.insert(lines, "Android project: " .. (is_android and "YES" or "NO"))

  local app_id = state.get("application_id")
  if app_id then
    table.insert(lines, "Application ID: " .. app_id)
  end

  local modules = state.get("modules") or {}
  if #modules > 0 then
    table.insert(lines, "Modules: " .. table.concat(modules, ", "))
  end

  local variants = state.get("variants") or {}
  if #variants > 0 then
    table.insert(lines, "Variants: " .. table.concat(variants, ", "))
  end

  local level = sdk and vim.log.levels.INFO or vim.log.levels.WARN
  vim.notify(table.concat(lines, "\n"), level, { title = "Android Health" })
end

return M
