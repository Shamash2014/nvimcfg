local M = {}

function M.setup()
  local state = require("android.state")
  local sdk_mod = require("android.sdk")

  sdk_mod.find_sdk()
  local gradlew = sdk_mod.find_gradlew()
  if not gradlew then
    return
  end

  if not sdk_mod.detect_android_project() then
    return
  end

  sdk_mod.resolve_tools()
  sdk_mod.parse_build_gradle()
  sdk_mod.find_modules()
  state.load()

  local build = require("android.build")
  local logcat = require("android.logcat")
  local devices = require("android.devices")
  local run = require("android.run")

  vim.api.nvim_create_user_command("AndroidMenu", function() run.android_menu() end, {})
  vim.api.nvim_create_user_command("AndroidBuild", function(opts)
    build.build_and_deploy({ variant = opts.args ~= "" and opts.args or nil })
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("AndroidAssemble", function(opts)
    build.assemble({ variant = opts.args ~= "" and opts.args or nil })
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("AndroidDeploy", function() build.deploy() end, {})
  vim.api.nvim_create_user_command("AndroidLogcat", function() logcat.toggle() end, {})
  vim.api.nvim_create_user_command("AndroidDevices", function() devices.select_device() end, {})
  vim.api.nvim_create_user_command("AndroidClean", function() build.clean() end, {})
  vim.api.nvim_create_user_command("AndroidGradleTasks", function() run.browse_gradle_tasks() end, {})
  vim.api.nvim_create_user_command("AndroidHealth", function() sdk_mod.health_check() end, {})
  vim.api.nvim_create_user_command("AndroidEmulatorStart", function() devices.launch_emulator() end, {})
  vim.api.nvim_create_user_command("AndroidEmulatorStop", function() devices.stop_emulator() end, {})

  local map = vim.keymap.set
  local opts = { silent = true }

  local function o(desc)
    return vim.tbl_extend("force", opts, { desc = desc })
  end

  map("n", "<leader>nn", function() run.android_menu() end, o("Android Menu"))
  map("n", "<leader>nb", function() build.build_and_deploy() end, o("Build & Deploy"))
  map("n", "<leader>na", function() build.assemble() end, o("Assemble APK"))
  map("n", "<leader>nl", function() logcat.toggle() end, o("Toggle Logcat"))
  map("n", "<leader>nd", function() devices.select_device() end, o("Select Device"))
  map("n", "<leader>ne", function() devices.launch_emulator() end, o("Launch Emulator"))
  map("n", "<leader>nc", function() build.clean() end, o("Clean Project"))
  map("n", "<leader>ng", function() run.browse_gradle_tasks() end, o("Gradle Tasks"))
  map("n", "<leader>nr", function() build.repeat_last() end, o("Repeat Last Build"))
  map("n", "<leader>nh", function() sdk_mod.health_check() end, o("Health Check"))
  map("n", "<leader>ns", function() run.show_state() end, o("Show State"))

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "kotlin", "java" },
    group = vim.api.nvim_create_augroup("AndroidLocalKeymaps", { clear = true }),
    callback = function(args)
      local buf_opts = { buffer = args.buf, silent = true }

      local function bo(desc)
        return vim.tbl_extend("force", buf_opts, { desc = desc })
      end

      map("n", "<localleader>b", function() build.build_and_deploy() end, bo("Build & Deploy"))
      map("n", "<localleader>a", function() build.assemble() end, bo("Assemble"))
      map("n", "<localleader>l", function() logcat.toggle() end, bo("Toggle Logcat"))
      map("n", "<localleader>d", function() devices.select_device() end, bo("Select Device"))
      map("n", "<localleader>r", function() build.repeat_last() end, bo("Repeat Build"))
      map("n", "<localleader>m", function() run.android_menu() end, bo("Android Menu"))
    end,
  })
end

return M
