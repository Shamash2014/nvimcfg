local M = {}

local function get_output_path(source_file)
  local base = source_file:gsub("%.md$", "")
  return base .. "_results.md"
end

local function format_duration(seconds)
  if not seconds or seconds == 0 then
    return "0s"
  end
  local mins = math.floor(seconds / 60)
  local secs = seconds % 60
  if mins > 0 then
    return string.format("%dm %ds", mins, secs)
  end
  return string.format("%ds", secs)
end

function M.write_results(source_file, tests, results, _)
  local lines = {}
  local tester = vim.fn.expand("$USER") or "unknown"
  local run_date = os.date("%Y-%m-%d %H:%M")

  local passed = 0
  local failed = 0
  local skipped = 0

  for _, test in ipairs(tests) do
    local result = results[test.id]
    if result then
      if result.status == "passed" then
        passed = passed + 1
      elseif result.status == "failed" then
        failed = failed + 1
      elseif result.status == "skipped" then
        skipped = skipped + 1
      end
    end
  end

  local total = passed + failed + skipped
  local pass_rate = total > 0 and math.floor((passed / total) * 100) or 0

  local suite_name = source_file:match("([^/]+)%.md$") or "Tests"
  suite_name = suite_name:gsub("_", " "):gsub("^%l", string.upper)

  table.insert(lines, "# Test Results: " .. suite_name)
  table.insert(lines, "**Run Date:** " .. run_date)
  table.insert(lines, "**Tester:** " .. tester)
  table.insert(lines, "**Environment:** local")
  table.insert(lines, "")
  table.insert(lines, "## Summary")
  table.insert(lines, "| Total | Passed | Failed | Skipped |")
  table.insert(lines, "|-------|--------|--------|---------|")
  table.insert(lines, string.format("| %d     | %d      | %d      | %d       |", total, passed, failed, skipped))
  table.insert(lines, "")
  table.insert(lines, "**Pass Rate:** " .. pass_rate .. "%")
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  for _, test in ipairs(tests) do
    local result = results[test.id]
    if result and result.status ~= "pending" then
      local status_upper = result.status:upper()
      table.insert(lines, string.format("## %s: %s - %s", test.id, test.name, status_upper))
      table.insert(lines, "**Duration:** " .. format_duration(result.duration))
      if result.timestamp then
        table.insert(lines, "**Completed:** " .. result.timestamp)
      end

      if result.status == "passed" then
        table.insert(lines, "**All steps completed successfully**")
      elseif result.status == "failed" then
        if result.failed_step and test.steps[result.failed_step] then
          local step = test.steps[result.failed_step]
          table.insert(lines, string.format('**Failed Step:** %d - "%s"', result.failed_step, step.text))
        end

        table.insert(lines, "")
        table.insert(lines, "### Expected")
        for _, exp in ipairs(test.expected) do
          table.insert(lines, "- " .. exp)
        end

        table.insert(lines, "")
        table.insert(lines, "### Actual (Observed)")
        if result.actual then
          table.insert(lines, "- " .. result.actual)
        else
          table.insert(lines, "- No actual result recorded")
        end

        if result.screenshot then
          table.insert(lines, "")
          table.insert(lines, "### Screenshot")
          table.insert(lines, string.format("![%s failure](%s)", test.id, result.screenshot))
        end

        if result.notes then
          table.insert(lines, "")
          table.insert(lines, "### Notes")
          table.insert(lines, result.notes)
        end
      elseif result.status == "skipped" then
        table.insert(lines, "**Reason:** " .. (result.skip_reason or "No reason provided"))
      end

      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  local output_path = get_output_path(source_file)
  vim.fn.writefile(lines, output_path)
  vim.notify("Results written to: " .. output_path, vim.log.levels.INFO)

  return output_path
end

function M.open_results(source_file)
  local output_path = get_output_path(source_file)
  if vim.fn.filereadable(output_path) == 1 then
    vim.cmd("edit " .. output_path)
  else
    vim.notify("No results file found: " .. output_path, vim.log.levels.WARN)
  end
end

return M
