local M = {}

local Process = require("ai_repl.process")
local registry = require("ai_repl.registry")
local render = require("ai_repl.render")

local config = {
  window = {
    width = 0.45,
    border = "rounded",
    title = "AI REPL"
  },
  provider = {
    cmd = "claude-code-acp",
    args = {},
    env = {}
  },
  adapter = "claude",
  history_size = 1000,
  permission_mode = "default",
  show_tool_calls = true,
  debug = false,
  reconnect = true,
  max_reconnect_attempts = 3,
  sessions_file = vim.fn.stdpath("data") .. "/ai_repl_sessions.json",
  max_sessions_per_project = 20
}

local ui = {
  wins = {},  -- per-tab windows: { [tabpage] = win }
  active = false,
  source_buf = nil,
  project_root = nil,
}

local function get_tab_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local win = ui.wins[tab]
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  ui.wins[tab] = nil
  return nil
end

local function set_tab_win(win)
  local tab = vim.api.nvim_get_current_tabpage()
  ui.wins[tab] = win
end

local function clear_tab_win()
  local tab = vim.api.nvim_get_current_tabpage()
  ui.wins[tab] = nil
end

local function get_project_root(buf)
  local file = buf and vim.api.nvim_buf_get_name(buf) or vim.api.nvim_buf_get_name(0)
  local dir = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return git_root
  end
  return dir
end

local function get_current_project_root()
  if ui.project_root then
    return ui.project_root
  end
  return get_project_root(ui.source_buf)
end

local function get_session_name(cwd)
  cwd = cwd or get_current_project_root()
  local dir_name = vim.fn.fnamemodify(cwd, ":t")
  local branch = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " branch --show-current 2>/dev/null")[1]
  if vim.v.shell_error == 0 and branch and branch ~= "" then
    return dir_name .. "/" .. branch
  end
  return dir_name
end

local function simplify_agent_name(name)
  if not name then return "Agent" end
  local simplified = name:gsub("^@[^/]+/", "")
  local friendly_names = {
    ["claude-code-acp"] = "Claude Code",
  }
  return friendly_names[simplified] or simplified
end

local function count_background_busy()
  local count = 0
  local active_id = registry.active_session_id()
  for sid, p in pairs(registry.all()) do
    if sid ~= active_id and p.state.busy then
      count = count + 1
    end
  end
  return count
end

local function update_statusline()
  local proc = registry.active()
  local win = get_tab_win()
  if not win then return end
  local agent_name = simplify_agent_name(proc and proc.state.agent_info and proc.state.agent_info.name)
  local mode = proc and proc.state.mode or "plan"
  local queue_count = proc and #proc.data.prompt_queue or 0
  local queue_str = queue_count > 0 and (" Q:" .. queue_count) or ""
  local busy_str = proc and proc.state.busy and " ●" or ""
  local bg_count = count_background_busy()
  local bg_str = bg_count > 0 and (" [" .. bg_count .. " bg]") or ""
  vim.wo[win].statusline = " " .. agent_name .. " [" .. mode .. "]" .. busy_str .. queue_str .. bg_str
end

local function setup_window_options(win)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
end

