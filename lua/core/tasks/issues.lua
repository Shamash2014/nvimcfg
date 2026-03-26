local M = {}

local function get_output_path(source_file)
  local base = source_file:gsub("%.md$", "")
  return base .. "_issues.md"
end

function M.write_issues(source_file, tests, results, bugs)
  bugs = bugs or {}
  local failures = {}
  for _, test in ipairs(tests) do
    local result = results[test.id]
    if result and result.status == "failed" then
      table.insert(failures, { test = test, result = result })
    end
  end

  if #failures == 0 and #bugs == 0 then
    return nil
  end

  local lines = {}
  local run_date = os.date("%Y-%m-%d %H:%M")
  local suite_name = source_file:match("([^/]+)%.md$") or "Tests"

  table.insert(lines, "# Issues from " .. suite_name .. " Run")
  table.insert(lines, "**Generated:** " .. run_date)
  table.insert(lines, "")

  if #bugs > 0 or #failures > 0 then
    table.insert(lines, "## Summary")
    table.insert(lines, string.format("- **Bugs Filed:** %d", #bugs))
    table.insert(lines, string.format("- **Failed Tests:** %d", #failures))
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  if #bugs > 0 then
    table.insert(lines, "# Bugs")
    table.insert(lines, "")

    for _, bug in ipairs(bugs) do
      table.insert(lines, string.format("## %s: %s", bug.id, bug.title))
      table.insert(lines, "")
      table.insert(lines, "| Field | Value |")
      table.insert(lines, "|-------|-------|")
      table.insert(lines, "| **Severity** | " .. (bug.severity or "major") .. " |")
      table.insert(lines, "| **Test Case** | " .. bug.test_id .. " |")
      table.insert(lines, "| **Step** | " .. (bug.step or "-") .. " |")
      table.insert(lines, "| **Timestamp** | " .. bug.timestamp .. " |")
      table.insert(lines, "")

      table.insert(lines, "### Description")
      table.insert(lines, bug.description)
      table.insert(lines, "")

      if bug.step_text then
        table.insert(lines, "### Context")
        table.insert(lines, "**During step:** " .. bug.step_text)
        table.insert(lines, "")
      end

      if bug.screenshot then
        table.insert(lines, "### Screenshot")
        table.insert(lines, string.format("![%s](%s)", bug.id, bug.screenshot))
        table.insert(lines, "")
      end

      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  if #failures > 0 then
    table.insert(lines, "# Failed Tests")
    table.insert(lines, "")

    for _, item in ipairs(failures) do
      local test = item.test
      local result = item.result

      table.insert(lines, string.format("## %s: %s", test.id, test.name))
      table.insert(lines, "")
      table.insert(lines, "| Field | Value |")
      table.insert(lines, "|-------|-------|")
      if test.priority then
        table.insert(lines, "| **Priority** | " .. test.priority .. " |")
      end
      if #test.tags > 0 then
        table.insert(lines, "| **Tags** | " .. table.concat(test.tags, ", ") .. " |")
      end
      if result.timestamp then
        table.insert(lines, "| **Tested At** | " .. result.timestamp .. " |")
      end
      table.insert(lines, "")

      table.insert(lines, "### Summary")
      local summary = test.name
      if result.failed_step and test.steps[result.failed_step] then
        summary = summary .. " - failed at: " .. test.steps[result.failed_step].text
      end
      table.insert(lines, summary)
      table.insert(lines, "")

      table.insert(lines, "### Steps to Reproduce")
      for i, step in ipairs(test.steps) do
        table.insert(lines, string.format("%d. %s", i, step.text))
      end
      table.insert(lines, "")

      table.insert(lines, "### Expected Result")
      for _, exp in ipairs(test.expected) do
        table.insert(lines, "- " .. exp)
      end
      table.insert(lines, "")

      table.insert(lines, "### Actual Result")
      if result.actual then
        table.insert(lines, "- " .. result.actual)
      else
        table.insert(lines, "- No actual result recorded")
      end
      table.insert(lines, "")

      if result.screenshot then
        table.insert(lines, "### Evidence")
        table.insert(lines, string.format("![Screenshot](%s)", result.screenshot))
        table.insert(lines, "")
      end

      table.insert(lines, "### Environment")
      table.insert(lines, "- Tester: " .. (vim.fn.expand("$USER") or "unknown"))
      table.insert(lines, "- Date: " .. run_date)
      table.insert(lines, "")

      if result.notes then
        table.insert(lines, "### Notes")
        table.insert(lines, result.notes)
        table.insert(lines, "")
      end

      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end

  local output_path = get_output_path(source_file)
  vim.fn.writefile(lines, output_path)
  vim.notify("Issues written to: " .. output_path, vim.log.levels.INFO)

  return output_path
end

function M.open_issues(source_file)
  local output_path = get_output_path(source_file)
  if vim.fn.filereadable(output_path) == 1 then
    vim.cmd("edit " .. output_path)
  else
    vim.notify("No issues file found: " .. output_path, vim.log.levels.WARN)
  end
end

return M
