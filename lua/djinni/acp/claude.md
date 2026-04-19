# Claude Code ACP Implementation Notes

## Provider: claude-agent-acp

The `claude-agent-acp` binary is the ACP adapter for Claude Code.
It wraps Claude Code's functionality behind the standard ACP protocol.

## Known Behaviors

### session/set_mode
- The ACP spec defines this as a REQUEST (with response)
- `claude-agent-acp` does NOT implement it — request blocks session, notification rejected
- **WORKAROUND**: Send `/mode <modeId>` as a `session/prompt` message instead
- Claude Code handles `/mode` as a slash command and sends `current_mode_update` event
- `session.set_mode()` in our code wraps this as a prompt call

### session/new Response
Returns: `sessionId`, `configOptions`, `modes`, `models`
- `configOptions` contains model selection options (category="model", type="select")
- `modes.availableModes` contains available SessionMode objects
- `modes.currentModeId` is the default mode

### session/update Events
The following `sessionUpdate` types are observed:
- `agent_message_chunk` - text streaming (content.text)
- `agent_thought_chunk` - thinking text
- `tool_call` - tool started (kind, title, status)
- `tool_call_update` - tool progress/result (status: running/completed/failed/error, content)
- `modes` - mode list update (availableModes, currentModeId)
- `current_mode_update` - mode changed (modeId)
- `plan` - plan entries with status (pending/in_progress/completed)
- `available_commands_update` - slash commands available
- `config_option_update` - config option changed
- `usage_update` - token usage during streaming
- `result` - final result with tokenUsage and cost

### session/request_permission
Agent sends this as a REQUEST to the client.
- `toolCall` has `title`, `kind`, `id`
- `options` array: each has `optionId`, `name`, `kind`
- `kind` values: `allow_once`, `allow_always`, `reject_once`, `reject_always`
- Respond with: `{ outcome: { outcome: "selected", optionId: "..." } }`
- NEVER timeout permission prompts

### Stderr Messages
- "Error handling notification {}" - ACP received a notification it doesn't support (non-fatal)
- "Error handling request {}" - ACP received a request it can't process (e.g., invalid session)
- "Session XXX: consuming background task result" - Normal housekeeping (filter from logs)

### Session Lifecycle
1. `initialize` -> OK
2. `session/new` -> sessionId, modes, configOptions
3. `session/set_mode` -> fire-and-forget (may not respond)
4. `session/prompt` -> streaming via session/update notifications -> PromptResponse
5. `session/cancel` -> notification to interrupt

### Error Patterns
- "Session not found" (code -32603): Session expired or ACP restarted. Clear session, retry via new session/new.
- 0-token response: Session in broken state. Invalidate and recreate.

### Background terminal limitation
Our `clientCapabilities` in `client.lua:125` is empty — we do NOT advertise `terminal`.
Consequence: when the agent is asked to run a bash with `run_in_background=true`,
claude-agent-acp falls back to synchronous execution (the turn blocks until the command exits).
There is no separate terminal-lifecycle message stream; all output arrives via the normal
`tool_call_update` with the `execute` kind once the command finishes.
To support true backgrounded terminals we would need to implement the `terminal/create`,
`terminal/output`, `terminal/wait`, `terminal/kill` handlers and advertise the capability.