local function handle_session_update(proc, params)
  local u = params.update
  if not u then return end

  local buf = proc.data.buf
  local update_type = u.sessionUpdate

  if config.debug and update_type ~= "agent_message_chunk" then
    render.append_content(buf, { "[debug] " .. (update_type or "unknown") })
  end

  if update_type == "agent_message_chunk" then
    render.start_animation(buf, "generating")
    local content = u.content
    if content and content.text then
      render.update_streaming(buf, content.text, proc.ui)
    end

  elseif update_type == "current_mode_update" then
    proc.state.mode = u.modeId or u.currentModeId
    update_statusline()

  elseif update_type == "tool_call" then
    local tool = {
      id = u.toolCallId,
      title = u.title,
      kind = u.kind,
      status = u.status or "pending",
      locations = u.locations,
      rawInput = u.rawInput,
      content = u.content
    }
    proc.ui.active_tools[u.toolCallId] = tool
    table.insert(proc.ui.pending_tool_calls, {
      id = u.toolCallId, title = u.title, kind = u.kind, input = u.rawInput
    })

    if u.title == "TodoWrite" and u.rawInput and u.rawInput.todos then
      proc.ui.current_plan = u.rawInput.todos
      render.render_plan(buf, proc.ui.current_plan)
      return
    elseif u.title == "ExitPlanMode" then
      render.append_content(buf, { "[>] Exiting plan mode..." })
      return
    elseif u.title == "AskUserQuestion" or (u.rawInput and u.rawInput.questions) then
      render.stop_animation()
      local questions = u.rawInput and u.rawInput.questions or {}
      for _, q in ipairs(questions) do
        render.append_content(buf, { "", "[?] " .. (q.question or "Question") })
        if q.options then
          for i, opt in ipairs(q.options) do
            render.append_content(buf, { "  " .. i .. ". " .. (opt.label or opt) })
          end
        end
      end
      if #questions > 0 then
        vim.schedule(function()
          local q = questions[1]
          if q.options and #q.options > 0 then
            local labels = {}
            for _, opt in ipairs(q.options) do
              table.insert(labels, opt.label or opt)
            end
            vim.ui.select(labels, { prompt = q.question or "Select:" }, function(choice)
              if choice then M.send_prompt(choice) end
            end)
          else
            vim.ui.input({ prompt = (q.question or "Answer") .. ": " }, function(input)
              if input and input ~= "" then M.send_prompt(input) end
            end)
          end
        end)
      end
    else
      render.start_animation(buf, "executing")
      render.render_tool(buf, tool)
    end

  elseif update_type == "tool_call_update" then
    local tool = proc.ui.active_tools[u.toolCallId] or {}
    tool.status = u.status or tool.status
    tool.title = u.title or tool.title
    tool.kind = u.kind or tool.kind
    tool.locations = u.locations or tool.locations
    tool.rawOutput = u.rawOutput or tool.rawOutput
    tool.rawInput = tool.rawInput or u.rawInput

    if u.content and type(u.content) == "table" then
      for _, block in ipairs(u.content) do
        if block.type == "diff" then
          tool.diff = {
            path = block.path,
            oldText = block.oldText,
            newText = block.newText,
          }
          break
        end
      end
      tool.content = u.content
    end

    proc.ui.active_tools[u.toolCallId] = tool

    if u.status == "completed" or u.status == "failed" then
      render.stop_animation()

      local is_edit_tool = tool.kind == "edit" or tool.kind == "write"
        or tool.title == "Edit" or tool.title == "Write"

      if u.status == "completed" and is_edit_tool then
        local file_path, old_text, new_text

        if tool.diff then
          file_path = tool.diff.path
          old_text = tool.diff.oldText
          new_text = tool.diff.newText
        end

        if not file_path and tool.locations and #tool.locations > 0 then
          local loc = tool.locations[1]
          file_path = loc.path or loc.uri
          if file_path then
            file_path = file_path:gsub("^file://", "")
          end
        end

        if not file_path and tool.rawInput then
          file_path = tool.rawInput.file_path or tool.rawInput.path
        end

        if not old_text and tool.rawInput then
          old_text = tool.rawInput.old_string or tool.rawInput.oldString
        end

        if not new_text and tool.rawInput then
          new_text = tool.rawInput.new_string or tool.rawInput.newString or tool.rawInput.content
        end

        if file_path and (old_text or new_text) then
          render.render_diff(buf, file_path, old_text or "", new_text or "")
        end
      end

      if tool.title ~= "AskUserQuestion" then
        render.render_tool(buf, tool)
      end

      if tool.title == "ExitPlanMode" and u.status == "completed" then
        render.append_content(buf, { "[>] Starting execution..." })
        vim.defer_fn(function()
          M.send_prompt("proceed with the plan", { silent = true })
        end, 200)
      end

      proc.ui.active_tools[u.toolCallId] = nil
    end

  elseif update_type == "plan" then
    proc.ui.current_plan = u.entries or u.plan or {}
    if type(proc.ui.current_plan) == "table" and proc.ui.current_plan.entries then
      proc.ui.current_plan = proc.ui.current_plan.entries
    end
    render.render_plan(buf, proc.ui.current_plan)

  elseif update_type == "available_commands_update" then
    proc.data.slash_commands = u.availableCommands or {}

  elseif update_type == "stop" then
    render.stop_animation()
    proc.state.busy = false

    if proc.ui.streaming_response and proc.ui.streaming_response ~= "" then
      local tool_calls_to_save = nil
      if #proc.ui.pending_tool_calls > 0 then
        tool_calls_to_save = vim.deepcopy(proc.ui.pending_tool_calls)
      end
      registry.append_message(proc.session_id, "assistant", proc.ui.streaming_response, tool_calls_to_save)

      if #proc.ui.current_plan == 0 then
        local md_plan = render.parse_markdown_plan(proc.ui.streaming_response)
        if #md_plan >= 3 then
          proc.ui.current_plan = md_plan
          render.render_plan(buf, md_plan)
        end
      end
    end

    proc.ui.current_plan = {}
    proc.ui.active_tools = {}
    proc.ui.pending_tool_calls = {}
    render.finish_streaming(buf, proc.ui)

    local reason = u.stopReason or "end_turn"
    local reason_msgs = {
      end_turn = "---",
      max_tokens = "[!] Stopped: token limit",
      max_turn_requests = "[!] Stopped: turn limit",
      refusal = "[!] Agent refused",
      cancelled = "[x] Cancelled"
    }
    local mode_str = proc.state.mode and (" [" .. proc.state.mode .. "]") or ""
    local queue_count = #proc.data.prompt_queue
    local queue_info = queue_count > 0 and (" [" .. queue_count .. " queued]") or ""
    render.append_content(buf, { "", (reason_msgs[reason] or "---") .. mode_str .. queue_info, "" })

    update_statusline()

    vim.defer_fn(function()
      proc:process_queued_prompts()
      update_statusline()
    end, 200)

  elseif update_type == "modes" then
    proc.state.modes = u.modes or {}
    proc.state.mode = u.currentModeId
    update_statusline()

  elseif update_type == "agent_thought_chunk" then
    render.start_animation(buf, "thinking")
  end
end

local TOOL_NAMES = {
  Read = "Read",
  Edit = "Edit",
  Write = "Write",
  Bash = "Run",
  Glob = "Find Files",
  Grep = "Search",
  Task = "Agent",
  WebFetch = "Fetch",
  WebSearch = "Web Search",
  TodoWrite = "Plan",
  NotebookEdit = "Notebook",
  LSP = "LSP",
  KillShell = "Kill Process",
}

local function get_tool_description(title, input, locations)
  if title == "Read" then
    local path = input.file_path or input.path or ""
    return vim.fn.fnamemodify(path, ":~:.")
  elseif title == "Edit" then
    local path = input.file_path or input.path or ""
    return vim.fn.fnamemodify(path, ":~:.")
  elseif title == "Write" then
    local path = input.file_path or input.path or ""
    return vim.fn.fnamemodify(path, ":~:.")
  elseif title == "Bash" then
    local desc = input.description or ""
    if desc ~= "" then return desc end
    local cmd = input.command or ""
    if #cmd > 60 then cmd = cmd:sub(1, 57) .. "..." end
    return cmd
  elseif title == "Glob" then
    return input.pattern or ""
  elseif title == "Grep" then
    return (input.pattern or "") .. (input.path and (" in " .. vim.fn.fnamemodify(input.path, ":~:.")) or "")
  elseif title == "Task" then
    return input.description or ""
  elseif title == "WebFetch" then
    local url = input.url or ""
    return url:match("://([^/]+)") or url:sub(1, 40)
  elseif title == "WebSearch" then
    return input.query or ""
  elseif title == "LSP" then
    return input.operation or ""
  elseif title == "KillShell" then
    return input.shell_id or ""
  end

  if locations and #locations > 0 then
    local l = locations[1]
    local path = l.path or l.uri or ""
    local loc = vim.fn.fnamemodify(path, ":~:.")
    if l.line then loc = loc .. ":" .. l.line end
    return loc
  end

  return ""
end

