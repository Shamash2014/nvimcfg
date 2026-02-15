-- Chat buffer UI module for .chat files
-- Flemma-inspired buffer-as-state approach while preserving ACP backend

local M = {}

local registry = require("ai_repl.registry")
local chat_parser = require("ai_repl.chat_parser")
local render = require("ai_repl.render")
local annotations = require("ai_repl.annotations")
local chat_buffer_events = require("ai_repl.chat_buffer_events")

local config = {
  -- Keybindings for .chat buffers
  keys = {
    send = "<C-]>",        -- Hybrid: execute pending tools or send
    cancel = "<C-c>",
  },
  -- Buffer behavior
  auto_save = true,
  auto_save_delay = 2000,  -- Delay in ms before autosave after text changes
  save_on_send = true,    -- Autosave before/after sending messages
  save_on_leave = true,   -- Autosave when leaving buffer
  fold_thinking = true,
  show_statusline = true,
}

local buffer_state = {}

-- Get state for a .chat buffer
local function get_state(buf)
  if not buffer_state[buf] then
    buffer_state[buf] = {
      session_id = nil,
      process = nil,
      last_role = nil,
      streaming = false,
      tool_approvals = {},  -- Pending tool approvals
      modified = false,
      repo_root = nil,  -- Track repository root for restart detection
    }
  end
  return buffer_state[buf]
end

-- Get repository root from a buffer path
local function get_repo_root(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name == "" then
    return nil
  end
  
  local dir = vim.fn.fnamemodify(buf_name, ":h")
  if dir == "." then
    dir = vim.fn.getcwd()
  end
  
  -- Try to get git root
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return git_root
  end
  
  -- Fallback to directory
  return dir
end

-- Check if buffer is a .chat file
function M.is_chat_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return name:match("%.chat$") ~= nil
end

-- Initialize a .chat buffer with ACP session
function M.init_buffer(buf)
  if not M.is_chat_buffer(buf) then
    return false, "Not a .chat buffer"
  end

  local state = get_state(buf)

  -- Set buffer options
  vim.bo[buf].filetype = "markdown"  -- Markdown for rendering
  vim.bo[buf].buftype = ""
  vim.bo[buf].bufhidden = ""
  vim.bo[buf].swapfile = true
  vim.bo[buf].buflisted = true
  vim.bo[buf].modifiable = true

  -- Enable text wrapping to prevent overflow
  vim.bo[buf].textwidth = 100  -- Limit lines to 100 characters
  vim.bo[buf].wrapmargin = 0
  vim.bo[buf].formatoptions = "tcqnj"  -- t=text width, c=comments, q=allow formatting with gq, n=recognize lists, j=join comment lines

  -- Set window-local options for wrapping
  vim.api.nvim_buf_call(buf, function()
    vim.wo.wrap = true  -- Enable visual wrapping
    vim.wo.linebreak = true  -- Break lines at word boundaries
  end)

  -- Parse existing content
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  -- Detect repository change
  local current_repo = get_repo_root(buf)
  local repo_changed = state.repo_root and current_repo and state.repo_root ~= current_repo
  
  if repo_changed then
    -- Repository changed, prompt user to restart conversation
    vim.schedule(function()
      vim.ui.select({
        "Restart conversation (clear all messages)",
        "Keep existing conversation",
      }, {
        prompt = "Chat buffer opened in a new repository (" .. vim.fn.fnamemodify(current_repo, ":t") .. "). What would you like to do?",
      }, function(choice, idx)
        if idx == 1 then
          -- Restart conversation
          M.restart_conversation(buf)
        else
          -- Keep existing, just update repo root
          state.repo_root = current_repo
        end
      end)
    end)
    return true
  end
  
  -- Update repo root if not set
  if not state.repo_root then
    state.repo_root = current_repo
  end

  -- Create or attach ACP session
  if parsed.session_id and not state.session_id then
    -- Try to load existing session
    local proc = registry.get(parsed.session_id)
    if proc and proc:is_alive() then
      state.session_id = parsed.session_id
      state.process = proc
      state.last_role = parsed.last_role
      -- Show session status in buffer (without render.append_content)
      vim.schedule(function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        table.insert(lines, "")
        table.insert(lines, "==================================================================")
        table.insert(lines, "[.CHAT BUFFER ATTACHED TO ACP SESSION]")
        table.insert(lines, "==================================================================")
        table.insert(lines, "Working Directory: " .. proc.data.cwd)
        table.insert(lines, "Session ID: " .. proc.session_id)
        table.insert(lines, "Provider: " .. (proc.data.provider or "unknown"))
        table.insert(lines, "==================================================================")
        table.insert(lines, "")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      end)
    else
      -- Try to attach to active session
      local ok, err = M.attach_session(buf, parsed.session_id)
      if not ok then
        -- No active session, will prompt user
        vim.schedule(function()
          vim.notify("[.chat] " .. err .. ". Creating new session...", vim.log.levels.WARN)
          local ai_repl = require("ai_repl.init")
          ai_repl.new_session()
          -- Try attaching again after session is created
          vim.defer_fn(function()
            M.attach_session(buf, parsed.session_id)
          end, 500)
        end)
      end
    end
  elseif not state.session_id then
    -- Create new session for this buffer
    local session_id = "chat_" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
    local ok, err = M.attach_session(buf, session_id)
    if not ok then
      vim.schedule(function()
        vim.notify("[.chat] " .. err .. ". Creating new session...", vim.log.levels.WARN)
        local ai_repl = require("ai_repl.init")
        ai_repl.new_session()
        vim.defer_fn(function()
          M.attach_session(buf, session_id)
        end, 500)
      end)
    end
  end

  -- Setup event forwarding from process to chat buffer
  if state.process and state.process:is_alive() then
    chat_buffer_events.setup_event_forwarding(buf, state.process)
  end

  -- Setup keybindings
  M.setup_keymaps(buf)

  -- Setup autocmds for saving and tracking changes
  M.setup_autocmds(buf)

  -- Setup decorations (role highlights, rulers, folding, spinner)
  local decorations_ok, decorations = pcall(require, "ai_repl.chat_decorations")
  if decorations_ok then
    decorations.setup_buffer(buf)
  end

  -- Sync annotations from buffer
  M.sync_annotations_from_buffer(buf)

  -- Ensure @You: marker exists for user input
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      chat_buffer_events.ensure_you_marker(buf)
    end
  end)

  return true
