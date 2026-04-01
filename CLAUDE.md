# Djinni.nvim - Neovim ACP Client for Claude

## Project Overview
Neovim plugin providing Claude Code integration via the Agent Client Protocol (ACP).
Supports .chat buffer sessions, streaming, tool calls, permissions, plans, and mode switching.

## Key Directories
- `lua/djinni/acp/` — ACP client, session management, provider config
- `lua/djinni/nowork/` — .chat buffer UI, streaming, commands, rendering
- `djinni-skills/` — Custom skills for the plugin

## Architecture
- Each .chat buffer owns a unique ACP session — NEVER reuse sessions across buffers
- `client.lua` — JSON-RPC 2.0 client over stdio (jobstart/chansend)
- `session.lua` — Session lifecycle: create, resume, prompt, set_mode, interrupt
- `chat.lua` — Buffer management, streaming, event handling, permissions UI

## ACP Protocol
- See `lua/djinni/acp/agents.md` for full protocol reference
- See `lua/djinni/acp/claude.md` for claude-agent-acp implementation notes

## Critical Rules
- `session/set_mode` MUST be sent as notify, NOT request (blocks ACP session)
- `session/cancel` is a notification (no response)
- `session/request_permission` is a request FROM agent TO client — always respond, never timeout
- Permission options use `kind` field, not `id`
- Lua `{}` encodes as JSON array; use `vim.empty_dict()` for empty JSON objects
- Always provide an 'always' option in permission prompts

## Testing
- No automated tests currently — verify by opening .chat buffers and sending messages
- Check `:messages` and log file for errors
- Stderr warnings like "Error handling notification" are cosmetic (non-fatal)
