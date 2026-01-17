-- Ralph Wiggum Mode Integration Helper
-- Hooks into agent responses to auto-continue until completion

local M = {}
local render = require("ai_repl.render")

local function format_duration(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  elseif seconds < 3600 then
    return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
  else
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, mins)
  end
end

local function show_summary(buf, ralph)
  local summary = ralph.get_summary()
  if not summary then return end

  local lines = {
    "",
    "┌─ Ralph Wiggum Summary ─────────────────────",
    string.format("│ Iterations: %d", summary.iterations),
    string.format("│ Duration: %s", format_duration(summary.duration_seconds)),
    string.format("│ Total output: %d chars", summary.total_response_chars),
    "└────────────────────────────────────────────",
    "",
  }
  render.append_content(buf, lines)
end

function M.check_and_continue(proc, response_text)
  local modes_module = require("ai_repl.modes")

  if not modes_module.is_ralph_wiggum_mode() then
    return false
  end

  local ralph = require("ai_repl.modes.ralph_wiggum")
  local buf = proc.data.buf

  ralph.record_iteration(response_text)

  local should_continue, reason = ralph.should_continue(response_text)

  if not should_continue then
    local status = ralph.get_status()

    if reason == "max_iterations" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⚠️ Ralph Wiggum: Max iterations reached (" .. status.iteration .. "/" .. status.max_iterations .. ")]",
        })
        show_summary(buf, ralph)
      end)
    elseif reason == "paused" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⏸️ Ralph Wiggum: Paused at iteration " .. status.iteration .. ". Use /ralph resume to continue]",
        })
      end)
      return false
    elseif reason == "stuck" then
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[⚠️ Ralph Wiggum: Detected stuck loop (same response 3x). Stopping.]",
        })
        show_summary(buf, ralph)
      end)
    elseif reason:match("^completed:") then
      local pattern = reason:gsub("^completed:", "")
      vim.schedule(function()
        render.append_content(buf, {
          "",
          "[✅ Ralph Wiggum: Task completed! (" .. status.iteration .. " iterations)]",
        })
        show_summary(buf, ralph)
      end)
    end

    ralph.disable()
    return false
  end

  local status = ralph.get_status()
  local delay = status.backoff_delay

  vim.schedule(function()
    local msg = string.format(
      "[🔄 Ralph Wiggum: Iteration %d/%d - continuing%s...]",
      status.iteration + 1,
      status.max_iterations,
      status.stuck_count > 0 and " (backoff: " .. delay .. "ms)" or ""
    )
    render.append_content(buf, { "", msg })
  end)

  local continuation_prompt = ralph.get_continuation_prompt()

  vim.defer_fn(function()
    if ralph.is_enabled() and not ralph.is_paused() then
      proc:send_prompt(continuation_prompt, { silent = true })
    end
  end, delay)

  return true
end

return M