local function handle_permission_request(proc, msg_id, params)
  render.stop_animation()
  local buf = proc.data.buf

  vim.schedule(function()
    local tool = params.toolCall or {}
    local tool_id = tool.toolCallId or tool.id

    if config.debug then
      render.append_content(buf, { "[debug] permission params: " .. vim.inspect(params):sub(1, 500) })
    end

    local stored_tool = tool_id and proc.ui.active_tools[tool_id] or {}

    local raw_input = tool.rawInput
      or tool.input
      or params.rawInput
      or params.input
      or stored_tool.rawInput
      or stored_tool.input
    if type(raw_input) == "string" then
      local ok, parsed = pcall(vim.json.decode, raw_input)
      raw_input = ok and parsed or {}
    end
    local input = raw_input or {}
    if vim.tbl_isempty(input) and tool.parameters then
      input = tool.parameters
    end

    local tool_kind = tool.kind or stored_tool.kind or ""
    local title_str = tool.title or stored_tool.title or ""
    local raw_title = title_str:match("^`?(%w+)") or tool_kind or "tool"
    local friendly_name = TOOL_NAMES[raw_title] or raw_title
    local locations = tool.locations or stored_tool.locations or {}

    if config.debug then
      render.append_content(buf, { "[debug] raw_title=" .. raw_title .. " kind=" .. tool_kind })
      render.append_content(buf, { "[debug] input: " .. vim.inspect(input):sub(1, 800) })
    end

    local desc = get_tool_description(raw_title, input, locations)

    local agent_options = params.options or {}
    local first_allow_id, first_deny_id, allow_always_id
    for _, opt in ipairs(agent_options) do
      local oid = opt.optionId or opt.id
      local okind = opt.kind or ""
      if oid then
        if oid:match("allow_always") or oid:match("allowAlways") then
          allow_always_id = allow_always_id or oid
        elseif okind:match("allow") or oid:match("allow") or oid:match("yes") or oid:match("approve") then
          first_allow_id = first_allow_id or oid
        end
        if okind:match("deny") or oid:match("deny") or oid:match("no") or oid:match("reject") then
          first_deny_id = first_deny_id or oid
        end
      end
    end

    local mode = config.permission_mode
    if mode == "bypassPermissions" or mode == "dontAsk" then
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = first_allow_id or "allow_always" } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
      return
    end

    local file_path = input.file_path or input.filePath or input.path
    local old_str = input.old_string or input.oldString or input.oldText
    local new_str = input.new_string or input.newString or input.newText

    local tool_content = tool.content or stored_tool.content
    if tool_content and type(tool_content) == "table" then
      for _, block in ipairs(tool_content) do
        if block.type == "diff" then
          file_path = file_path or block.path
          old_str = old_str or block.oldText
          new_str = new_str or block.newText
          break
        end
      end
    end

    if not file_path and locations and #locations > 0 then
      local loc = locations[1]
      file_path = loc.path or loc.uri
      if file_path then
        file_path = file_path:gsub("^file://", "")
      end
    end

    local is_edit = raw_title == "Edit" or raw_title == "Write" or tool_kind == "edit"
    if is_edit and old_str and new_str then
      render.render_diff(buf, file_path or "file", old_str, new_str)
    elseif is_edit and input.content and file_path then
      local old_content = ""
      if vim.fn.filereadable(file_path) == 1 then
        old_content = table.concat(vim.fn.readfile(file_path), "\n")
      end
      render.render_diff(buf, file_path, old_content, input.content)
    elseif raw_title == "Bash" and input.command then
      render.append_content(buf, { "$ " .. input.command })
    end

    local display = friendly_name
    if desc ~= "" then
      display = display .. ": " .. desc
    end
    render.append_content(buf, { "", "[?] " .. display })

    local function send_selected(option_id)
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = option_id } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
    end

    local function send_cancelled()
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "cancelled" } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
    end

    render.append_content(buf, { "  [y] Allow  [a] Always  [n] Deny  [c] Cancel" })

    local answered = false
    local function cleanup_keymaps()
      for _, key in ipairs({ "y", "a", "n", "c" }) do
        pcall(vim.keymap.del, "n", key, { buffer = buf })
      end
    end

    local function handle_choice(choice)
      if answered then return end
      answered = true
      cleanup_keymaps()

      if choice == "y" then
        render.append_content(buf, { "[+] Allowed" })
        send_selected(first_allow_id or "allow_once")
      elseif choice == "a" then
        render.append_content(buf, { "[+] Always allowed" })
        send_selected(allow_always_id or "allow_always")
      elseif choice == "n" then
        render.append_content(buf, { "[x] Denied" })
        send_selected(first_deny_id or "reject_once")
      else
        render.append_content(buf, { "[x] Cancelled" })
        send_cancelled()
      end
    end

    local opts = { buffer = buf, nowait = true }
    vim.keymap.set("n", "y", function() handle_choice("y") end, opts)
    vim.keymap.set("n", "a", function() handle_choice("a") end, opts)
    vim.keymap.set("n", "n", function() handle_choice("n") end, opts)
    vim.keymap.set("n", "c", function() handle_choice("c") end, opts)
  end)
end

local function handle_method(proc, method, params, msg_id)
  local buf = proc.data.buf
  local is_active = proc.session_id == registry.active_session_id()

  if method == "session/update" then
    handle_session_update(proc, params)

    if not is_active then
      local u = params.update
      if u and u.sessionUpdate == "stop" then
        update_statusline()
        local agent_name = proc:get_agent_name()
        vim.notify("Background: " .. agent_name .. " completed", vim.log.levels.INFO)
      end
    end

  elseif method == "session/request_permission" then
    if is_active then
      handle_permission_request(proc, msg_id, params)
    else
      local response = {
        jsonrpc = "2.0",
        id = msg_id,
        result = { outcome = { outcome = "selected", optionId = "allow_always" } }
      }
      vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
      render.append_content(buf, { "[+] Auto-approved (background): " .. (params.toolCall and params.toolCall.title or "tool") })
    end

  elseif method:match("^terminal/") then
    local response = {
      jsonrpc = "2.0",
      id = msg_id,
      result = {}
    }
    if method == "terminal/create" then
      local term_id = "term_" .. os.time() .. "_" .. math.random(1000, 9999)
      proc.data.terminals[term_id] = { id = term_id, buf = nil }
      response.result = { terminalId = term_id }
    end
    vim.fn.chansend(proc.job_id, vim.json.encode(response) .. "\n")
  end
end

