return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufNewFile", "BufWritePost" },
  config = function()
    local lint = require("lint")

    -- Helper function to check if a command exists
    local function command_exists(cmd)
      return vim.fn.executable(cmd) == 1
    end

    -- Only use eslint_d if it's installed
    local js_linters = {}
    if command_exists("eslint_d") then
      js_linters = { "eslint_d" }
    elseif command_exists("eslint") then
      js_linters = { "eslint" }
    end

    lint.linters_by_ft = {
      javascript = js_linters,
      typescript = js_linters,
      javascriptreact = js_linters,
      typescriptreact = js_linters,
      vue = js_linters,
    }

    -- Remove eslint/eslint_d linters if commands don't exist
    if not command_exists("eslint") and not command_exists("eslint_d") then
      lint.linters_by_ft.javascript = nil
      lint.linters_by_ft.typescript = nil
      lint.linters_by_ft.javascriptreact = nil
      lint.linters_by_ft.typescriptreact = nil
      lint.linters_by_ft.vue = nil
    end

    -- Only add linters if they exist
    if command_exists("ruff") then
      lint.linters_by_ft.python = { "ruff" }
    end
    if command_exists("golangcilint") then
      lint.linters_by_ft.go = { "golangcilint" }
    end
    if command_exists("cargo") and command_exists("clippy") then
      lint.linters_by_ft.rust = { "clippy" }
    end
    if command_exists("luacheck") then
      lint.linters_by_ft.lua = { "luacheck" }
    end
    if command_exists("hadolint") then
      lint.linters_by_ft.dockerfile = { "hadolint" }
    end
    if command_exists("yamllint") then
      lint.linters_by_ft.yaml = { "yamllint" }
    end
    if command_exists("jsonlint") then
      lint.linters_by_ft.json = { "jsonlint" }
    end
    if command_exists("markdownlint") then
      lint.linters_by_ft.markdown = { "markdownlint" }
    end
    if command_exists("shellcheck") then
      lint.linters_by_ft.sh = { "shellcheck" }
      lint.linters_by_ft.bash = { "shellcheck" }
    end

    -- Custom linter configurations
    if lint.linters.luacheck then
      lint.linters.luacheck.args = {
        "--globals", "vim",
        "--formatter", "plain",
        "--codes",
        "--ranges",
        "-"
      }
    end

    if lint.linters.eslint_d then
      lint.linters.eslint_d.args = {
        "--no-warn-ignored",
        "--format", "json",
        "--stdin",
        "--stdin-filename",
        function() return vim.api.nvim_buf_get_name(0) end,
      }
    end

    -- Auto-lint on save and text change
    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function()
        -- Only try to lint if linters are configured for this filetype
        local ft = vim.bo.filetype
        local linters = lint.linters_by_ft[ft]
        if linters and #linters > 0 then
          -- Check if at least one linter command exists
          local linter_available = false
          for _, linter_name in ipairs(linters) do
            if command_exists(linter_name) or command_exists(linter_name:gsub("_", "-")) then
              linter_available = true
              break
            end
          end

          if linter_available then
            pcall(lint.try_lint)
          end
        end
      end,
    })

    -- Manual lint command
    vim.keymap.set("n", "<leader>cl", function()
      lint.try_lint()
    end, { desc = "Trigger linting for current file" })
  end,
}