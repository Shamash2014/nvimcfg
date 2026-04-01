# Agent Guidelines for Djinni.nvim

## Before Making Changes
1. Read `lua/djinni/acp/agents.md` for ACP protocol spec
2. Read `lua/djinni/acp/claude.md` for claude-agent-acp behavior and known issues
3. Understand the session lifecycle: initialize -> session/new -> set_mode -> prompt -> events -> cleanup

## Key Files
| File | Purpose |
|------|---------|
| `lua/djinni/acp/client.lua` | JSON-RPC 2.0 client (request, notify, on event) |
| `lua/djinni/acp/session.lua` | Session management (create, resume, send, set_mode) |
| `lua/djinni/acp/provider.lua` | ACP provider config (command, args) |
| `lua/djinni/nowork/chat.lua` | .chat buffer: streaming, events, permissions, commands |
| `lua/djinni/nowork/commands.lua` | Slash commands (/mode, /start, /profile, etc.) |
| `lua/djinni/nowork/log.lua` | Logging |

## ACP Pitfalls (read claude.md for full details)
- `session/set_mode` — MUST use `client:notify`, never `client:request` (blocks session)
- `session/cancel` — notification, no response expected
- `session/request_permission` — request FROM agent, client MUST respond, NEVER timeout
- Empty JSON objects — use `vim.empty_dict()`, not `{}` (Lua tables encode as arrays)
- Session not found — clear session state and retry via new session/new
- 0-token responses — invalidate session, reconnect

## Session Flow
```
client:request("initialize", ...) -> ready
client:request("session/new", {cwd, mcpServers}) -> sessionId, modes, configOptions
client:notify("session/set_mode", {sessionId, modeId}) -> fire-and-forget
client:on("session/update", handler) -> register event handler
client:request("session/prompt", {sessionId, prompt}) -> streaming events -> PromptResponse
```

## Event Handling
Events arrive via `session/update` notification with `sessionUpdate` discriminator:
- `agent_message_chunk` / `agent_thought_chunk` — text streaming
- `tool_call` / `tool_call_update` — tool lifecycle
- `modes` / `current_mode_update` — mode changes
- `plan` — plan entries
- `result` / `usage_update` — token usage

## Code Style
- No comments in code — fix issues directly
- No console.log/print — use `log.info()`, `log.warn()`, `log.dbg()`
- Guard buffer validity: `vim.api.nvim_buf_is_valid(buf)`
- Use `vim.schedule()` for callbacks that touch Neovim API
- Filter stderr noise: skip lines starting with whitespace, containing `[Object]`, or "consuming background task"