local function create_process(session_id, opts)
  opts = opts or {}

  local proc = Process.new(session_id, {
    cmd = config.provider.cmd,
    args = config.provider.args,
    env = vim.tbl_extend("force", config.provider.env, opts.env or {}),
    cwd = opts.cwd or get_current_project_root(),
    debug = config.debug,
    load_session_id = opts.load_session_id,
  })
  proc._created_at = os.time()

  proc:set_handlers({
    on_method = function(self, method, params, msg_id)
      handle_method(self, method, params, msg_id)
    end,
    on_debug = function(self, line)
      if self.data.buf then
        render.append_content(self.data.buf, { "[debug] " .. line })
      end
    end,
    on_exit = function(self, code, was_alive)
      render.stop_animation()
      if code ~= 0 and self.data.buf and was_alive then
        render.append_content(self.data.buf, { "Process exited with code: " .. code })
        if config.reconnect and ui.active and self.state.reconnect_count < config.max_reconnect_attempts then
          self.state.reconnect_count = self.state.reconnect_count + 1
          render.append_content(self.data.buf, { "Reconnecting... (" .. self.state.reconnect_count .. "/" .. config.max_reconnect_attempts .. ")" })
          vim.defer_fn(function()
            if ui.active and self.session_id == registry.active_session_id() then
              self:restart()
            end
          end, 1000)
        end
      else
        self.state.reconnect_count = 0
      end
    end,
    on_ready = function(self)
      update_statusline()
    end,
    on_status = function(self, status, data)
      local buf = self.data.buf
      if not buf then return end

      if status == "initialized" then
        local caps = {}
        if self.state.agent_capabilities.loadSession then table.insert(caps, "sessions") end
        if self.state.agent_capabilities.modes then table.insert(caps, "modes") end
        if self.state.agent_capabilities.plans then table.insert(caps, "plans") end
        local agent_name = self:get_agent_name()
        local caps_str = #caps > 0 and " [" .. table.concat(caps, ", ") .. "]" or ""

        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_set_name, buf, agent_name)
        end
        render.append_content(buf, { "Connected: " .. agent_name .. caps_str })

      elseif status == "session_created" then
        local session_name = get_session_name(self.data.cwd)
        self.data.name = session_name
        local buf_name = "AI: " .. session_name
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_set_name, buf, buf_name)
        end
        render.append_content(buf, { "Project: " .. self.data.cwd, "[+] Session ready", "" })
        update_statusline()

      elseif status == "session_loaded" then
        if not self.data.name or self.data.name == "New Session" then
          local session_name = get_session_name(self.data.cwd)
          self.data.name = session_name
          local buf_name = "AI: " .. session_name
          if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_set_name, buf, buf_name)
          end
        end
        local messages = registry.load_messages(self.session_id)
        if messages and #messages > 0 then
          render.render_history(buf, messages)
        else
          render.append_content(buf, { "[+] Session loaded: " .. self.session_id:sub(1, 8) .. "...", "" })
        end
        update_statusline()

      elseif status == "session_load_failed" then
        render.append_content(buf, { "[!] Session load failed, creating new..." })

      elseif status == "init_failed" or status == "session_failed" then
        render.append_content(buf, { "[!] Error: " .. tostring(data) })
      end
    end,
  })

  proc._on_session_id_changed = function(self, old_id, new_id)
    local was_active = registry.active_session_id() == old_id
    registry.unregister(old_id)
    registry.set(new_id, self)
    if was_active then
      registry.set_active(new_id)
    end
  end

  return proc
end

local function create_buffer(proc, name)
  local buf = vim.api.nvim_create_buf(true, false)
  local session_name = name or get_session_name(proc.data.cwd)
  local buf_name = "AI: " .. session_name
  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  render.init_buffer(buf)
  proc.data.buf = buf
  proc.data.name = session_name

  return buf
end

local IMAGE_EXTENSIONS = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  svg = "image/svg+xml",
}

local function get_mime_type(file_path)
  local ext = file_path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if IMAGE_EXTENSIONS[ext] then
      return IMAGE_EXTENSIONS[ext], true
    end
  end
  return "text/plain", false
end

local function read_file_content(file_path, is_image)
  if is_image then
    local f = io.open(file_path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local ok, encoded = pcall(function()
      return vim.base64.encode(data)
    end)
    if ok then return encoded end
    return nil
  else
    local lines = vim.fn.readfile(file_path)
    return table.concat(lines, "\n")
  end
end

local function parse_file_references(text)
  local prompt = {}
  local files = {}
  local remaining_text = text

  for file_ref in text:gmatch("@([^%s]+)") do
    local abs_path = vim.fn.fnamemodify(file_ref, ":p")
    if vim.fn.filereadable(abs_path) == 1 then
      table.insert(files, abs_path)
      remaining_text = remaining_text:gsub("@" .. vim.pesc(file_ref), "", 1)
    end
  end

  for _, file_path in ipairs(files) do
    local mime_type, is_image = get_mime_type(file_path)
    local content = read_file_content(file_path, is_image)

    if content then
      local resource = {
        uri = "file://" .. file_path,
        name = vim.fn.fnamemodify(file_path, ":t"),
        mimeType = mime_type,
      }
      if is_image then
        resource.blob = content
      else
        resource.text = content
      end
      table.insert(prompt, { type = "resource", resource = resource })
    end
  end

  remaining_text = remaining_text:gsub("^%s*(.-)%s*$", "%1")
  if remaining_text ~= "" then
    table.insert(prompt, { type = "text", text = remaining_text })
  end

  return prompt, #files > 0
end

local function setup_buffer_keymaps(buf)
  local function submit()
    local raw_text = render.get_prompt_input(buf)
    local text = raw_text:gsub("^%s*(.-)%s*$", "%1")
    if text == "" then
      vim.notify("AI REPL: Empty prompt", vim.log.levels.DEBUG)
      return
    end
    render.clear_prompt_input(buf)

    if text:sub(1, 1) == "/" then
      M.handle_command(text:sub(2))
    else
      local proc = registry.active()
      local prompt, has_files = parse_file_references(text)

      if proc and #proc.data.context_files > 0 then
        for _, file_path in ipairs(proc.data.context_files) do
          local mime_type, is_image = get_mime_type(file_path)
          local file_content = read_file_content(file_path, is_image)
          if file_content then
            local resource = {
              uri = "file://" .. file_path,
              name = vim.fn.fnamemodify(file_path, ":t"),
              mimeType = mime_type,
            }
            if is_image then
              resource.blob = file_content
            else
              resource.text = file_content
            end
            table.insert(prompt, 1, { type = "resource", resource = resource })
          end
        end
        proc.data.context_files = {}
      end

      if has_files or #prompt > 1 then
        M.send_prompt(prompt)
      else
        M.send_prompt(text)
      end
    end
  end

  render.setup_cursor_lock(buf)

  local opts = { buffer = buf, silent = true }
  vim.keymap.set("i", "<CR>", submit, opts)
  vim.keymap.set("n", "<CR>", submit, opts)
  vim.keymap.set("n", "q", M.hide, opts)
  vim.keymap.set("n", "<Esc>", M.hide, opts)
  vim.keymap.set("n", "<C-c>", M.cancel, opts)
  vim.keymap.set("i", "<C-c>", M.cancel, opts)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() M.show_mode_picker() end, opts)
  vim.keymap.set("n", "<C-q>", M.show_queue, opts)
  vim.keymap.set("n", "<C-e>", M.edit_queued, opts)
  vim.keymap.set("n", "i", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)
  vim.keymap.set("n", "a", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)
  vim.keymap.set("n", "G", function()
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then render.goto_prompt(buf, win) end
  end, opts)

  vim.keymap.set("i", "@", function()
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      local root = get_current_project_root()
      local target_buf = buf
      local target_win = vim.api.nvim_get_current_win()
      snacks.picker.files({
        layout = { preset = "vscode" },
        cwd = root,
        confirm = function(picker, item)
          picker:close()
          if item then
            local file_path = item.file or item[1]
            if file_path then
              local rel_path = vim.fn.fnamemodify(file_path, ":.")
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(target_buf) and vim.api.nvim_win_is_valid(target_win) then
                  vim.api.nvim_set_current_win(target_win)
                  vim.api.nvim_win_set_buf(target_win, target_buf)
                  vim.cmd("startinsert")
                  vim.api.nvim_put({ "@" .. rel_path .. " " }, "c", false, true)
                end
              end)
            end
          end
        end,
        on_close = function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(target_buf) and vim.api.nvim_win_is_valid(target_win) then
              vim.api.nvim_set_current_win(target_win)
              vim.cmd("startinsert")
            end
          end)
        end,
      })
    else
      vim.api.nvim_put({ "@" }, "c", false, true)
    end
  end, opts)

  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      local p, sid = registry.get_by_buffer(buf)
      if p and sid and sid ~= registry.active_session_id() then
        registry.set_active(sid)
        update_statusline()
      end
    end
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      render.cleanup_buffer(buf)
    end
  })
