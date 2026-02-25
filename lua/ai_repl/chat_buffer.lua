-- Chat buffer UI module for .chat files
-- Flemma-inspired buffer-as-state approach while preserving ACP backend

local M = {}

local registry = require("ai_repl.registry")
local chat_parser = require("ai_repl.chat_parser")
local render = require("ai_repl.render")
local annotations = require("ai_repl.annotations")
local chat_buffer_events = require("ai_repl.chat_buffer_events")
local chat_state = require("ai_repl.chat_state")
local async = require("ai_repl.async")

local config = {
  -- Keybindings for .chat buffers
  keys = {
    send = "<C-]>",        -- Hybrid: execute pending tools or send
    cancel = "<C-c>",
    kill_session = "<leader>ak",
    restart_session = "<leader>aR",
    force_cancel = "<leader>aK",
  },
  -- Buffer behavior
  auto_save = true,
  auto_save_delay = 0,  -- Delay in ms before autosave after text changes
  save_on_send = true,    -- Autosave before/after sending messages
  save_on_leave = true,   -- Autosave when leaving buffer
  fold_thinking = true,
  show_statusline = true,
}

local function get_state(buf)
  return chat_state.get_buffer_state(buf)
end

local function get_repo_root(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if buf_name == "" then
    return nil
  end

  local dir = vim.fn.fnamemodify(buf_name, ":h")
  if dir == "." then
    dir = vim.fn.getcwd()
  end

  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return git_root
  end

  return dir
end

function M.get_repo_root(buf)
  return get_repo_root(buf)
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
function M.init_buffer(buf, existing_session_id)
  if not M.is_chat_buffer(buf) then
    return false, "Not a .chat buffer"
  end

  local state = get_state(buf)

  -- Set buffer options
  vim.bo[buf].filetype = "chat"  -- Dedicated chat filetype (not markdown to avoid expensive plugins)
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

  -- Parse existing content with caching
  local parsed = chat_parser.parse_buffer_cached(buf)

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

  -- Skip session setup if a session is being created
  if state.creating_session then
    return true
  end

  -- If called with existing_session_id, attach to it immediately
  if existing_session_id then
    local proc = registry.get(existing_session_id)
    if proc and proc:is_alive() then
      M.attach_session(buf, existing_session_id)
      local chat_buffer_events = require("ai_repl.chat_buffer_events")
      chat_buffer_events.setup_event_forwarding(buf, proc)
      M.setup_keymaps(buf)
      M.setup_autocmds(buf)
      return true
    end
  end

  -- Create or attach ACP session
  if parsed.session_id and not state.session_id then
    -- Try to load existing session
    local proc = registry.get(parsed.session_id)
    if proc and proc:is_alive() then
      state.session_id = parsed.session_id
      state.process = proc
      state.last_role = parsed.last_role

      -- Sync conversation history from buffer to process
      -- This ensures the AI has full context of the conversation
      if #parsed.messages > 0 then
        local proc_messages = proc.data.messages or {}

        -- Only sync if process doesn't have messages or buffer has different content
        local needs_sync = #proc_messages == 0

        if not needs_sync then
          -- Check if the last messages match
          local last_proc_msg = proc_messages[#proc_messages]
          local last_parsed_msg = parsed.messages[#parsed.messages]
          if not last_proc_msg or not last_parsed_msg or
             last_proc_msg.role ~= last_parsed_msg.role or
             last_proc_msg.content ~= last_parsed_msg.content then
            needs_sync = true
          end
        end

        if needs_sync then
          proc.data.messages = {}
          for _, msg in ipairs(parsed.messages) do
            if msg.role == "user" or msg.role == "djinni" or msg.role == "system" then
              registry.append_message(state.session_id, msg.role, msg.content, msg.tool_calls)
            end
          end
        end
      end

      -- Show session status in buffer (without render.append_content)
      vim.schedule(function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local provider_id = proc.data.provider or "unknown"
        local providers = require("ai_repl.providers")
        local provider_cfg = providers.get(provider_id) or {}
        local provider_name = provider_cfg.name or provider_id
        table.insert(lines, "")
        table.insert(lines, "Working Directory: " .. proc.data.cwd)
        table.insert(lines, "Session ID: " .. proc.session_id)
        table.insert(lines, "Messages synced: " .. #parsed.messages)
        table.insert(lines, "==================================================================")
        table.insert(lines, "")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        require("ai_repl.init").update_statusline()
      end)
    else
      -- No active session exists, user must manually start with /start
      vim.notify("[.chat] No active session. Type /start to begin.", vim.log.levels.INFO)
    end
  elseif not state.session_id then
    -- Don't auto-create session eagerly — wait for user to send a message.
    -- This prevents spawning ACP processes for every .chat buffer on startup.
  end

  -- Setup event forwarding from process to chat buffer
  if state.process and state.process:is_alive() then
    chat_buffer_events.setup_event_forwarding(buf, state.process)
  end

  -- Setup keybindings
  M.setup_keymaps(buf)

  -- Setup autocmds for saving and tracking changes
  M.setup_autocmds(buf)

  -- Invalidate parser cache on buffer changes
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      chat_parser.invalidate_cache(buf)
    end,
  })

  -- Optimize updatetime when chat buffer is active
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      chat_state.increment_active_buffers()
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    callback = function()
      chat_state.decrement_active_buffers()
    end,
  })

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