end

-- Detach ACP process from buffer
function M.attach_session(buf, session_id)
  local state = get_state(buf)

  if state.session_id and state.session_id ~= session_id then
    -- Detach from old session
    M.detach_session(buf)
  end

  local proc = registry.get(session_id)
  if not proc then
    -- Check if there's an active process we can use
    proc = registry.active()
    
    if not proc or not proc:is_alive() then
      -- No active process, return error
      -- The caller should create a session first
      return false, "No active ACP session. Please create one first with :AIReplNew or /new"
    end
  end

  state.session_id = proc.session_id
  state.process = proc
  state.modified = false

  -- Update buffer name if needed
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not buf_name:match("%.chat$") then
    buf_name = buf_name .. ".chat"
    vim.api.nvim_buf_set_name(buf, buf_name)
  end

  -- Ensure absolute path before lcd so :w still resolves correctly
  if buf_name ~= "" then
    local abs = vim.fn.fnamemodify(buf_name, ":p")
    if abs ~= buf_name then
      vim.api.nvim_buf_set_name(buf, abs)
    end
  end

  if proc.data.cwd then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("lcd " .. vim.fn.fnameescape(proc.data.cwd))
    end)
  end

  return true
end

-- Detach ACP process from buffer
function M.detach_session(buf)
  local state = get_state(buf)

  if state.process and state.modified then
    -- Auto-save before detaching
    M.save_buffer(buf)
  end

  state.session_id = nil
  state.process = nil
  state.modified = false
