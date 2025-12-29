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
        lint.try_lint()
      end,
    })

    -- Manual lint command
    vim.keymap.set("n", "<leader>cl", function()
      lint.try_lint()
    end, { desc = "Trigger linting for current file" })
  end,
}