-- Attach ACP process to buffer (session_id is optional - if not found, will search for matching repo)
function M.attach_session(buf, session_id)
  local state = get_state(buf)

  if state.session_id and state.session_id ~= session_id then
    -- Detach from old session
    M.detach_session(buf)
  end

  local proc = nil
  local current_repo = get_repo_root(buf)

  if session_id then
    proc = registry.get(session_id)
  end

  if not proc or not proc:is_alive() then
    proc = nil
    for sid, p in pairs(registry.all()) do
      if p:is_alive() and p.data.cwd == current_repo then
        proc = p
        break
      end
    end
  end

  if not proc or not proc:is_alive() then
    return false, "No ACP session found for this project. Please create one first."
  end

  state.session_id = proc.session_id
  state.process = proc
  state.modified = false
  state.system_sent = false

  -- Setup event forwarding to ensure AI responses appear in chat buffer
  chat_buffer_events.setup_event_forwarding(buf, proc)

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
    state.repo_root = proc.data.cwd
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
function M.restart_conversation(buf, provider_id)
  if not M.is_chat_buffer(buf) then
    return false, "Not a .chat buffer"
  end

  local state = get_state(buf)

  -- Detach from current session
  if state.session_id then
    M.detach_session(buf)
  end

  -- Parse existing messages from buffer (don't remove them)
  local parsed = chat_parser.parse_buffer_cached(buf)
  local existing_messages = parsed.messages or {}
  local has_content = #existing_messages > 0

  -- Update repo root to current; capture fallback before any picker opens
  state.repo_root = get_repo_root(buf) or vim.fn.getcwd()

  local function create_session_with_provider(provider)
    local ai_repl = require("ai_repl.init")

    vim.notify("[.chat] Creating new session with " .. provider .. "...", vim.log.levels.INFO)

    local session_id = registry.generate_unique_session_id()
    local proc = ai_repl._create_process(session_id, {
      provider = provider,
      cwd = state.repo_root,
    })

    ai_repl._registry_set(session_id, proc)
    ai_repl._registry_set_active(session_id)

    proc:start()

    local function attach_when_ready()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if proc:is_ready() then
        chat_buffer_events.setup_event_forwarding(buf, proc)
        M.attach_session(buf, proc.session_id)

        -- Sync existing messages from buffer to new session
        if has_content then
          local registry = require("ai_repl.registry")
          for _, msg in ipairs(existing_messages) do
            if msg.role == "user" or msg.role == "djinni" or msg.role == "system" then
              registry.append_message(proc.session_id, msg.role, msg.content, msg.tool_calls)
            end
          end
          vim.notify("[.chat] Synced " .. #existing_messages .. " messages to new session", vim.log.levels.INFO)
        end

        local provider_id = proc.data.provider or "unknown"
        local providers = require("ai_repl.providers")
        local provider_cfg = providers.get(provider_id) or {}
        local provider_name = provider_cfg.name or provider_id
        vim.notify("[.chat] Conversation restarted with " .. provider, vim.log.levels.INFO)
        require("ai_repl.init").update_statusline()
      else
        vim.defer_fn(attach_when_ready, 100)
      end
    end

    attach_when_ready()
  end

  if provider_id then
    create_session_with_provider(provider_id)
  else
    local ai_repl = require("ai_repl.init")
    ai_repl.pick_provider(function(selected_provider)
      if not selected_provider then
        vim.notify("[.chat] Restart cancelled", vim.log.levels.INFO)
        return
      end
      create_session_with_provider(selected_provider)
    end)
  end

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
    vim.notify("[.chat] No active session. Press C-] to start one.", vim.log.levels.ERROR)
    return false
  end

  -- Reset streaming state in case it was stuck from a previous cancel
  if state.streaming and not state.process.state.busy then
    state.streaming = false
    chat_buffer_events.stop_streaming(buf)
  end

  -- Parse buffer to get messages
  local parsed = chat_parser.parse_buffer_cached(buf)

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

  -- Check if process is alive BEFORE checking ready
  if not proc:is_alive() then
    vim.notify("[.chat] Process is not alive. Cannot send message.", vim.log.levels.ERROR)
    return false
  end

  -- Ensure session_ready is set if initialized (handles post-cancel state)
  if proc.state.initialized and not proc.state.session_ready then
    proc.state.session_ready = true
  end

  -- Now check if ready (should pass after above fix)
  if not proc:is_ready() then
    vim.notify("[.chat] Session not ready. Please wait...", vim.log.levels.WARN)
    return false
  end

  local content = last_user_msg.content

  -- Check if content is empty or just whitespace
  if content:match("^%s*$") then
    vim.notify("[.chat] Message is empty. Type something after @You:", vim.log.levels.WARN)
    return false
  end

  -- Trim leading/trailing whitespace for command detection
  local trimmed_content = content:gsub("^%s*(.-)%s*$", "%1")

  -- Check if this is a slash command
  if trimmed_content:sub(1, 1) == "/" then
    -- Extract command (remove leading /)
    local cmd_with_args = trimmed_content:sub(2)

    -- Import handle_command from ai_repl
    local ai_repl = require("ai_repl")

    -- Inject @Djinni: marker if not present before executing command
    if parsed.last_role ~= "djinni" then
      M.append_djinni_marker(buf)
    end

    -- Clear the slash command from the buffer by removing the user message
    -- Find the last @You: or @User: marker and remove everything after it until the next marker
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local last_you_line = -1
    for i = #lines, 1, -1 do
      if lines[i]:match("^@You:%s*$") or lines[i]:match("^@User:%s*$") then
        last_you_line = i
        break
      end
    end

    if last_you_line ~= -1 then
      -- Remove content after @You: marker (keep the marker itself)
      vim.api.nvim_buf_set_lines(buf, last_you_line + 1, -1, false, {})
    end

    -- Handle the slash command
    ai_repl.handle_command(cmd_with_args)

    -- Ensure @You: marker is added after command execution
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        chat_buffer_events.ensure_you_marker(buf)
      end
    end)

    return true
  end

  -- Handle @file references
  local prompt = chat_parser.build_prompt(content, parsed.attachments)

  local system_messages = {}
  for _, msg in ipairs(parsed.messages) do
    if msg.role == "system" and msg.content and msg.content ~= "" then
      table.insert(system_messages, msg.content)
    end
  end
  if #system_messages > 0 and not state.system_sent then
    local system_block = {
      type = "text",
      text = "<system>\n" .. table.concat(system_messages, "\n\n") .. "\n</system>",
    }
    table.insert(prompt, 1, system_block)
    state.system_sent = true
  end

  if state.process and not chat_buffer_events.is_forwarding_setup(buf, state.process) then
    vim.notify("[.chat] Warning: Event forwarding not set up. Responses may not appear.", vim.log.levels.WARN)
  end

  if parsed.last_role ~= "djinni" then
    M.append_djinni_marker(buf)
  end

  -- Autosave buffer before sending
  if config.save_on_send and config.auto_save then
    M.autosave_buffer(buf)
  end

  -- Send prompt
  async.run(function()
    proc:send_prompt(prompt)
  end)

  -- Update state
  state.streaming = true
  state.last_role = "djinni"

  -- Poll for completion and append @You: when done
  local poll_timer = vim.uv.new_timer()
  local timer_closed = false
  local max_wait_time = 300000
  local elapsed_time = 0

  poll_timer:start(500, 300, vim.schedule_wrap(function()
    if timer_closed then return end

    if not vim.api.nvim_buf_is_valid(buf) then
      timer_closed = true
      poll_timer:stop()
      poll_timer:close()
      return
    end

    elapsed_time = elapsed_time + 300

    if elapsed_time > max_wait_time then
      timer_closed = true
      poll_timer:stop()
      poll_timer:close()
      return
    end

    if proc.state.busy then return end

    timer_closed = true
    poll_timer:stop()
    poll_timer:close()

    if not vim.api.nvim_buf_is_valid(buf) then return end

    state.streaming = false
    chat_buffer_events.stop_streaming(buf)

    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      chat_buffer_events.ensure_you_marker(buf)

      -- Autosave after response is received
      if config.save_on_send and config.auto_save then
        M.autosave_buffer(buf)
      end
    end, 150)
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
  local parsed = chat_parser.parse_buffer_cached(buf)

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
    local state = get_state(buf)
    if state.process and state.process.ui and state.process.ui.permission_active then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i = #lines, 1, -1 do
        if lines[i]:match("^%[%?%]") then
          vim.api.nvim_win_set_cursor(0, {i, 0})
          vim.notify("[.chat] Jumped to tool permission prompt. Use [y/a/n/c].", vim.log.levels.INFO)
          return
        end
      end
      vim.notify("[.chat] No tool permission prompt found in buffer.", vim.log.levels.WARN)
    else
      M.hybrid_send(buf)
    end
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
        proc.ui.permission_active = false
        proc.ui.permission_queue = {}
      end

      -- Cancel active questionnaire
      local q_ok, questionnaire = pcall(require, "ai_repl.questionnaire")
      if q_ok then pcall(questionnaire.cancel) end

      -- Cancel current operation but keep the process alive
      proc:cancel()

      -- Ensure state is clean for immediate new message
      proc.state.busy = false
      proc.state.session_ready = true
    end

    -- Reset streaming state
    state.streaming = false
    chat_buffer_events.stop_streaming(buf)
    local ok, decorations = pcall(require, "ai_repl.chat_decorations")
    if ok then pcall(decorations.stop_spinner, buf) end

    -- Append cancellation notice
    chat_buffer_events.append_to_chat_buffer(buf, { "", "[x] Cancelled", "" })

    -- Ensure @You: marker exists for new input
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        chat_buffer_events.ensure_you_marker(buf)
      end
    end)
  end, opts)

  -- Jump to next/previous message
  vim.keymap.set("n", "]m", function()
    chat_parser.jump_to_message(buf, 1)
  end, opts)

  vim.keymap.set("n", "[m", function()
    chat_parser.jump_to_message(buf, -1)
  end, opts)

  -- Jump to next/previous permission prompt
  vim.keymap.set("n", "]p", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    for i = current_line + 1, #lines do
      if lines[i]:match("^%[%?%]") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
    end
    vim.notify("[.chat] No more permission prompts below", vim.log.levels.INFO)
  end, vim.tbl_extend("force", opts, {
    desc = "Jump to next permission prompt"
  }))

  vim.keymap.set("n", "[p", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    for i = current_line - 1, 1, -1 do
      if lines[i]:match("^%[%?%]") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
    end
    vim.notify("[.chat] No more permission prompts above", vim.log.levels.INFO)
  end, vim.tbl_extend("force", opts, {
    desc = "Jump to previous permission prompt"
  }))

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

  -- Kill session
  vim.keymap.set("n", config.keys.kill_session, function()
    local state = get_state(buf)
    if state.process and state.process:is_alive() then
      vim.ui.select({
        "Yes, kill session",
        "No, keep session",
      }, {
        prompt = "Kill the current session? This will terminate the AI process.",
      }, function(choice, idx)
        if idx == 1 then
          local ai_repl = require("ai_repl")
          ai_repl.kill_session()
        end
      end)
    else
      vim.notify("[.chat] No active session to kill", vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", opts, {
    desc = "Kill current AI session"
  }))

  -- Force cancel (cancel + kill for stuck agents)
  vim.keymap.set("n", config.keys.force_cancel, function()
    local state = get_state(buf)
    if state.process and state.process:is_alive() then
      vim.ui.select({
        "Yes, force cancel",
        "No, keep session",
      }, {
        prompt = "Force cancel? This will cancel the current operation AND kill the session.",
      }, function(choice, idx)
        if idx == 1 then
          local ai_repl = require("ai_repl")
          ai_repl.force_cancel_session()
        end
      end)
    else
      vim.notify("[.chat] No active session to cancel", vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", opts, {
    desc = "Force cancel (cancel + kill) current AI session"
  }))

  -- Restart session (kill and create fresh)
  vim.keymap.set("n", config.keys.restart_session, function()
    vim.ui.select({
      "Yes, restart session",
      "No, keep session",
    }, {
      prompt = "Restart session? This will kill the current session and create a new one.",
    }, function(choice, idx)
      if idx == 1 then
        local ai_repl = require("ai_repl")
        ai_repl.restart_session()
      end
    end)
  end, vim.tbl_extend("force", opts, {
    desc = "Restart session (kill and create fresh)"
  }))

  -- Summarize conversation
  vim.keymap.set("n", "<leader>as", function()
    M.summarize_conversation(buf)
  end, vim.tbl_extend("force", opts, {
    desc = "Summarize conversation in .chat buffer"
  }))

  -- Open chat sessions picker (Oil-like)
  vim.keymap.set("n", "-", function()
    require("ai_repl.chat_sessions").toggle()
  end, vim.tbl_extend("force", opts, {
    desc = "Open chat sessions picker"
  }))