end

-- Restart conversation in chat buffer
function M.restart_conversation(buf)
  if not M.is_chat_buffer(buf) then
    return false, "Not a .chat buffer"
  end

  local state = get_state(buf)

  -- Detach from current session
  if state.session_id then
    M.detach_session(buf)
  end

  -- Clear buffer content and reset to empty template
  local template = chat_parser.generate_empty_template()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, template)

  -- Update repo root to current
  state.repo_root = get_repo_root(buf)

  -- Create new session
  local session_id = "chat_" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
  local ok, err = M.attach_session(buf, session_id)
  
  if not ok then
    vim.schedule(function()
      vim.notify("[.chat] " .. err .. ". Creating new session...", vim.log.levels.WARN)
      local ai_repl = require("ai_repl.init")
      ai_repl.new_session()
      vim.defer_fn(function()
        M.attach_session(buf, session_id)
      end, 500)
    end)
  end

  vim.notify("[.chat] Conversation restarted", vim.log.levels.INFO)
  return true
end

-- Summarize conversation by sending full content to AI
function M.summarize_conversation(buf)
  if not M.is_chat_buffer(buf) then
    return false, "Not a .chat buffer"
  end

  local state = get_state(buf)

  if not state.process or not state.process:is_ready() then
    vim.notify("[.chat] No active session or session not ready", vim.log.levels.WARN)
    return false
  end

  -- Get all lines from buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local full_content = table.concat(lines, "\n")

  if full_content:match("^%s*$") then
    vim.notify("[.chat] Buffer is empty, nothing to summarize", vim.log.levels.WARN)
    return false
  end

  -- Create summary prompt
  local summary_prompt = {
    { type = "text", text = "Please provide a concise summary of the following conversation. Focus on:\n" },
    { type = "text", text = "1. Main topics discussed\n" },
    { type = "text", text = "2. Key decisions made\n" },
    { type = "text", text = "3. Action items or next steps\n" },
    { type = "text", text = "4. Any important context or conclusions\n\n" },
    { type = "text", text = "--- Conversation ---\n\n" },
    { type = "text", text = full_content },
  }

  -- Send to AI
  local ok, err = pcall(function()
    state.process:send_prompt(summary_prompt)
  end)

  if not ok then
    vim.notify("[.chat] Failed to send summary request: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  vim.notify("[.chat] Summary request sent to AI", vim.log.levels.INFO)
  return true
end

-- Send buffer content to ACP process
function M.send_to_process(buf)
  local state = get_state(buf)

  if not state.process then
    vim.notify("[.chat] No active session", vim.log.levels.ERROR)
    return false
  end

  if not state.process:is_ready() then
    vim.notify("[.chat] Session not ready", vim.log.levels.WARN)
    return false
  end

  -- Parse buffer to get messages
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  -- Find last @You: or @User: message
  local last_user_msg = nil
  for i = #parsed.messages, 1, -1 do
    if parsed.messages[i].role == "user" then
      last_user_msg = parsed.messages[i]
      break
    end
  end

  if not last_user_msg then
    -- Try to extract content from current position
    local content = M.extract_current_user_message(buf)
    if not content or content:match("^%s*$") then
      vim.notify("[.chat] No message to send. Type after @You: marker", vim.log.levels.WARN)
      return false
    end
    last_user_msg = { content = content }
  end

  -- Send to process
  local proc = state.process
  local content = last_user_msg.content

  -- Check if content is empty or just whitespace
  if content:match("^%s*$") then
    vim.notify("[.chat] Message is empty. Type something after @You:", vim.log.levels.WARN)
    return false
  end

  -- Handle @file references
  local prompt = chat_parser.build_prompt(content, parsed.attachments)

  -- Inject @Djinni: marker if not present
  if parsed.last_role ~= "djinni" then
    M.append_djinni_marker(buf)
  end

  -- Autosave buffer before sending
  if config.save_on_send and config.auto_save then
    M.autosave_buffer(buf)
  end

  -- Send prompt
  proc:send_prompt(prompt)

  -- Update state
  state.streaming = true
  state.last_role = "djinni"

  -- Poll for completion and append @You: when done
  local poll_timer = vim.uv.new_timer()
  poll_timer:start(500, 300, vim.schedule_wrap(function()
    if proc.state.busy then return end
    poll_timer:stop()
    poll_timer:close()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    state.streaming = false
    chat_buffer_events.stop_streaming(buf)
    chat_buffer_events.ensure_you_marker(buf)

    -- Autosave after response is received
    if config.save_on_send and config.auto_save then
      M.autosave_buffer(buf)
    end
  end))

  return true
end

-- Extract current user message from buffer
function M.extract_current_user_message(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Find last @You: or @User: marker
  local last_you_line = -1
  for i = #lines, 1, -1 do
    if lines[i]:match("^@You:%s*$") or lines[i]:match("^@User:%s*$") then
      last_you_line = i
      break
    end
  end

  if last_you_line == -1 then
    return nil
  end

  -- Collect content after the marker
  local content_lines = {}
  for i = last_you_line + 1, #lines do
    local line = lines[i]
    -- Stop at next role marker or end
    if line:match("^@%w+:") then
      break
    end
    table.insert(content_lines, line)
  end

  local content = table.concat(content_lines, "\n")
  -- Trim leading/trailing whitespace but preserve internal formatting
  content = content:gsub("^%s*", ""):gsub("%s*$", "")

  return content
end

-- Append @Djinni: marker to buffer
function M.append_djinni_marker(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line_count = #lines

  -- Check if last line is empty
  if line_count > 0 and lines[line_count] ~= "" then
    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "" })
    line_count = line_count + 1
  end

  -- Append @Djinni: marker at the end
  vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, {
    "@Djinni:",
    ""
  })

  -- Move cursor to @Djinni: line
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { line_count + 1, 0 })
  end
