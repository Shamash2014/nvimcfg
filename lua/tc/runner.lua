local M = {}

local state = {
  tests = {},
  source_file = nil,
  source_bufnr = nil,
  source_winid = nil,
  runner_bufnr = nil,
  runner_winid = nil,
  current_test_idx = 1,
  current_step_idx = 1,
  results = {},
  bugs = {},
  start_time = nil,
  test_start_time = nil,
}

local function reset_state()
  state = {
    tests = {},
    source_file = nil,
    source_bufnr = nil,
    source_winid = nil,
    runner_bufnr = nil,
    runner_winid = nil,
    current_test_idx = 1,
    current_step_idx = 1,
    results = {},
    bugs = {},
    start_time = nil,
    test_start_time = nil,
  }
end

local function get_current_test()
  return state.tests[state.current_test_idx]
end

local function get_test_result(test_idx)
  local test = state.tests[test_idx]
  if not test then return nil end
  if not state.results[test.id] then
    state.results[test.id] = {
      status = "pending",
      steps = {},
      duration = nil,
      timestamp = nil,
      actual = nil,
      screenshot = nil,
      notes = nil,
      skip_reason = nil,
      failed_step = nil,
    }
  end
  return state.results[test.id]
end

local function wrap_text(text, width)
  local wrapped = {}
  local line = ""
  for word in text:gmatch("%S+") do
    if #line + #word + 1 > width then
      if #line > 0 then
        table.insert(wrapped, line)
      end
      line = word
    else
      line = #line > 0 and (line .. " " .. word) or word
    end
  end
  if #line > 0 then
    table.insert(wrapped, line)
  end
  return wrapped
end