end

-- Hybrid send: tools → execute → send
function M.hybrid_send(buf)
  local state = get_state(buf)

  if not state.process then
    if state.creating_session then
      vim.notify("[.chat] Session is starting, please wait...", vim.log.levels.INFO)
      return false
    end

    state.creating_session = true
    vim.notify("[.chat] Starting session...", vim.log.levels.INFO)

    local ai_repl = require("ai_repl.init")
    local session_strategy = require("ai_repl.session_strategy")
    local current_repo = get_repo_root(buf)
    local strategy = ai_repl.get_config().session_strategy or "latest"

    session_strategy.get_or_create_session(strategy, current_repo, function(proc)
      state.creating_session = false
      if not proc then
        vim.notify("[.chat] Failed to create session.", vim.log.levels.ERROR)
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      chat_buffer_events.setup_event_forwarding(buf, proc)
      M.attach_session(buf, proc.session_id)
      ai_repl.update_statusline()

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.hybrid_send(buf)
        end
      end)
    end)
    return true
  end

  -- Check if process is alive
  if not state.process:is_alive() then
    vim.notify("[.chat] Process is not alive. Cannot send message.", vim.log.levels.ERROR)
    return false
  end

  -- Ensure session_ready is set if initialized (handles post-cancel state)
  if state.process.state.initialized and not state.process.state.session_ready then
    state.process.state.session_ready = true
  end

  -- Double-check readiness after fixing session_ready
  if not state.process:is_ready() then
    vim.notify("[.chat] Session not ready. Please wait...", vim.log.levels.WARN)
    return false
  end

  if state.process.ui and state.process.ui.permission_active then
    vim.notify("[.chat] Waiting for tool permission response. Use [y/a/n/c].", vim.log.levels.WARN)
    return false
  end

  local parsed = chat_parser.parse_buffer_cached(buf)

  -- Phase 0: Check for annotations to sync first
  if #parsed.annotations > 0 then
    local ok, msg = M.sync_annotations_from_buffer(buf)
    if ok then
      vim.notify("[.chat] " .. msg, vim.log.levels.INFO)
    end
  end

  -- Phase 3: Autosave before sending
  if config.save_on_send and config.auto_save then
    M.autosave_buffer(buf)
  end

  -- Phase 4: Send to process
  return M.send_to_process(buf)
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
        autosave_timer = vim.uv.new_timer()
        autosave_timer:start(config.auto_save_delay, 0, vim.schedule_wrap(function()
          if autosave_timer then
            autosave_timer:stop()
            autosave_timer:close()
            autosave_timer = nil
          end
          if vim.api.nvim_buf_is_valid(buf) then
            M.autosave_buffer(buf)
          end
        end))
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
      -- Clean up autosave timer
      if autosave_timer then
        autosave_timer:stop()
        autosave_timer:close()
        autosave_timer = nil
      end

      -- Final autosave before deletion
      if config.auto_save then
        M.autosave_buffer(buf)
      end

      -- Kill the session process if this buffer is attached to one
      local state = get_state(buf)
      if state.session_id and state.process and state.process:is_alive() then
        vim.notify("[.chat] Killing session " .. state.session_id, vim.log.levels.INFO)
        registry.remove(state.session_id)
      end

      M.detach_session(buf)
      chat_state.cleanup_buffer_state(buf)
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
  local parsed = chat_parser.parse_buffer_cached(buf)

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
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and M.is_chat_buffer(buf) then
      return buf
    end
  end
  return nil
end

return M