end

local function create_ui()
  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width

  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  set_tab_win(win)
  vim.api.nvim_win_set_width(win, width)
  setup_window_options(win)

  local temp_id = "temp_" .. os.time() .. "_" .. math.random(1000, 9999)
  local proc = create_process(temp_id, { cwd = ui.project_root })
  local buf = create_buffer(proc, "New Session")

  registry.set(temp_id, proc)
  registry.set_active(temp_id)

  vim.api.nvim_win_set_buf(win, buf)
  setup_buffer_keymaps(buf)

  render.append_content(buf, { "AI REPL | /help for commands", "" })

  proc:start()

  render.goto_prompt(buf, win)
end

function M.send_prompt(content, opts)
  opts = opts or {}
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  if not proc:is_alive() then
    render.append_content(proc.data.buf, { "Error: Agent not running" })
    return
  end

  if not proc:is_ready() then
    render.append_content(proc.data.buf, { "Error: Session not ready yet, please wait..." })
    return
  end

  local prompt
  local user_message_text = ""

  if type(content) == "string" then
    prompt = { { type = "text", text = content } }
    user_message_text = content
  elseif type(content) == "table" then
    prompt = content
    local preview = ""
    for _, block in ipairs(content) do
      if block.type == "text" then
        preview = preview .. block.text
      elseif block.type == "resource" then
        preview = preview .. "[" .. (block.resource.uri or "resource") .. "] "
      elseif block.type == "resource_link" then
        preview = preview .. "[@" .. (block.resourceLink and block.resourceLink.name or "file") .. "] "
      end
    end
    user_message_text = preview
  else
    return
  end

  local is_queued = proc.state.busy

  if not opts.silent then
    if is_queued then
      local queue_pos = #proc.data.prompt_queue + 1
      render.append_content(proc.data.buf, { "", "> " .. user_message_text:sub(1, 100) .. " [queued #" .. queue_pos .. "]" })
    else
      render.append_content(proc.data.buf, { "", "> " .. user_message_text:sub(1, 100) })
    end
  end

  if not opts.silent and user_message_text ~= "" then
    registry.append_message(proc.session_id, "user", user_message_text)
  end

  proc:send_prompt(prompt)
  update_statusline()
end

function M.set_mode(mode_id)
  local proc = registry.active()
  if not proc or not proc:is_ready() then return end
  proc:set_mode(mode_id)
  update_statusline()
  render.append_content(proc.data.buf, { "Mode set to: " .. mode_id })
end

function M.cancel()
  local proc = registry.active()
  if not proc then return end
  proc:cancel()
  render.stop_animation()
  render.append_content(proc.data.buf, { "Cancelled" })
end

function M.show_queue()
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    render.append_content(proc.data.buf, { "[i] Queue is empty" })
    return
  end

  local lines = { "", "━━━ Queue ━━━" }
  for i, item in ipairs(queue) do
    local text = item.text or (type(item.prompt) == "string" and item.prompt or "")
    if #text > 60 then text = text:sub(1, 57) .. "..." end
    table.insert(lines, string.format(" %d. %s", i, text))
  end
  table.insert(lines, "━━━━━━━━━━━━")
  table.insert(lines, "")
  render.append_content(proc.data.buf, lines)
end

function M.edit_queued(index)
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  local function do_edit(idx)
    local item = proc:get_queued_item(idx)
    if not item then
      vim.notify("Invalid queue index: " .. idx, vim.log.levels.ERROR)
      return
    end

    local current_text = item.text or (type(item.prompt) == "string" and item.prompt or "")
    vim.ui.input({ prompt = "Edit queued #" .. idx .. ": ", default = current_text }, function(new_text)
      if new_text and new_text ~= "" then
        proc:update_queued_item(idx, new_text)
        render.append_content(proc.data.buf, { "[+] Updated queued #" .. idx })
        update_statusline()
      end
    end)
  end

  if index then
    do_edit(index)
  elseif #queue == 1 then
    do_edit(1)
  else
    local items = {}
    for i, item in ipairs(queue) do
      local text = item.text or (type(item.prompt) == "string" and item.prompt or "")
      if #text > 50 then text = text:sub(1, 47) .. "..." end
      table.insert(items, string.format("#%d: %s", i, text))
    end

    vim.ui.select(items, { prompt = "Select message to edit:" }, function(choice, idx)
      if choice and idx then
        do_edit(idx)
      end
    end)
  end
end