local function render_runner()
  if not state.runner_bufnr or not vim.api.nvim_buf_is_valid(state.runner_bufnr) then
    return
  end

  local test = get_current_test()
  if not test then return end

  local result = get_test_result(state.current_test_idx)
  local lines = {}
  local width = 54

  table.insert(lines, "┌" .. string.rep("─", width - 2) .. "┐")

  local title = test.id .. ": " .. test.name
  if #title > width - 4 then
    title = title:sub(1, width - 7) .. "..."
  end
  table.insert(lines, "│ " .. title .. string.rep(" ", width - 4 - #title) .. " │")

  local meta = string.format("[%d/%d]", state.current_test_idx, #state.tests)
  if test.priority then
    meta = meta .. " Priority: " .. test.priority
  end
  if test.type then
    meta = meta .. " | " .. test.type
  end
  table.insert(lines, "│ " .. meta .. string.rep(" ", width - 4 - #meta) .. " │")

  table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")

  if #test.preconditions > 0 then
    table.insert(lines, "│ PRECONDITIONS:" .. string.rep(" ", width - 17) .. "│")
    for _, pre in ipairs(test.preconditions) do
      local wrapped = wrap_text(pre, width - 6)
      for j, wline in ipairs(wrapped) do
        local prefix = j == 1 and " • " or "   "
        table.insert(lines, "│" .. prefix .. wline .. string.rep(" ", width - 4 - #wline) .. " │")
      end
    end
    table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
  end

  table.insert(lines, "│ STEPS:" .. string.rep(" ", width - 9) .. "│")
  for i, step in ipairs(test.steps) do
    local step_result = result.steps[i]
    local icon = "  "
    if step_result == "passed" then
      icon = "✓ "
    elseif step_result == "failed" then
      icon = "✗ "
    elseif i == state.current_step_idx then
      icon = "▸ "
    end

    local step_header = string.format("%s%d. ", icon, step.number)
    local wrapped = wrap_text(step.text, width - 6 - #step_header)

    for j, wline in ipairs(wrapped) do
      local prefix = j == 1 and (" " .. step_header) or string.rep(" ", #step_header + 1)
      local content = prefix .. wline
      table.insert(lines, "│" .. content .. string.rep(" ", width - 3 - #content) .. " │")
    end

    if step.expected and step.expected ~= "" then
      local exp_wrapped = wrap_text("→ " .. step.expected, width - 10)
      for _, eline in ipairs(exp_wrapped) do
        table.insert(lines, "│     " .. eline .. string.rep(" ", width - 8 - #eline) .. " │")
      end
    end
  end

  if #test.expected > 0 and not (test.steps[1] and test.steps[1].expected) then
    table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
    table.insert(lines, "│ EXPECTED RESULTS:" .. string.rep(" ", width - 20) .. "│")
    for _, exp in ipairs(test.expected) do
      local wrapped = wrap_text(exp, width - 6)
      for j, wline in ipairs(wrapped) do
        local prefix = j == 1 and " • " or "   "
        table.insert(lines, "│" .. prefix .. wline .. string.rep(" ", width - 4 - #wline) .. " │")
      end
    end
  end

  if #test.postconditions > 0 then
    table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
    table.insert(lines, "│ POSTCONDITIONS:" .. string.rep(" ", width - 18) .. "│")
    for _, post in ipairs(test.postconditions) do
      local wrapped = wrap_text(post, width - 6)
      for j, wline in ipairs(wrapped) do
        local prefix = j == 1 and " • " or "   "
        table.insert(lines, "│" .. prefix .. wline .. string.rep(" ", width - 4 - #wline) .. " │")
      end
    end
  end

  if result.status ~= "pending" then
    table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
    local status_icon = result.status == "passed" and "✓" or (result.status == "failed" and "✗" or "○")
    local status_line = " STATUS: " .. status_icon .. " " .. result.status:upper()
    table.insert(lines, "│" .. status_line .. string.rep(" ", width - 3 - #status_line) .. " │")
    if result.skip_reason then
      local reason = " Reason: " .. result.skip_reason
      if #reason > width - 4 then reason = reason:sub(1, width - 7) .. "..." end
      table.insert(lines, "│" .. reason .. string.rep(" ", width - 3 - #reason) .. " │")
    end
    if result.actual then
      table.insert(lines, "│ Actual:" .. string.rep(" ", width - 10) .. "│")
      local wrapped = wrap_text(result.actual, width - 6)
      for _, wline in ipairs(wrapped) do
        table.insert(lines, "│   " .. wline .. string.rep(" ", width - 6 - #wline) .. " │")
      end
    end
    if result.screenshot then
      local ss = " Screenshot: " .. result.screenshot
      if #ss > width - 4 then ss = ss:sub(1, width - 7) .. "..." end
      table.insert(lines, "│" .. ss .. string.rep(" ", width - 3 - #ss) .. " │")
    end
  end

  if #state.bugs > 0 then
    table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
    local bugs_line = string.format(" BUGS FILED: %d", #state.bugs)
    table.insert(lines, "│" .. bugs_line .. string.rep(" ", width - 3 - #bugs_line) .. " │")
  end

  table.insert(lines, "├" .. string.rep("─", width - 2) .. "┤")
  table.insert(lines, "│ [p] Pass  [f] Fail  [s] Skip  [r] Retest" .. string.rep(" ", width - 44) .. " │")
  table.insert(lines, "│ [b] Bug   [a] Screenshot  [x] Remove" .. string.rep(" ", width - 40) .. " │")
  table.insert(lines, "│ [n/j] Next step    [N/k] Prev step" .. string.rep(" ", width - 38) .. " │")
  table.insert(lines, "│ []] Next test  [[] Prev test  [q] Quit" .. string.rep(" ", width - 42) .. " │")
  table.insert(lines, "└" .. string.rep("─", width - 2) .. "┘")

  vim.api.nvim_buf_set_option(state.runner_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.runner_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.runner_bufnr, "modifiable", false)
end

local function sync_source_position()
  local test = get_current_test()
  if not test or not state.source_winid or not vim.api.nvim_win_is_valid(state.source_winid) then
    return
  end
  vim.api.nvim_win_set_cursor(state.source_winid, { test.line_number, 0 })
  vim.api.nvim_set_current_win(state.source_winid)
  vim.cmd("normal! zz")
  vim.api.nvim_set_current_win(state.runner_winid)
end

local function next_step()
  local test = get_current_test()
  if not test then return end
  if state.current_step_idx < #test.steps then
    state.current_step_idx = state.current_step_idx + 1
    render_runner()
  end
end

local function prev_step()
  if state.current_step_idx > 1 then
    state.current_step_idx = state.current_step_idx - 1
    render_runner()
  end
end

local function next_test()
  if state.current_test_idx < #state.tests then
    state.current_test_idx = state.current_test_idx + 1
    state.current_step_idx = 1
    state.test_start_time = os.time()
    render_runner()
    sync_source_position()
  end
end

local function prev_test()
  if state.current_test_idx > 1 then
    state.current_test_idx = state.current_test_idx - 1
    state.current_step_idx = 1
    state.test_start_time = os.time()
    render_runner()
    sync_source_position()
  end
end

local function mark_step_passed()
  local test = get_current_test()
  local result = get_test_result(state.current_test_idx)
  if not test or not result then return end

  result.steps[state.current_step_idx] = "passed"

  if state.current_step_idx < #test.steps then
    state.current_step_idx = state.current_step_idx + 1
  else
    result.status = "passed"
    result.duration = os.time() - state.test_start_time
    result.timestamp = os.date("%Y-%m-%d %H:%M")
    if state.current_test_idx < #state.tests then
      next_test()
    else
      render_runner()
      vim.notify("All tests completed!", vim.log.levels.INFO)
    end
  end
  render_runner()
end

local function mark_test_passed()
  local test = get_current_test()
  local result = get_test_result(state.current_test_idx)
  if not test or not result then return end

  for i = 1, #test.steps do
    result.steps[i] = "passed"
  end
  result.status = "passed"
  result.duration = os.time() - state.test_start_time
  result.timestamp = os.date("%Y-%m-%d %H:%M")

  if state.current_test_idx < #state.tests then
    next_test()
  else
    render_runner()
    vim.notify("All tests completed!", vim.log.levels.INFO)
  end
end

local function mark_test_failed()
  local test = get_current_test()
  local result = get_test_result(state.current_test_idx)
  if not test or not result then return end

  vim.ui.input({ prompt = "Actual result (observed behavior): " }, function(actual)
    if actual and actual ~= "" then
      result.actual = actual
      result.steps[state.current_step_idx] = "failed"
      result.failed_step = state.current_step_idx
      result.status = "failed"
      result.duration = os.time() - state.test_start_time
      result.timestamp = os.date("%Y-%m-%d %H:%M")

      vim.ui.input({ prompt = "Notes (optional): " }, function(notes)
        if notes and notes ~= "" then
          result.notes = notes
        end

        if state.current_test_idx < #state.tests then
          next_test()
        else
          render_runner()
          vim.notify("All tests completed!", vim.log.levels.INFO)
        end
      end)
    end
  end)
end

local function mark_test_skipped()
  local result = get_test_result(state.current_test_idx)
  if not result then return end

  vim.ui.input({ prompt = "Skip reason: " }, function(reason)
    if reason and reason ~= "" then
      result.status = "skipped"
      result.skip_reason = reason
      result.duration = 0
      result.timestamp = os.date("%Y-%m-%d %H:%M")

      if state.current_test_idx < #state.tests then
        next_test()
      else
        render_runner()
        vim.notify("All tests completed!", vim.log.levels.INFO)
      end
    end
  end)
end

local function attach_screenshot()
  local result = get_test_result(state.current_test_idx)
  if not result then return end

  vim.ui.input({ prompt = "Screenshot path: " }, function(path)
    if path and path ~= "" then
      result.screenshot = path
      render_runner()
      vim.notify("Screenshot attached: " .. path, vim.log.levels.INFO)
    end
  end)
end

local function file_bug()
  local test = get_current_test()
  if not test then return end

  vim.ui.input({ prompt = "Bug title: " }, function(title)
    if not title or title == "" then return end

    vim.ui.input({ prompt = "Description: " }, function(description)
      if not description or description == "" then return end

      vim.ui.input({ prompt = "Severity (critical/major/minor/trivial): " }, function(severity)
        severity = severity or "major"

        vim.ui.input({ prompt = "Screenshot path (optional): " }, function(screenshot)
          local bug = {
            id = string.format("BUG-%03d", #state.bugs + 1),
            title = title,
            description = description,
            severity = severity,
            screenshot = screenshot ~= "" and screenshot or nil,
            test_id = test.id,
            test_name = test.name,
            step = state.current_step_idx,
            step_text = test.steps[state.current_step_idx] and test.steps[state.current_step_idx].text or nil,
            timestamp = os.date("%Y-%m-%d %H:%M"),
          }
          table.insert(state.bugs, bug)
          render_runner()
          vim.notify("Bug filed: " .. bug.id .. " - " .. title, vim.log.levels.INFO)
        end)
      end)
    end)
  end)
end

local function remove_test()
  if #state.tests <= 1 then
    vim.notify("Cannot remove last test", vim.log.levels.WARN)
    return
  end

  local test = get_current_test()
  if not test then return end

  vim.ui.select({ "Yes", "No" }, { prompt = "Remove " .. test.id .. "?" }, function(choice)
    if choice == "Yes" then
      local removed_id = test.id
      table.remove(state.tests, state.current_test_idx)

      if state.current_test_idx > #state.tests then
        state.current_test_idx = #state.tests
      end
      state.current_step_idx = 1
      state.test_start_time = os.time()

      render_runner()
      sync_source_position()
      vim.notify("Removed: " .. removed_id, vim.log.levels.INFO)
    end
  end)
end

local function retest_current()
  local test = get_current_test()
  if not test then return end

  state.results[test.id] = {
    status = "pending",
    steps = {},
    duration = nil,
    timestamp = nil,
    actual = nil,
    screenshot = nil,
    notes = nil,
    skip_reason = nil,
    failed_step = nil,
  }
  state.current_step_idx = 1
  state.test_start_time = os.time()

  render_runner()
  vim.notify("Re-testing: " .. test.id, vim.log.levels.INFO)
end

local function close_runner()
  local results_module = require("tc.results")
  local issues_module = require("tc.issues")

  results_module.write_results(state.source_file, state.tests, state.results, state.start_time)
  issues_module.write_issues(state.source_file, state.tests, state.results, state.bugs)

  if state.runner_winid and vim.api.nvim_win_is_valid(state.runner_winid) then
    vim.api.nvim_win_close(state.runner_winid, true)
  end
  if state.runner_bufnr and vim.api.nvim_buf_is_valid(state.runner_bufnr) then
    vim.api.nvim_buf_delete(state.runner_bufnr, { force = true })
  end

  vim.notify("Test run completed. Results saved.", vim.log.levels.INFO)
  reset_state()
end

local function setup_keymaps()
  local opts = { noremap = true, silent = true, buffer = state.runner_bufnr }

  vim.keymap.set("n", "p", mark_test_passed, opts)
  vim.keymap.set("n", "f", mark_test_failed, opts)
  vim.keymap.set("n", "s", mark_test_skipped, opts)
  vim.keymap.set("n", "x", remove_test, opts)
  vim.keymap.set("n", "r", retest_current, opts)
  vim.keymap.set("n", "a", attach_screenshot, opts)
  vim.keymap.set("n", "b", file_bug, opts)
  vim.keymap.set("n", "n", next_step, opts)
  vim.keymap.set("n", "j", next_step, opts)
  vim.keymap.set("n", "N", prev_step, opts)
  vim.keymap.set("n", "k", prev_step, opts)
  vim.keymap.set("n", "]", next_test, opts)
  vim.keymap.set("n", "[", prev_test, opts)
  vim.keymap.set("n", "q", close_runner, opts)
  vim.keymap.set("n", "<Esc>", close_runner, opts)
end

function M.start(tests, source_file)
  reset_state()

  state.tests = tests
  state.source_file = source_file
  state.source_bufnr = vim.api.nvim_get_current_buf()
  state.source_winid = vim.api.nvim_get_current_win()
  state.start_time = os.time()
  state.test_start_time = os.time()

  vim.cmd("leftabove vsplit")
  state.runner_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, state.runner_bufnr)
  state.runner_winid = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_option(state.runner_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(state.runner_bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.runner_bufnr, "swapfile", false)
  vim.api.nvim_buf_set_name(state.runner_bufnr, "WildTest")

  vim.api.nvim_win_set_width(state.runner_winid, 56)

  setup_keymaps()
  render_runner()
  sync_source_position()
end

function M.start_at_test(tests, source_file, test_idx)
  M.start(tests, source_file)
  if test_idx and test_idx > 0 and test_idx <= #tests then
    state.current_test_idx = test_idx
    state.current_step_idx = 1
    render_runner()
    sync_source_position()
  end
end

function M.get_state()
  return state
end

return M