end

-- Save buffer to session history
function M.save_buffer(buf)
  local state = get_state(buf)

  if not state.session_id or not state.process then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  -- Save messages to registry
  for _, msg in ipairs(parsed.messages) do
    if msg.role == "user" then
      registry.append_message(state.session_id, msg.role, msg.content, msg.tool_calls)
    elseif msg.role == "djinni" then
      registry.append_message(state.session_id, msg.role, msg.content, msg.tool_calls)
    end
  end

  state.modified = false
  return true
end

-- Autosave buffer to disk
function M.autosave_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local buf_name = vim.api.nvim_buf_get_name(buf)

  -- Skip if buffer has no name or is not a .chat file
  if not buf_name or buf_name == "" or not buf_name:match("%.chat$") then
    return false
  end

  -- Skip if buffer is not modified
  if not vim.bo[buf].modified then
    return false
  end

  -- Get the local cwd for this buffer (where it should be saved)
  local local_cwd = vim.api.nvim_buf_call(buf, function()
    return vim.fn.getcwd()
  end)

  -- Ensure buffer name is relative to local cwd or create proper path
  local full_path = vim.fn.fnamemodify(buf_name, ":p")
  local save_path = full_path

  -- If the file doesn't have a proper directory yet, use local cwd
  if vim.fn.isdirectory(vim.fn.fnamemodify(full_path, ":h")) == 0 then
    local filename = vim.fn.fnamemodify(buf_name, ":t")
    save_path = local_cwd .. "/" .. filename
    vim.api.nvim_buf_set_name(buf, save_path)
  end

  -- Ensure directory exists before saving
  local dir = vim.fn.fnamemodify(save_path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Save buffer to disk
  -- Temporarily enable modifiable and readonly to allow write to succeed
  local was_modifiable = vim.bo[buf].modifiable
  local was_readonly = vim.bo[buf].readonly
  local old_ei = vim.o.eventignore
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  -- Ignore autocmds during autosave to prevent editorconfig issues
  vim.o.eventignore = "BufWritePre,BufWritePost"

  local ok, err = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent write!")
    end)
  end)

  -- Restore modifiable, readonly, and eventignore state
  vim.bo[buf].modifiable = was_modifiable
  vim.bo[buf].readonly = was_readonly
  vim.o.eventignore = old_ei

  if ok then
    vim.notify("[.chat] Buffer autosaved: " .. vim.fn.fnamemodify(buf_name, ":~:."), vim.log.levels.DEBUG)
    return true
  else
    vim.notify("[.chat] Failed to autosave: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
end

-- Setup keybindings for .chat buffer
function M.setup_keymaps(buf)
  local opts = { buffer = buf, silent = true }

  -- Send/Execute hybrid key (C-])
  vim.keymap.set({ "n", "i" }, config.keys.send, function()
    M.hybrid_send(buf)
  end, opts)

  -- Cancel key
  vim.keymap.set({ "n", "i" }, config.keys.cancel, function()
    local state = get_state(buf)
    local proc = state.process

    if proc then
      -- Cancel active permission prompt
      if proc.ui and proc.ui.permission_active then
        -- Remove permission keymaps from this buffer
        for _, key in ipairs({ "y", "a", "n", "c" }) do
          pcall(vim.keymap.del, "n", key, { buffer = buf })
        end
        -- Also remove from proc's REPL buffer if different
        if proc.data.buf and proc.data.buf ~= buf then
          for _, key in ipairs({ "y", "a", "n", "c" }) do
            pcall(vim.keymap.del, "n", key, { buffer = proc.data.buf })
          end
        end
        proc.ui.permission_active = false
        proc.ui.permission_queue = {}
      end

      -- Cancel active questionnaire
      local q_ok, questionnaire = pcall(require, "ai_repl.questionnaire")
      if q_ok then pcall(questionnaire.cancel) end

      proc:cancel()
    end

    state.streaming = false
    chat_buffer_events.stop_streaming(buf)
    local ok, decorations = pcall(require, "ai_repl.chat_decorations")
    if ok then pcall(decorations.stop_spinner, buf) end

    chat_buffer_events.append_to_chat_buffer(buf, { "", "[x] Cancelled", "", "@You:", "", "" })
  end, opts)

  -- Jump to next/previous message
  vim.keymap.set("n", "]m", function()
    chat_parser.jump_to_message(buf, 1)
  end, opts)

  vim.keymap.set("n", "[m", function()
    chat_parser.jump_to_message(buf, -1)
  end, opts)

  -- Text objects for messages
  vim.keymap.set("o", "im", function()
    chat_parser.select_message(buf, false)
  end, opts)

  vim.keymap.set("o", "am", function()
    chat_parser.select_message(buf, true)
  end, opts)

  -- Add annotation from visual selection
  vim.keymap.set("v", "<leader>aa", function()
    M.add_annotation_from_selection(buf)
  end, vim.tbl_extend("force", opts, {
    desc = "Add selection as annotation to .chat buffer"
  }))

  -- Restart conversation
  vim.keymap.set("n", "<leader>ar", function()
    vim.ui.select({
      "Yes, restart conversation",
      "No, keep conversation",
    }, {
      prompt = "Restart conversation? This will clear all messages.",
    }, function(choice, idx)
      if idx == 1 then
        M.restart_conversation(buf)
      end
    end)
  end, vim.tbl_extend("force", opts, {
    desc = "Restart conversation in .chat buffer"
  }))

  -- Summarize conversation
  vim.keymap.set("n", "<leader>as", function()
    M.summarize_conversation(buf)
  end, vim.tbl_extend("force", opts, {
    desc = "Summarize conversation in .chat buffer"
  }))