function M.remove_queued(index)
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local queue = proc:get_queue()
  if #queue == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  local function do_remove(idx)
    local removed = proc:remove_queued_item(idx)
    if removed then
      render.append_content(proc.data.buf, { "[x] Removed queued #" .. idx })
      update_statusline()
    else
      vim.notify("Invalid queue index: " .. idx, vim.log.levels.ERROR)
    end
  end

  if index then
    do_remove(index)
  elseif #queue == 1 then
    do_remove(1)
  else
    local items = {}
    for i, item in ipairs(queue) do
      local text = item.text or (type(item.prompt) == "string" and item.prompt or "")
      if #text > 50 then text = text:sub(1, 47) .. "..." end
      table.insert(items, string.format("#%d: %s", i, text))
    end

    vim.ui.select(items, { prompt = "Select message to remove:" }, function(choice, idx)
      if choice and idx then
        do_remove(idx)
      end
    end)
  end
end

function M.clear_queue()
  local proc = registry.active()
  if not proc then
    vim.notify("No active AI session", vim.log.levels.ERROR)
    return
  end

  local count = #proc:get_queue()
  if count == 0 then
    vim.notify("Queue is empty", vim.log.levels.INFO)
    return
  end

  proc:clear_queue()
  render.append_content(proc.data.buf, { "[x] Cleared " .. count .. " queued messages" })
  update_statusline()
end

local function get_settings_path()
  local proc = registry.active()
  local cwd = proc and proc.data.cwd or vim.fn.getcwd()
  return cwd .. "/.claude/settings.local.json"
end

local function read_settings()
  local path = get_settings_path()
  if vim.fn.filereadable(path) ~= 1 then return nil end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and data or nil
end

local function write_settings(data)
  local path = get_settings_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

function M.show_permissions()
  local proc = registry.active()
  if not proc then return end

  local data = read_settings()
  local allow = data and data.permissions and data.permissions.allow or {}

  if #allow == 0 then
    render.append_content(proc.data.buf, { "[i] No allow rules" })
    return
  end

  local lines = { "", "━━━ Allowed ━━━" }
  for i, rule in ipairs(allow) do
    table.insert(lines, string.format("  %d. %s", i, rule))
  end
  table.insert(lines, "━━━━━━━━━━━━━━━")
  render.append_content(proc.data.buf, lines)
end

function M.revoke_permission()
  local proc = registry.active()
  if not proc then return end

  local data = read_settings()
  local allow = data and data.permissions and data.permissions.allow or {}

  if #allow == 0 then
    vim.notify("No permissions to revoke", vim.log.levels.INFO)
    return
  end

  vim.ui.select(allow, { prompt = "Revoke:" }, function(choice, idx)
    if not choice then return end
    table.remove(data.permissions.allow, idx)
    write_settings(data)
    render.append_content(proc.data.buf, { "[x] Revoked: " .. choice })
  end)
end

function M.handle_command(cmd)
  local proc = registry.active()
  local buf = proc and proc.data.buf

  local parts = vim.split(cmd, "%s+", { trimempty = true })
  local command = parts[1] or ""
  local args = { unpack(parts, 2) }

  if command == "help" or command == "h" then
    render.append_content(buf, {
      "", "Commands:",
      "  /help - Show this help",
      "  /new - New session",
      "  /sessions - List sessions",
      "  /cm - Agent slash commands",
      "  /mode <mode> - Set mode",
      "  /cwd [path] - Show/change working directory",
      "  /queue - Show queued messages",
      "  /edit [n] - Edit queued message",
      "  /remove [n] - Remove queued message",
      "  /clearq - Clear all queued messages",
      "  /perms - Show allow rules",
      "  /revoke - Revoke allow rule",
      "  /clear - Clear buffer",
      "  /cancel - Cancel current",
      "  /quit - Close REPL",
      ""
    })
  elseif command == "new" then
    M.new_session()
  elseif command == "sessions" then
    M.open_session_picker()
  elseif command == "mode" then
    if args[1] then
      M.set_mode(args[1])
    else
      M.show_mode_picker()
    end
  elseif command == "cwd" then
    if args[1] then
      local new_cwd = vim.fn.expand(args[1])
      if vim.fn.isdirectory(new_cwd) == 1 then
        new_cwd = vim.fn.fnamemodify(new_cwd, ":p"):gsub("/$", "")
        if proc then
          proc.data.cwd = new_cwd
          ui.project_root = new_cwd
          render.append_content(buf, { "Working directory: " .. new_cwd })
        end
      else
        render.append_content(buf, { "[!] Not a directory: " .. new_cwd })
      end
    else
      local cwd = proc and proc.data.cwd or ui.project_root or vim.fn.getcwd()
      render.append_content(buf, { "Working directory: " .. cwd })
    end
  elseif command == "clear" then
    if buf then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      render.init_buffer(buf)
    end
  elseif command == "cancel" then
    M.cancel()
  elseif command == "queue" or command == "q" then
    M.show_queue()
  elseif command == "edit" or command == "e" then
    local idx = args[1] and tonumber(args[1])
    M.edit_queued(idx)
  elseif command == "remove" or command == "rm" then
    local idx = args[1] and tonumber(args[1])
    M.remove_queued(idx)
  elseif command == "clearq" or command == "cq" then
    M.clear_queue()
  elseif command == "perms" or command == "permissions" then
    M.show_permissions()
  elseif command == "revoke" then
    M.revoke_permission()
  elseif command == "quit" or command == "close" then
    M.close()
  elseif command == "debug" then
    config.debug = not config.debug
    if proc then
      proc.config.debug = config.debug
    end
    render.append_content(buf, { "Debug: " .. tostring(config.debug) })
  elseif command == "cm" or command == "commands" then
    if not proc or not proc.data.slash_commands or #proc.data.slash_commands == 0 then
      render.append_content(buf, { "[!] No agent commands available" })
      return
    end
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      local items = {}
      for _, sc in ipairs(proc.data.slash_commands) do
        table.insert(items, {
          text = sc.name .. (sc.description and (" - " .. sc.description) or ""),
          name = sc.name,
        })
      end
      snacks.picker.pick({
        source = "select",
        items = items,
        prompt = "Slash Commands",
        format = function(item) return { { item.text } } end,
        confirm = function(picker, item)
          picker:close()
          if item then
            vim.schedule(function()
              proc:notify("session/slash_command", {
                sessionId = proc.session_id,
                commandName = item.name,
                args = ""
              })
            end)
          end
        end,
      })
    else
      local lines = { "", "Agent Commands:" }
      for _, sc in ipairs(proc.data.slash_commands) do
        table.insert(lines, "  " .. sc.name .. (sc.description and (" - " .. sc.description) or ""))
      end
      table.insert(lines, "")
      render.append_content(buf, lines)
    end
  else
    if proc and proc.data.slash_commands then
      for _, sc in ipairs(proc.data.slash_commands) do
        if sc.name == command or sc.name == "/" .. command then
          proc:notify("session/slash_command", {
            sessionId = proc.session_id,
            commandName = sc.name,
            args = table.concat(args, " ")
          })
          return
        end
      end
    end
    render.append_content(buf, { "[!] Unknown command: " .. command })
  end
