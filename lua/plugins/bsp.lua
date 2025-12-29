return {
  "nvim-neotest/nvim-nio",
  lazy = true,
  ft = { "swift", "objective-c", "objective-cpp" },
  config = function()
    -- BSP client setup and utilities
    local M = {}

    function M.is_available()
      return vim.fn.executable('xcode-build-server') == 1
    end

    function M.get_build_targets()
      if not M.is_available() then
        return {}
      end

      local result = vim.fn.system("xcode-build-server buildTargets 2>/dev/null")
      if vim.v.shell_error ~= 0 then
        return {}
      end

      local ok, data = pcall(vim.json.decode, result)
      if not ok or not data.targets then
        return {}
      end

      local targets = {}
      for _, target in ipairs(data.targets) do
        table.insert(targets, {
          id = target.id,
          name = target.displayName or target.id,
          language_ids = target.languageIds or {},
        })
      end
      return targets
    end

    function M.setup_autocommands()
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        pattern = { "*.swift", "*.h", "*.m", "*.mm" },
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()

          -- Add BSP-specific commands
          if M.is_available() then
            vim.api.nvim_buf_create_user_command(bufnr, "BSPBuild", function()
              local targets = M.get_build_targets()
              if #targets == 0 then
                vim.notify("No build targets found", vim.log.levels.WARN)
                return
              end

              vim.ui.select(targets, {
                prompt = "Select build target:",
                format_item = function(item) return item.name end,
              }, function(choice)
                if choice then
                  require("snacks").terminal("xcode-build-server build --target " .. choice.id, {
                    win = {
                      position = "bottom",
                      height = 0.3,
                    },
                  })
                end
              end)
            end, { desc = "BSP build target" })

            vim.api.nvim_buf_create_user_command(bufnr, "BSPTest", function()
              local targets = M.get_build_targets()
              if #targets == 0 then
                vim.notify("No build targets found", vim.log.levels.WARN)
                return
              end

              vim.ui.select(targets, {
                prompt = "Select test target:",
                format_item = function(item) return item.name end,
              }, function(choice)
                if choice then
                  require("snacks").terminal("xcode-build-server test --target " .. choice.id, {
                    win = {
                      position = "bottom",
                      height = 0.3,
                    },
                  })
                end
              end)
            end, { desc = "BSP test target" })

            vim.api.nvim_buf_create_user_command(bufnr, "BSPList", function()
              require("snacks").terminal("xcode-build-server buildTargets", {
                win = {
                  position = "bottom",
                  height = 0.4,
                },
              })
            end, { desc = "List BSP targets" })

            vim.api.nvim_buf_create_user_command(bufnr, "BSPCompileCommands", function()
              require("snacks").terminal("xcode-build-server compileCommands", {
                win = {
                  position = "bottom",
                  height = 0.3,
                },
              })
            end, { desc = "Generate compile commands" })
          end
        end,
      })
    end

    -- Setup autocommands
    M.setup_autocommands()

    -- Make functions globally available
    _G.BSP = M

    -- Notify user about BSP availability
    if M.is_available() then
      vim.notify("Xcode Build Server (BSP) detected and configured", vim.log.levels.INFO)
    end
  end,
}