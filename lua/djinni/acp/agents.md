# ACP (Agent Client Protocol) Reference

Spec: https://agentclientprotocol.com
Schema: https://agentclientprotocol.com/protocol/schema
GitHub: https://github.com/agentclientprotocol/agent-client-protocol

## Transport

JSON-RPC 2.0 over stdio (local agents) or HTTP/WebSocket (remote agents).

## Methods: Client -> Agent (Requests)

### initialize
Negotiate protocol version and capabilities.
- Params: `protocolVersion`, `clientInfo`, `clientCapabilities`
- Response: `protocolVersion`, `serverCapabilities`, `authMethods`

### session/new
Create a new conversation session.
- Params: `cwd` (required), `mcpServers`, `configOptions`, `modes`
- Response: `sessionId` (required), `configOptions`, `modes`, `models`

### session/load
Resume an existing session (requires `loadSession` capability).
- Params: `sessionId` (required), `cwd`, `mcpServers`
- Response: streams conversation history via `session/update` notifications

### session/prompt
Send a user prompt. Handles full turn lifecycle: LLM processing, tool calls, permissions, streaming.
- Params: `sessionId` (required), `prompt` (required, array of content blocks)
- Response: `stopReason` (required), token usage

### session/set_mode
Set session mode (e.g., "ask", "architect", "code"). **This is a REQUEST, not a notification.**
- Params: `sessionId` (required), `modeId` (required)
- Response: `SetSessionModeResponse` (minimal, just `_meta`)

### session/set_config_option
Set a configuration option value.
- Params: `sessionId` (required), `optionId` (required), `value` (required)
- Response: `SetSessionConfigOptionResponse`

### session/list
List available sessions (requires `sessionList` capability).
- Response: array of `SessionInfo`

## Methods: Client -> Agent (Notifications)

### session/cancel
Cancel ongoing prompt processing. Agent SHOULD stop LLM requests, abort tool calls, send pending updates, respond to `session/prompt` with `StopReason::Cancelled`.
- Params: `sessionId` (required)

## Methods: Agent -> Client (Notifications)

### session/update
Real-time session progress updates. **No response expected.**
- Params: `sessionId` (required), `update` (required, SessionUpdate union)

SessionUpdate types:
- `user_message_chunk` - streamed user message
- `agent_message_chunk` - agent response text
- `agent_thought_chunk` - agent thinking/reasoning
- `tool_call` - tool invocation started (id, title, kind, status)
- `tool_call_update` - tool status/result update (status: running/completed/failed/error)
- `plan` - agent execution plan entries
- `modes` - available modes changed
- `current_mode_update` - active mode changed
- `available_commands_update` - slash commands changed
- `config_option_update` - config option changed
- `session_info_update` - session metadata changed

## Methods: Agent -> Client (Requests)

### session/request_permission
Request user authorization for a tool call.
- Params: `sessionId`, `toolCall` (required), `options` (required, array of PermissionOption)
- Each option: `optionId` (required), `name` (required), `kind` (hint: allow_once, allow_always, deny_once, deny_always)
- Response: `RequestPermissionOutcome` with selected `optionId`
- If cancelled via `session/cancel`, respond with `Cancelled` outcome

### fs/read_text_file
Read file contents (requires `fileSystem` client capability).
- Params: `path` (required, absolute), `startLine`, `endLine`

### fs/write_text_file
Write file contents.
- Params: `path` (required, absolute), `content` (required)

### terminal/create
Create a terminal (requires `terminal` client capability).
- Returns `TerminalId` for tracking

### terminal/output
Get terminal output.

### terminal/wait
Wait for terminal exit.

### terminal/kill
Kill a running terminal.

## Key Types

### Content (prompt content blocks)
- `text` - text content with `text` field
- `image` - image with `source` (base64 or url)
- `resource` - embedded resource

### ToolKind
Categories: `read`, `edit`, `delete`, `search`, `execute`, `think`, `fetch`, `switch_mode`, `other`

### StopReason
Why agent stopped: `end_turn`, `cancelled`, `max_tokens`, `tool_use`, `error`

### SessionMode
- `id` (required) - unique mode identifier
- `name` (required) - display name
- `description` - optional description

### SessionModeState
- `availableModes` (required) - array of SessionMode
- `currentModeId` (required) - active mode ID

## Important Notes

1. `session/set_mode` is a REQUEST (expects response), not a notification
2. `session/cancel` is a NOTIFICATION (no response)
3. `session/update` is a NOTIFICATION from agent to client
4. `session/request_permission` is a REQUEST from agent to client (client must respond)
5. File paths must be absolute, line numbers are 1-based
6. Custom extensions use `_` prefix, metadata in `_meta` fields
7. Clients SHOULD continue accepting tool_call_update after session/cancel