end

function M.show_mode_picker()
  local proc = registry.active()
  if not proc or not proc.state.modes or #proc.state.modes == 0 then
    vim.notify("No modes available", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, m in ipairs(proc.state.modes) do
    local prefix = m.id == proc.state.mode and "[*] " or "[ ] "
    table.insert(labels, prefix .. m.name)
  end

  vim.ui.select(labels, { prompt = "Select mode:" }, function(choice, idx)
    if not choice or not idx then return end
    local mode = proc.state.modes[idx]
    if mode then
      M.set_mode(mode.id)
    end
  end)
end

function M.open()
  local win = get_tab_win()
  if win then
    M.show()
    return
  end
  ui.active = true
  ui.source_buf = vim.api.nvim_get_current_buf()
  ui.project_root = get_project_root(ui.source_buf)
  create_ui()
end

function M.close()
  local win = get_tab_win()
  if win then
    vim.api.nvim_win_close(win, true)
  end
  clear_tab_win()
  ui.active = false
end

function M.hide()
  local win = get_tab_win()
  if win then
    vim.api.nvim_win_hide(win)
  end
end

function M.show()
  local proc = registry.active()
  if not proc or not proc.data.buf then
    M.open()
    return
  end

  local win = get_tab_win()
  if not win then
    local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
    vim.cmd("botright vsplit")
    win = vim.api.nvim_get_current_win()
    set_tab_win(win)
    vim.api.nvim_win_set_width(win, width)
    setup_window_options(win)
  end

  vim.api.nvim_win_set_buf(win, proc.data.buf)
  update_statusline()
  vim.api.nvim_set_current_win(win)
end

function M.toggle()
  local win = get_tab_win()
  if win then
    if vim.api.nvim_get_current_win() == win then
      M.hide()
    else
      vim.api.nvim_set_current_win(win)
    end
  else
    M.open()
  end
end

function M.new_session(opts)
  opts = opts or {}

  local cur_buf = vim.api.nvim_get_current_buf()
  local proc = registry.active()
  if not (proc and proc.data.buf and cur_buf == proc.data.buf) then
    ui.source_buf = cur_buf
  end
  ui.project_root = opts.cwd or get_project_root(ui.source_buf or cur_buf)

  local win = get_tab_win()
  if not win then
    ui.active = true
    create_ui()
    return
  end

  local width = config.window.width < 1 and math.floor(vim.o.columns * config.window.width) or config.window.width
  vim.api.nvim_win_set_width(win, width)
  setup_window_options(win)

  local temp_id = "temp_" .. os.time() .. "_" .. math.random(1000, 9999)
  local new_proc = create_process(temp_id, { cwd = ui.project_root })
  local buf = create_buffer(new_proc, "New Session")

  registry.set(temp_id, new_proc)
  registry.set_active(temp_id)

  vim.api.nvim_win_set_buf(win, buf)
  setup_buffer_keymaps(buf)

  render.append_content(buf, { "Creating new session..." })

  new_proc:start()

  render.goto_prompt(buf, win)
end

function M.load_session(session_id, opts)
  opts = opts or {}

  local existing = registry.get(session_id)
  if existing and existing:is_ready() then
    registry.set_active(session_id)
    local win = get_tab_win()
    if win then
      vim.api.nvim_win_set_buf(win, existing.data.buf)
    end
    update_statusline()
    render.append_content(existing.data.buf, { "[+] Switched to session: " .. session_id:sub(1, 8) .. "...", "" })
    return
  end

  local sessions = registry.load_from_disk()
  local session_info = sessions[session_id]

  local proc = create_process(session_id, {
    cwd = session_info and session_info.cwd or get_current_project_root(),
    env = session_info and session_info.env or {},
    load_session_id = session_id,
  })

  local buf = create_buffer(proc, session_info and session_info.name or nil)

  registry.set(session_id, proc)
  registry.set_active(session_id)

  local win = get_tab_win()
  if win then
    vim.api.nvim_win_set_buf(win, buf)
    setup_window_options(win)
  end

  setup_buffer_keymaps(buf)
  render.append_content(buf, { "Loading session " .. session_id:sub(1, 8) .. "..." })

  proc:start()

  if not win then
    win = vim.fn.bufwinid(buf)
  end
  if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
    render.goto_prompt(buf, win)
  end
end

function M.open_session_picker()
  local root = get_current_project_root()
  local disk_sessions = registry.get_sessions_for_project(root)
  local items = {}

  table.insert(items, { label = "+ New Session", action = "new" })

  for _, s in ipairs(disk_sessions) do
    local prefix
    if s.is_active then
      prefix = "[*] "
    elseif s.has_process then
      prefix = "[~] "
    else
      prefix = "[ ] "
    end
    table.insert(items, {
      label = prefix .. (s.name or s.session_id:sub(1, 8)),
      action = s.is_active and "current" or "load",
      id = s.session_id
    })
  end

  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, { prompt = "Select session:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    if item.action == "new" then
      M.new_session()
    elseif item.action == "load" then
      M.load_session(item.id)
    end
  end)
end

function M.pick_process()
  local running = registry.list_running()
  if #running == 0 then
    vim.notify("No active processes", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, r in ipairs(running) do
    local is_current = r.session_id == registry.active_session_id()
    local name = r.process.data.name or r.session_id:sub(1, 8)
    local status = is_current and "[*]" or "[~]"
    table.insert(items, {
      label = status .. " " .. name,
      session_id = r.session_id,
      is_current = is_current
    })
  end

  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, { prompt = "Select process:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    if not item.is_current then
      M.load_session(item.session_id)
    end
  end)
end

function M.switch_to_buffer()
  local all = registry.all()
  local items = {}

  for sid, proc in pairs(all) do
    if proc.data.buf and vim.api.nvim_buf_is_valid(proc.data.buf) then
      local is_current = sid == registry.active_session_id()
      local has_process = proc:is_alive()
      local name = proc.data.name or sid:sub(1, 8)
      local status = is_current and "[*]" or (has_process and "[~]" or "[ ]")

      table.insert(items, {
        label = status .. " " .. name,
        session_id = sid,
        buf = proc.data.buf,
        is_current = is_current
      })
    end
  end

  if #items == 0 then
    M.open()
    return
  end

  table.sort(items, function(a, b)
    if a.is_current then return true end
    if b.is_current then return false end
    return a.label < b.label
  end)

  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, { prompt = "Switch to buffer:" }, function(choice, idx)
    if not choice or not idx then return end
    local item = items[idx]
    local win = get_tab_win()
    if item.is_current then
      if win then
        vim.api.nvim_set_current_win(win)
      end
    else
      registry.set_active(item.session_id)
      if win then
        vim.api.nvim_win_set_buf(win, item.buf)
      end
      update_statusline()
    end
  end)
end

function M.kill_current_session()
  local proc = registry.active()
  if not proc then
    vim.notify("No active session", vim.log.levels.WARN)
    return
  end

  local session_id = proc.session_id
  local buf = proc.data.buf

  registry.save_messages(session_id, proc.data.messages)
  registry.delete_session(session_id)

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  local remaining = registry.list_running()
  if #remaining > 0 then
    M.load_session(remaining[1].session_id)
  else
    M.close()
  end

  vim.notify("Session killed", vim.log.levels.INFO)
end

function M.add_file_as_link(file, message)
  local proc = registry.active()
  if not proc then return end

  local abs_path = vim.fn.fnamemodify(file, ":p")
  local mime_type, is_image = get_mime_type(abs_path)
  local content = read_file_content(abs_path, is_image)

  if not content then return end

  local resource = {
    uri = "file://" .. abs_path,
    name = vim.fn.fnamemodify(file, ":t"),
    mimeType = mime_type,
  }
  if is_image then
    resource.blob = content
  else
    resource.text = content
  end

  local prompt = { { type = "resource", resource = resource } }

  if message then
    table.insert(prompt, { type = "text", text = message })
  end

  M.send_prompt(prompt)
end

function M.add_selection_to_prompt()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if not text or text == "" then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    if #lines == 0 then return end

    if #lines == 1 then
      lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
    else
      lines[1] = lines[1]:sub(start_pos[3])
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
    text = table.concat(lines, "\n")
  end

  if not text or text == "" then return end

  local function add_to_prompt()
    local proc = registry.active()
    if not proc or not proc.data.buf then return end

    local current = render.get_prompt_input(proc.data.buf)
    local separator = current ~= "" and "\n" or ""
    render.set_prompt_input(proc.data.buf, current .. separator .. "```\n" .. text .. "\n```\n")

    local win = get_tab_win()
    if not win then
      win = vim.fn.bufwinid(proc.data.buf)
    end
    if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      render.goto_prompt(proc.data.buf, win)
    end
  end

  if not ui.active then
    M.open()
    vim.defer_fn(add_to_prompt, 500)
  else
    add_to_prompt()
  end
end

function M.send_selection()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if not text or text == "" then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    if #lines == 0 then return end

    if #lines == 1 then
      lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
    else
      lines[1] = lines[1]:sub(start_pos[3])
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
    text = table.concat(lines, "\n")
  end

  if not text or text == "" then return end

  if not ui.active then
    M.open()
    vim.defer_fn(function()
      M.send_prompt("```\n" .. text .. "\n```")
    end, 500)
  else
    M.send_prompt("```\n" .. text .. "\n```")
  end
end

local QUICK_ACTIONS = {
  { label = "Explain this code", prompt = "Explain this code concisely:\n```\n%s\n```" },
  { label = "Check for issues", prompt = "Check this code for bugs, issues, or improvements:\n```\n%s\n```" },
  { label = "Add types", prompt = "Add type annotations to this code:\n```\n%s\n```" },
  { label = "Refactor", prompt = "Refactor this code to be cleaner and more maintainable:\n```\n%s\n```" },
  { label = "Write tests", prompt = "Write tests for this code:\n```\n%s\n```" },
  { label = "Add documentation", prompt = "Add documentation/comments to this code:\n```\n%s\n```" },
  { label = "Simplify", prompt = "Simplify this code while maintaining functionality:\n```\n%s\n```" },
  { label = "Optimize", prompt = "Optimize this code for performance:\n```\n%s\n```" },
}

local function get_visual_selection()
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    vim.cmd('normal! "vy')
  end

  local text = vim.fn.getreg("v")
  if text and text ~= "" then
    return text
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])
  if #lines == 0 then return nil end

  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end
  return table.concat(lines, "\n")
