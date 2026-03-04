# Project Buffer — Tasks Display + New Session

## Summary

Extend `project_manager` with two features: (1) show open tasks (from `proc.ui.current_plan`) per live session, grouped under each project root, and (2) allow starting a new AI session for a specific project directly from the project buffer.

## Data Changes (`projects.lua`)

### Task collection in `collect_live_sessions`

For each live session, read `proc.ui.current_plan` and attach as `plan_items`. Count non-completed items as `open_task_count`.

```lua
-- In collect_live_sessions, after building the session entry:
local plan = proc.ui and proc.ui.current_plan or {}
local open_tasks = {}
for _, item in ipairs(plan) do
  if item.status ~= "completed" then
    table.insert(open_tasks, {
      content = item.content or item.activeForm or "",
      status = item.status or "pending",
    })
  end
end

-- Add to session entry:
session.plan_items = open_tasks
session.open_task_count = #open_tasks
```

## Visual Layout Update (`init.lua`)

```
vbet_easy_2/
  ◐ Claude  se-2026-03-04.chat (15)  3
      ◐ Ask clarifying questions
      ○ Propose approaches
      ○ Present design
  ● Claude  3.1.0-2026-03-04.chat (42)
nvim/
    Claude  (saved 2h ago)
dotfiles/
```

- Task lines: 6-space indent, status icon + content text
- Only shown for live sessions with non-empty `plan_items`
- Task count on session line after msg count
- Entry type: `"task"` — CR opens parent session's chat buffer

### Status Icons (reuse existing)

- `◐` in_progress
- `○` pending

Completed tasks are not shown.

## New Session from Project (`init.lua`)

### Keymaps

| Key | Context | Action |
|-----|---------|--------|
| `n` | Project line | Start new session at project root, default provider |
| `s` | Project line | Pick provider, then start session at project root |

### Implementation

```lua
local function start_session_at_project(entry, provider_id)
  M.close()
  vim.cmd("cd " .. vim.fn.fnameescape(entry.path))
  local ai_repl = require("ai_repl")
  if provider_id then
    ai_repl.new_session(provider_id)
  else
    ai_repl.open_chat_buffer()
  end
end
```

For `s` (pick provider): call `ai_repl.pick_provider(callback)` where callback calls `start_session_at_project` with the chosen provider.

## Help Screen Update

Add to help text:

```
  On project:
  n            New session (default provider)
  s            New session (pick provider)
```

## Dependencies

No new dependencies. Uses existing:
- `proc.ui.current_plan` from `ai_repl` session state
- `ai_repl.new_session()` / `ai_repl.open_chat_buffer()` for session creation
- `ai_repl.pick_provider()` for provider selection