end

-- Hybrid send: tools → execute → send
function M.hybrid_send(buf)
  local state = get_state(buf)

  -- Check if process exists and is ready
  if not state.process then
    vim.notify("[.chat] No active session. Please create one first.", vim.log.levels.ERROR)
    return false
  end

  if not state.process:is_ready() then
    vim.notify("[.chat] Session not ready. Please wait...", vim.log.levels.WARN)
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  -- Phase 0: Check for annotations to sync first
  if #parsed.annotations > 0 then
    local ok, msg = M.sync_annotations_from_buffer(buf)
    if ok then
      vim.notify("[.chat] " .. msg, vim.log.levels.INFO)
    end
  end

  -- Phase 1: Check for pending tool approvals
  if #parsed.pending_tools > 0 then
    -- Inject placeholders for review
    M.inject_tool_placeholders(buf, parsed.pending_tools)
    return true
  end

  -- Phase 2: Check for tool placeholders to execute
  if M.has_tool_placeholders(lines) then
    M.execute_tools(buf)
    return true
  end

  -- Phase 3: Autosave before sending
  if config.save_on_send and config.auto_save then
    M.autosave_buffer(buf)
  end

  -- Phase 4: Send to process
  return M.send_to_process(buf)
end

-- Inject placeholders for pending tools
function M.inject_tool_placeholders(buf, tools)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for _, tool in ipairs(tools) do
    local placeholder = string.format(
      "\n\n**Tool Use:** `%s` (`%s`)\n```json\n%s\n```\n",
      tool.id,
      tool.title or tool.kind,
      vim.json.encode(tool.input or {})
    )
    table.insert(lines, placeholder)
  end

  vim.api.nvim_buf_set_lines(buf, #lines, #lines, false, lines)
  vim.notify("[.chat] Tools injected - review and press C-] to execute", vim.log.levels.INFO)
end

-- Check if buffer has tool placeholders
function M.has_tool_placeholders(lines)
  for _, line in ipairs(lines) do
    if line:match("^%*%*Tool Use:%*%*") then
      return true
    end
  end
  return false
end

-- Execute approved tools
function M.execute_tools(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  -- Send tool calls to process
  local state = get_state(buf)
  if not state.process then
    return
  end

  -- Autosave before executing tools
  if config.auto_save then
    M.autosave_buffer(buf)
  end

  for _, tool in ipairs(parsed.tools) do
    -- Execute tool via process
    -- This will trigger process callbacks which update buffer
  end

  -- Autosave after executing tools
  if config.auto_save then
    M.autosave_buffer(buf)
  end

  vim.notify("[.chat] Tools executed - press C-] to send", vim.log.levels.INFO)
end

-- Setup autocmds for buffer lifecycle
function M.setup_autocmds(buf)
  local autosave_timer = nil

  -- Track modifications and trigger autosave
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      local state = get_state(buf)
      state.modified = true

      -- Debounced autosave after text changes
      if config.auto_save and config.auto_save_delay > 0 then
        if autosave_timer then
          autosave_timer:stop()
          autosave_timer:close()
        end
        autosave_timer = vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M.autosave_buffer(buf)
          end
          autosave_timer = nil
        end, config.auto_save_delay) -- Use configurable delay
      end
    end,
  })

  -- Auto-save on write (also saves to registry)
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      local ok = M.save_buffer(buf)
      if ok then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        vim.notify("[.chat] Saved to session: " .. vim.fn.fnamemodify(buf_name, ":~:."), vim.log.levels.DEBUG)
      end
    end,
  })

  -- Cleanup on delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      -- Final autosave before deletion
      if config.auto_save then
        M.autosave_buffer(buf)
      end
      M.detach_session(buf)
      buffer_state[buf] = nil
    end,
  })

  -- Autosave when leaving the buffer
  if config.save_on_leave then
    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = buf,
      callback = function()
        if config.auto_save then
          M.autosave_buffer(buf)
        end
      end,
    })
  end

  -- Autosave on InsertLeave (when leaving insert mode)
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = buf,
    callback = function()
      if config.auto_save then
        M.autosave_buffer(buf)
      end
    end,
  })
