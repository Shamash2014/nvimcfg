local M = {}

local parser = require("tc.parser")
local runner = require("tc.runner")
local results = require("tc.results")
local issues = require("tc.issues")

M.config = {
  keymaps = {
    start = "<leader>ozz",
    pick = "<leader>ozp",
    results = "<leader>ozr",
    issues = "<leader>ozi",
  },
}

local function get_current_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  return filepath, bufnr
end

local function is_markdown_file(filepath)
  return filepath:match("%.md$") ~= nil
end

function M.start_test_run()
  local filepath, bufnr = get_current_file()

  if not is_markdown_file(filepath) then
    vim.notify("Current file is not a markdown file", vim.log.levels.ERROR)
    return
  end

  local parsed = parser.parse_buffer(bufnr)

  if #parsed.tests == 0 then
    vim.notify("No test cases found in file", vim.log.levels.WARN)
    return
  end

  vim.notify(string.format("Found %d test cases", #parsed.tests), vim.log.levels.INFO)
  runner.start(parsed.tests, filepath)
end

function M.pick_test()
  local filepath, bufnr = get_current_file()

  if not is_markdown_file(filepath) then
    vim.notify("Current file is not a markdown file", vim.log.levels.ERROR)
    return
  end

  local parsed = parser.parse_buffer(bufnr)

  if #parsed.tests == 0 then
    vim.notify("No test cases found in file", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, test in ipairs(parsed.tests) do
    table.insert(items, string.format("%d. %s: %s", i, test.id, test.name))
  end

  vim.ui.select(items, { prompt = "Select test:" }, function(choice, idx)
    if choice and idx then
      runner.start_at_test(parsed.tests, filepath, idx)
    end
  end)
end

function M.open_results()
  local filepath = get_current_file()
  if not is_markdown_file(filepath) then
    vim.notify("Current file is not a markdown file", vim.log.levels.ERROR)
    return
  end
  results.open_results(filepath)
end

function M.open_issues()
  local filepath = get_current_file()
  if not is_markdown_file(filepath) then
    vim.notify("Current file is not a markdown file", vim.log.levels.ERROR)
    return
  end
  issues.open_issues(filepath)
end

local function setup_keymaps()
  local opts = { noremap = true, silent = true }

  vim.keymap.set("n", M.config.keymaps.start, M.start_test_run, vim.tbl_extend("force", opts, { desc = "WildTest: Start" }))
  vim.keymap.set("n", M.config.keymaps.pick, M.pick_test, vim.tbl_extend("force", opts, { desc = "WildTest: Pick" }))
  vim.keymap.set("n", M.config.keymaps.results, M.open_results, vim.tbl_extend("force", opts, { desc = "WildTest: Results" }))
  vim.keymap.set("n", M.config.keymaps.issues, M.open_issues, vim.tbl_extend("force", opts, { desc = "WildTest: Issues" }))
end

local function setup_commands()
  vim.api.nvim_create_user_command("WildTest", M.start_test_run, { desc = "Start test run" })
  vim.api.nvim_create_user_command("WildTestPick", M.pick_test, { desc = "Pick test" })
  vim.api.nvim_create_user_command("WildTestResults", M.open_results, { desc = "Open results" })
  vim.api.nvim_create_user_command("WildTestIssues", M.open_issues, { desc = "Open issues" })
end

function M.setup(opts)
  opts = opts or {}

  if opts.keymaps then
    M.config.keymaps = vim.tbl_deep_extend("force", M.config.keymaps, opts.keymaps)
  end

  setup_keymaps()
  setup_commands()
end

return M