end

function M.quick_action(action_index)
  local text = get_visual_selection()
  if not text or text == "" then
    vim.notify("No selection", vim.log.levels.WARN)
    return
  end

  local function execute_action(action)
    local prompt = string.format(action.prompt, text)
    if not ui.active then
      M.open()
      vim.defer_fn(function()
        M.send_prompt(prompt)
      end, 500)
    else
      M.send_prompt(prompt)
    end
  end

  if action_index and QUICK_ACTIONS[action_index] then
    execute_action(QUICK_ACTIONS[action_index])
    return
  end

  local labels = {}
  for _, action in ipairs(QUICK_ACTIONS) do
    table.insert(labels, action.label)
  end

  vim.ui.select(labels, { prompt = "Quick Action:" }, function(choice, idx)
    if not choice or not idx then return end
    execute_action(QUICK_ACTIONS[idx])
  end)
end

function M.explain_selection()
  M.quick_action(1)
end

function M.check_selection()
  M.quick_action(2)
end

function M.get_slash_commands()
  local proc = registry.active()
  return proc and proc.data.slash_commands or {}
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  registry.setup({
    sessions_file = config.sessions_file,
    save_interval = 30000,
    max_sessions_per_project = config.max_sessions_per_project,
  })

  registry.start_autosave()

  vim.api.nvim_create_user_command("AIRepl", function() M.toggle() end, {})
  vim.api.nvim_create_user_command("AIReplOpen", function() M.open() end, {})
  vim.api.nvim_create_user_command("AIReplClose", function() M.close() end, {})
  vim.api.nvim_create_user_command("AIReplNew", function() M.new_session() end, {})
  vim.api.nvim_create_user_command("AIReplSessions", function() M.open_session_picker() end, {})
  vim.api.nvim_create_user_command("AIReplPicker", function() M.pick_process() end, {})

  vim.api.nvim_set_hl(0, "AIReplPrompt", { fg = "#7aa2f7", bold = true })
end

return M