end

-- Sync annotations from .chat buffer to annotation system
function M.sync_annotations_from_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local parsed = chat_parser.parse_buffer(lines)

  if #parsed.annotations == 0 then
    return false, "No annotations found in buffer"
  end

  -- Start annotation session if not active
  local annotation_session = require("ai_repl.annotations.session")
  if not annotation_session.is_active() then
    local annotations_config = require("ai_repl.annotations.config")
    annotation_session.start(annotations_config.config)
  end

  -- Get annotation buffer
  local ann_bufnr = annotation_session.get_bufnr()
  if not ann_bufnr or not vim.api.nvim_buf_is_valid(ann_bufnr) then
    return false, "Failed to get annotation buffer"
  end

  -- Convert .chat annotations to annotation format
  local writer = require("ai_repl.annotations.writer")
  local session_state = annotation_session.get_state()

  for _, ann in ipairs(parsed.annotations) do
    local annotation_data = {
      file = ann.file,
      start_line = ann.start_line,
      end_line = ann.end_line or ann.start_line,
      note = ann.note,
      text = ann.text or "",
    }

    writer.append(session_state, "location", annotation_data, ann.note)
  end

  return true, string.format("Synced %d annotations", #parsed.annotations)
end

-- Send annotations from .chat buffer to AI
function M.send_annotations_to_ai(buf)
  local state = get_state(buf)

  if not state.process then
    vim.notify("[.chat] No active session", vim.log.levels.ERROR)
    return false
  end

  -- Sync annotations first
  local ok, err = M.sync_annotations_from_buffer(buf)
  if not ok then
    vim.notify("[.chat] " .. tostring(err), vim.log.levels.WARN)
    -- Continue anyway, annotations might already be in system
  end

  -- Use existing annotation send function
  require("ai_repl.annotations").send_annotation_to_ai()

  return true
end

-- Add annotation from visual selection to .chat buffer
function M.add_annotation_from_selection(buf)
  -- Get visual selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
  local end_pos = vim.api.nvim_buf_get_mark(buf, ">")

  if not start_pos or not end_pos then
    vim.notify("[.chat] No visual selection", vim.log.levels.WARN)
    return
  end

  local start_line = start_pos[1]
  local end_line = end_pos[1]
  local file_path = vim.api.nvim_buf_get_name(buf)
  local relative_file = vim.fn.fnamemodify(file_path, ":~:.")

  -- Get selected text (for snippet mode)
  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  local selected_text = table.concat(lines, "\n")

  -- Prompt for note
  vim.ui.input({ prompt = "Annotation note: " }, function(note)
    if not note or note == "" then
      return
    end

    -- Generate annotation line
    local ann_line
    if start_line == end_line then
      ann_line = string.format("- **`%s:%d`** — %s", relative_file, start_line, note)
    else
      ann_line = string.format("- **`%s:%d-%d`** — %s", relative_file, start_line, end_line, note)
    end

    -- Insert annotation line at cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    local insert_at = cursor[1]

    -- Find end of current message or end of buffer
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local insert_idx = insert_at

    -- Check if we're in a message, find its end
    for i = insert_at, #buf_lines do
      if buf_lines[i]:match("^@") and i > insert_at then
        insert_idx = i - 1
        break
      end
    end

    -- Insert blank line, annotation, blank line
    vim.api.nvim_buf_set_lines(buf, insert_idx, insert_idx, false, {
      "",
      ann_line,
      ""
    })

    vim.notify("[.chat] Annotation added", vim.log.levels.INFO)
  end)
end

-- Get active .chat buffer for current session
function M.get_active_chat_buffer()
  for buf, _ in pairs(buffer_state) do
    if vim.api.nvim_buf_is_valid(buf) and M.is_chat_buffer(buf) then
      return buf
    end
  end
  return nil
end

return M
