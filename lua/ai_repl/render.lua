local M = {}

local tool_utils = require("ai_repl.tool_utils")

local NS = vim.api.nvim_create_namespace("ai_repl_render")
local NS_ANIM = vim.api.nvim_create_namespace("ai_repl_anim")
local NS_DIFF = vim.api.nvim_create_namespace("ai_repl_diff")
local NS_PROMPT = vim.api.nvim_create_namespace("ai_repl_prompt")

local PROMPT_MARKER = "$> "

local buffer_state = {}

-- Diff cache for performance optimization
local diff_cache = {}
local CACHE_SIZE_LIMIT = 100

-- Streaming performance optimization
local streaming_state = {
  pending_updates = {},
  last_update_time = {},
  update_timers = {},
  throttle_ms = 16,  -- ~60fps
  batch_size = 500,  -- Batch characters before forcing update
}

local function schedule_streaming_update(buf, callback)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  -- Clear existing timer for this buffer
  if streaming_state.update_timers[buf] then
    pcall(vim.fn.timer_stop, streaming_state.update_timers[buf])
  end
  
  -- Store callback
  table.insert(streaming_state.pending_updates, callback)
  
  -- Schedule throttled update
  streaming_state.update_timers[buf] = vim.fn.timer_start(streaming_state.throttle_ms, function()
    vim.schedule(function()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
      
      -- Execute all pending updates
      for _, cb in ipairs(streaming_state.pending_updates) do
        cb()
      end
      
      -- Clear pending updates
      streaming_state.pending_updates = {}
      streaming_state.update_timers[buf] = nil
    end)
  end)
end

local function flush_streaming_updates(buf)
  if streaming_state.update_timers[buf] then
    pcall(vim.fn.timer_stop, streaming_state.update_timers[buf])
    streaming_state.update_timers[buf] = nil
  end
  
  for _, cb in ipairs(streaming_state.pending_updates) do
    cb()
  end
  
  streaming_state.pending_updates = {}
end

local function get_cache_key(old_content, new_content)
  if type(old_content) ~= "string" then old_content = "" end
  if type(new_content) ~= "string" then new_content = "" end
  return vim.fn.sha256(old_content .. "|" .. new_content)
end

local function get_cached_diff(cache_key)
  return diff_cache[cache_key]
end

local function cache_diff_result(cache_key, result)
  -- Simple LRU-style cache cleanup
  if vim.tbl_count(diff_cache) >= CACHE_SIZE_LIMIT then
    local keys_to_remove = {}
    local count = 0
    for _ in pairs(diff_cache) do
      count = count + 1
      if count > CACHE_SIZE_LIMIT * 0.8 then
        table.insert(keys_to_remove, _)
      end
    end
    for _, key in ipairs(keys_to_remove) do
      diff_cache[key] = nil
    end
  end

  diff_cache[cache_key] = {
    result = result,
    timestamp = os.time()
  }
end

local SPINNERS = {
  generating = { "|", "/", "-", "\\" },
  thinking = { ".", "..", "..." },
  executing = { "[=  ]", "[ = ]", "[  =]", "[ = ]" },
  compacting = { "◜", "◠", "◝", "◞", "◡", "◟" }
}
local SPIN_TIMING = { generating = 100, thinking = 400, executing = 150, compacting = 120 }

local animation = {
  active = false,
  state = nil,
  timer = nil,
  frame = 1,
  extmark_id = nil,
  idle_timer = nil,
  buf = nil,
}

local function get_state(buf)
  if not buffer_state[buf] then
    buffer_state[buf] = {
      prompt_extmark = nil,
      prompt_line = nil,
    }
  end
  return buffer_state[buf]
end

function M.init_buffer(buf)
  local state = get_state(buf)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = true
  vim.bo[buf].modifiable = true
  vim.b[buf].ai_repl = true

  -- Enable text wrapping to prevent overflow
  vim.bo[buf].textwidth = 100

  -- Set window-local options (need to get the window first)
  vim.api.nvim_buf_call(buf, function()
    vim.wo.wrap = true
    vim.wo.linebreak = true
  end)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

  M.render_prompt(buf)

  local ok, syntax = pcall(require, "ai_repl.syntax")
  if ok then
    syntax.apply_to_buffer(buf)
  end

  return state
end

function M.render_prompt(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local state = get_state(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  state.prompt_line = line_count

  state.prompt_extmark = vim.api.nvim_buf_set_extmark(buf, NS_PROMPT, line_count - 1, 0, {
    id = state.prompt_extmark,
    virt_text = { { PROMPT_MARKER, "AIReplPrompt" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
end

function M.cleanup_buffer(buf)
  buffer_state[buf] = nil
  
  -- Clean up streaming state
  if streaming_state.update_timers[buf] then
    pcall(vim.fn.timer_stop, streaming_state.update_timers[buf])
    streaming_state.update_timers[buf] = nil
  end
  
  for _, ns in ipairs({ NS, NS_ANIM, NS_DIFF, NS_PROMPT }) do
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  end
end

function M.get_prompt_line(buf)
  local state = get_state(buf)
  if state.prompt_extmark then
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, buf, NS_PROMPT, state.prompt_extmark, {})
    if ok and pos and #pos >= 1 then
      return pos[1] + 1
    end
  end
  return state.prompt_line or vim.api.nvim_buf_line_count(buf)
end

function M.append_content(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local to_append = {}
  if type(lines) == "string" then
    for line in lines:gmatch("[^\r\n]*") do
      table.insert(to_append, line)
    end
  elseif type(lines) == "table" then
    for _, l in ipairs(lines) do
      if type(l) == "string" then
        for line in l:gmatch("[^\r\n]*") do
          table.insert(to_append, line)
        end
      end
    end
  end

  if #to_append == 0 then return end

  -- Use fast path for single-line appends (no batching needed)
  if #to_append <= 2 then
    vim.schedule(function()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
      vim.bo[buf].modifiable = true

      local prompt_ln = M.get_prompt_line(buf)
      local insert_at = prompt_ln - 1

      vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, to_append)
      M.render_prompt(buf)
    end)
  else
    -- Batch multi-line appends
    schedule_streaming_update(buf, function()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
      vim.bo[buf].modifiable = true

      local prompt_ln = M.get_prompt_line(buf)
      local insert_at = prompt_ln - 1

      vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, to_append)
      M.render_prompt(buf)
    end)
  end
end

function M.update_streaming(buf, text, process_ui)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  schedule_streaming_update(buf, function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local prompt_ln = M.get_prompt_line(buf)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local user_input = vim.api.nvim_buf_get_lines(buf, prompt_ln - 1, line_count, false)

    local lines = {}
    for line in process_ui.streaming_response:gmatch("[^\r\n]*") do
      table.insert(lines, line)
    end

    if not process_ui.streaming_start_line then
      local prev_line = ""
      if prompt_ln > 1 then
        prev_line = vim.api.nvim_buf_get_lines(buf, prompt_ln - 2, prompt_ln - 1, false)[1] or ""
      end
      if prev_line == "" then
        process_ui.streaming_start_line = prompt_ln - 1
      else
        vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, prompt_ln - 1, false, { "" })
        process_ui.streaming_start_line = prompt_ln
      end
    end

    table.insert(lines, "")
    for _, input_line in ipairs(user_input) do
      table.insert(lines, input_line)
    end

    vim.api.nvim_buf_set_lines(buf, process_ui.streaming_start_line, -1, false, lines)
    M.render_prompt(buf)
  end)
end

function M.finish_streaming(buf, process_ui)
  -- Flush any pending updates immediately
  flush_streaming_updates(buf)
  process_ui.streaming_response = ""
  process_ui.streaming_start_line = nil
end

function M.get_prompt_input(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return "" end
  local prompt_ln = M.get_prompt_line(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, prompt_ln - 1, line_count, false)
  if #lines == 0 then return "" end
  return table.concat(lines, "\n")
end

function M.clear_prompt_input(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local prompt_ln = M.get_prompt_line(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, -1, false, { "" })
  M.render_prompt(buf)
end

function M.set_prompt_input(buf, text)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local prompt_ln = M.get_prompt_line(buf)
  vim.bo[buf].modifiable = true

  local lines = {}
  for line in text:gmatch("[^\r\n]*") do
    table.insert(lines, line)
  end
  if #lines == 0 then lines = { "" } end

  vim.api.nvim_buf_set_lines(buf, prompt_ln - 1, -1, false, lines)
  M.render_prompt(buf)
end

local TOOL_DISPLAY = {
  Read = { icon = "📄", name = "Read" },
  Edit = { icon = "✏️", name = "Edit" },
  Write = { icon = "📝", name = "Write" },
  Bash = { icon = "⚡", name = "Run" },
  Glob = { icon = "🔍", name = "Find" },
  Grep = { icon = "🔎", name = "Search" },
  Task = { icon = "🤖", name = "Agent" },
  WebFetch = { icon = "🌐", name = "Fetch" },
  WebSearch = { icon = "🔍", name = "Search Web" },
  TodoWrite = { icon = "📋", name = "Plan" },
  LSP = { icon = "💡", name = "LSP" },
  NotebookEdit = { icon = "📓", name = "Notebook" },
  ExitPlanMode = { icon = "▶️", name = "Execute" },
  EnterPlanMode = { icon = "📝", name = "Plan Mode" },
  AskUser = { icon = "❓", name = "Question" },
  AskUserQuestion = { icon = "❓", name = "Question" },
}

local function get_tool_description(tool)
  local input = tool.rawInput or {}
  local title = tool.title or ""
  return tool_utils.get_tool_description(title, input, tool.locations, { path_format = ":t", max_cmd_len = 50 })
end

function M.render_tool(buf, tool)
  if tool.status == "pending" or tool.status == "in_progress" then
    return
  end

  local status = tool_utils.STATUS_ICONS[tool.status] or "○"
  local title = tool.title or tool.kind or "tool"
  local display = TOOL_DISPLAY[title] or { icon = "•", name = title }
  local desc = get_tool_description(tool)

  local line = status .. " " .. display.name
  if desc ~= "" then
    line = line .. ": " .. desc
  end

  M.append_content(buf, { line })
end

function M.render_plan(buf, plan)
  if #plan == 0 then return end
  
  -- Detect if this is a spec mode plan (has structured metadata)
  local is_spec_mode = false
  local has_metadata = false
  local plan_title = "Plan"
  local plan_description = nil
  
  -- Check for spec mode metadata
  for _, item in ipairs(plan) do
    if type(item) == "table" then
      if item.isSpecMode or item.spec_mode then
        is_spec_mode = true
      end
      if item.title or item.name then
        plan_title = item.title or item.name
        has_metadata = true
      end
      if item.description then
        plan_description = item.description
      end
    end
  end
  
  local lines = { "" }
  
  -- Add header with appropriate icon
  local header_icon = is_spec_mode and "📝" or "📋"
  table.insert(lines, "━━━ " .. header_icon .. " " .. plan_title .. " ━━━")
  
  -- Add description if available
  if plan_description then
    table.insert(lines, " " .. plan_description)
    table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━")
  end
  
  for i, item in ipairs(plan) do
    local icon = tool_utils.STATUS_ICONS[item.status] or "○"
    local pri = item.priority == "high" and "! " or ""
    local text = item.content or item.text or item.activeForm or item.description or tostring(item)
    
    -- Add special formatting for spec mode items
    local prefix = ""
    if is_spec_mode then
      if item.type == "requirement" then
        prefix = "📌 "
      elseif item.type == "task" then
        prefix = "✓ "
      elseif item.type == "testing" then
        prefix = "🧪 "
      elseif item.type == "phase" then
        prefix = "➤ "
      end
    end
    
    table.insert(lines, string.format(" %s %d.%s%s%s", icon, i, prefix, pri, text))
  end
  table.insert(lines, "━━━━━━━━━━━━")
  table.insert(lines, "")
  M.append_content(buf, lines)
end

function M.parse_markdown_plan(text)
  local plan = {}
  local in_spec_section = false
  local spec_mode_keywords = {
    ["specification"] = true,
    ["acceptance criteria"] = true,
    ["implementation plan"] = true,
    ["technical details"] = true,
    ["requirements"] = true,
    ["testing strategy"] = true,
  }
  
  for line in text:gmatch("[^\r\n]+") do
    local lower_line = line:lower()
    
    -- Detect spec mode sections
    for keyword, _ in pairs(spec_mode_keywords) do
      if lower_line:match("^%s*##?%s*" .. keyword) or lower_line:match("^%s*" .. keyword .. ":") then
        in_spec_section = true
        table.insert(plan, { 
          content = line:gsub("^%s*##?%s*", ""), 
          status = "pending",
          type = "section"
        })
        break
      end
    end
    
    -- Parse checkbox items
    local checkbox, content = line:match("^%s*[%-*]%s*%[([%sx ])%]%s*(.+)")
    if checkbox and content then
      local status = "pending"
      if checkbox == "x" or checkbox == "X" then
        status = "completed"
      end
      local item_type = in_spec_section and "task" or nil
      table.insert(plan, { 
        content = content, 
        status = status,
        type = item_type
      })
    else
      -- Parse numbered items
      local num, content2 = line:match("^%s*(%d+)[%.%)%s]+(.+)")
      if num and content2 and not content2:match("^%s*$") then
        local clean = content2:gsub("^%*%*(.-)%*%*", "%1"):gsub("^__(.-)__", "%1")
        if #clean > 0 and #clean < 200 then
          local item_type = in_spec_section and "task" or nil
          table.insert(plan, { 
            content = clean, 
            status = "pending",
            type = item_type
          })
        end
      end
    end
  end
  
  -- Mark as spec mode if we detected spec sections
  if #plan > 0 and in_spec_section then
    plan.isSpecMode = true
  end
  
  return plan
end

function M.render_diff(buf, file_path, old_content, new_content)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  -- Skip if contents are identical
  if old_content == new_content then
    return
  end

  -- Check cache first
  local cache_key = get_cache_key(old_content, new_content)
  local cached_result = get_cached_diff(cache_key)
  local diff_data, stats
  
  local function compute_enhanced_diff(old_text, new_text)
    if type(old_text) ~= "string" then old_text = "" end
    if type(new_text) ~= "string" then new_text = "" end
    local old_lines = vim.split(old_text, "\n", { plain = true })
    local new_lines = vim.split(new_text, "\n", { plain = true })
    local result = {}
    local hunks = vim.diff(old_text or "", new_text or "", { result_type = "indices" })
    
    local old_idx = 1
    local new_idx = 1
    local hunk_num = 0
    local total_additions = 0
    local total_deletions = 0

    for _, hunk in ipairs(hunks or {}) do
      local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]
      hunk_num = hunk_num + 1
      
      -- Add unchanged context lines before hunk
      while old_idx < old_start do
        table.insert(result, { 
          text = string.format(" %s%d  %s", " ", old_idx, old_lines[old_idx] or ""),
          old_line = old_idx,
          new_line = new_idx,
          type = "context"
        })
        old_idx = old_idx + 1
        new_idx = new_idx + 1
      end
      
      -- Add hunk header with Git-style @@ notation
      local context_start = math.max(1, old_start - 3)
      local context_count = (old_start - context_start) + math.max(old_count, new_count) + 3
      local hunk_header = string.format("@@ -%d,%d +%d,%d @@", 
        old_start, old_count, new_start, new_count)
      table.insert(result, {
        text = hunk_header,
        type = "hunk_header",
        hunk_num = hunk_num,
        old_start = old_start,
        new_start = new_start
      })
      
      -- Process deleted lines
      for i = old_start, old_start + old_count - 1 do
        if old_lines[i] then
          local line_text = old_lines[i]
          local word_diffs = M.compute_word_diff(line_text, "")
          table.insert(result, {
            text = string.format("-%s%d  %s", " ", i, line_text),
            old_line = i,
            new_line = nil,
            type = "delete",
            word_diffs = word_diffs
          })
          total_deletions = total_deletions + 1
        end
      end
      
      old_idx = old_start + old_count
      new_idx = new_start
      
      -- Process added lines
      for i = new_start, new_start + new_count - 1 do
        if new_lines[i] then
          local line_text = new_lines[i]
          local word_diffs = M.compute_word_diff("", line_text)
          table.insert(result, {
            text = string.format("+%s%d  %s", " ", i, line_text),
            old_line = nil,
            new_line = i,
            type = "add",
            word_diffs = word_diffs
          })
          total_additions = total_additions + 1
          new_idx = new_idx + 1
        end
      end
    end
    
    -- Add remaining unchanged lines
    while old_idx <= #old_lines do
      table.insert(result, { 
        text = string.format(" %s%d  %s", " ", old_idx, old_lines[old_idx] or ""),
        old_line = old_idx,
        new_line = new_idx,
        type = "context"
      })
      old_idx = old_idx + 1
      new_idx = new_idx + 1
    end
    
    return result, {
      additions = total_additions,
      deletions = total_deletions,
      hunks = hunk_num
    }
  end

  local function compute_word_diff(old_line, new_line)
    if old_line == "" and new_line ~= "" then
      return { type = "full_add", text = new_line }
    elseif old_line ~= "" and new_line == "" then
      return { type = "full_delete", text = old_line }
    elseif old_line ~= new_line then
      -- Enhanced word-level diff using character-based diff
      local char_diff = vim.diff(old_line, new_line, { 
        result_type = "indices",
        algorithm = "minimal"
      })
      
      local segments = {}
      local old_pos = 1
      local new_pos = 1
      
      for _, hunk in ipairs(char_diff or {}) do
        local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]
        
        -- Add unchanged prefix
        if old_pos < old_start then
          local unchanged = old_line:sub(old_pos, old_start - 1)
          table.insert(segments, { 
            text = unchanged, 
            type = "unchanged",
            old_start = old_pos,
            old_end = old_start - 1,
            new_start = new_pos,
            new_end = new_pos + (old_start - old_pos) - 1
          })
          new_pos = new_pos + (old_start - old_pos)
        end
        
        -- Add deleted part
        if old_count > 0 then
          local deleted = old_line:sub(old_start, old_start + old_count - 1)
          table.insert(segments, { 
            text = deleted, 
            type = "delete",
            old_start = old_start,
            old_end = old_start + old_count - 1
          })
        end
        
        -- Add added part
        if new_count > 0 then
          local added = new_line:sub(new_start, new_start + new_count - 1)
          table.insert(segments, { 
            text = added, 
            type = "add",
            new_start = new_start,
            new_end = new_start + new_count - 1
          })
          new_pos = new_start + new_count
        end
        
        old_pos = old_start + old_count
      end
      
      -- Add trailing unchanged part
      if old_pos <= #old_line then
        local unchanged = old_line:sub(old_pos)
        table.insert(segments, { 
          text = unchanged, 
          type = "unchanged",
          old_start = old_pos,
          old_end = #old_line
        })
      end
      
      return { type = "mixed", segments = segments }
    end
    return nil
  end

  -- Add word diff computation method
  M.compute_word_diff = compute_word_diff

  local diff_data, stats = compute_enhanced_diff(old_content, new_content)
  
  -- Cache the result if not from cache
  if not cached_result then
    cache_diff_result(cache_key, { diff_data = diff_data, stats = stats })
  end
  
  -- Build header with file info and stats
  local filename = vim.fn.fnamemodify(file_path, ":t")
  local stats_text = string.format("+%d -%d", stats.additions, stats.deletions)
  local header = string.format("--- %s (%s) ---", filename, stats_text)
  
  local lines = { "", header }
  for _, d in ipairs(diff_data) do
    table.insert(lines, d.text)
  end
  table.insert(lines, "---")
  table.insert(lines, "")

  local function apply_syntax_highlighting(buf, line_num, content_line, file_path)
    -- Fast path: skip syntax highlighting for very large diffs or unknown filetypes
    if #content_line > 500 then
      return
    end
    
    -- Try to determine filetype from path
    local filetype = vim.filetype.match({ filename = file_path }) or "text"
    
    -- Skip expensive parsing for certain filetypes
    local skip_syntax = {
      ["text"] = true,
      ["log"] = true,
      ["markdown"] = true,
    }
    if skip_syntax[filetype] then
      return
    end
    
    -- Create temporary buffer for syntax highlighting
    local temp_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, { content_line })
    vim.bo[temp_buf].filetype = filetype
    -- Disable folds on temporary buffer to prevent treesitter errors
    vim.bo[temp_buf].foldmethod = "manual"
    vim.bo[temp_buf].foldenable = false
    
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(temp_buf) then return end
      
      -- Try to start treesitter parsing
      local ok, parser = pcall(vim.treesitter.get_parser, temp_buf, filetype)
      if ok and parser then
        -- Safely parse with error handling
        local parse_ok = pcall(function()
          parser:parse()
        end)
        
        if parse_ok then
          -- Get syntax highlights and apply them to diff buffer
          local highlights = {}
          local trees = parser:trees()
          if trees and trees[1] then
            local root = trees[1]:root()
            if root then
              for node in root:iter_children() do
                if node and node:type() then
                  local start_row, start_col, _, end_col = node:range()
                  if start_row == 0 then
                    table.insert(highlights, {
                      start_col = start_col,
                      end_col = end_col,
                      hl_group = "@" .. node:type()
                    })
                  end
                end
              end
            end
          end
          
          -- Apply highlights to diff buffer with diff background
          for _, hl in ipairs(highlights) do
            local content_start = content_line:find("%s%s")
            if content_start then
              content_start = content_start + 1
              pcall(vim.api.nvim_buf_set_extmark, buf, NS_DIFF, line_num, 
                content_start + hl.start_col, {
                  end_col = content_start + hl.end_col,
                  hl_group = hl.hl_group,
                  virt_text = { { "", "AIReplDiffContext" } },
                  virt_text_pos = "overlay"
                })
            end
          end
        end
      end
      
      -- Clean up temporary buffer
      if vim.api.nvim_buf_is_valid(temp_buf) then
        pcall(vim.api.nvim_buf_delete, temp_buf, { force = true })
      end
    end)
  end

  local function set_diff_extmark(b, line, col, end_col, hl_group)
    pcall(vim.api.nvim_buf_set_extmark, b, NS_DIFF, line, col, {
      end_col = end_col,
      hl_group = hl_group
    })
  end

  local function apply_word_diff_highlights(b, line_num, d, seg_type, full_type, word_hl, pos_key)
    if not d.word_diffs then return end
    local match_pos = d.text:find("%s%s")
    if not match_pos then return end
    local content_start = match_pos + 1
    if d.word_diffs.type == full_type then
      set_diff_extmark(b, line_num, content_start, #d.text, word_hl)
    elseif d.word_diffs.type == "mixed" and d.word_diffs.segments then
      for _, segment in ipairs(d.word_diffs.segments) do
        if segment.type == seg_type then
          local s_start = segment[pos_key .. "_start"]
          local s_end = segment[pos_key .. "_end"]
          set_diff_extmark(b, line_num, content_start + s_start - 1, content_start + s_end, word_hl)
        end
      end
    end
  end

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local prompt_ln = M.get_prompt_line(buf)
    local insert_at = prompt_ln - 1

    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, lines)

    local diff_start = insert_at + 2
    
    -- Lazy render highlights to avoid blocking UI
    local function render_highlights_batch(start_idx, batch_size)
      local end_idx = math.min(start_idx + batch_size - 1, #diff_data)
      
      for i = start_idx, end_idx do
        local d = diff_data[i]
        local line_num = diff_start + i - 1

        if d.type == "hunk_header" then
          set_diff_extmark(buf, line_num, 0, #d.text, "AIReplDiffHunk")
        elseif d.type == "add" then
          set_diff_extmark(buf, line_num, 0, #d.text, "AIReplDiffAdd")
          apply_word_diff_highlights(buf, line_num, d, "add", "full_add", "AIReplDiffAddWord", "new")
        elseif d.type == "delete" then
          set_diff_extmark(buf, line_num, 0, #d.text, "AIReplDiffDelete")
          apply_word_diff_highlights(buf, line_num, d, "delete", "full_delete", "AIReplDiffDeleteWord", "old")
        elseif d.type == "context" then
          local match_pos = d.text:find("%s%d+%s")
          if match_pos then
            local content_start = match_pos + 2
            set_diff_extmark(buf, line_num, 0, content_start, "AIReplDiffContext")
            local content = d.text:sub(content_start)
            apply_syntax_highlighting(buf, line_num, content, file_path)
          end
        end
      end
      
      -- Continue with next batch if there's more
      if end_idx < #diff_data then
        vim.defer_fn(function()
          if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
          render_highlights_batch(end_idx + 1, batch_size)
        end, 0)
      end
    end
    
    -- Start batch rendering (50 lines at a time to avoid blocking)
    render_highlights_batch(1, 50)

    set_diff_extmark(buf, diff_start - 1, 0, #header, "AIReplDiffHeader")

    -- Store hunk locations for navigation
    local hunk_positions = {}
    for i, d in ipairs(diff_data) do
      if d.type == "hunk_header" then
        table.insert(hunk_positions, diff_start + i - 1)
      end
    end

    if #hunk_positions > 0 then
      local opts = { buffer = buf, silent = true, nowait = true }
      local nav_bindings = {
        { key = '[h', direction = 'prev', offset = 0 },
        { key = ']h', direction = 'next', offset = 0 },
        { key = '[c', direction = 'prev', offset = 1 },
        { key = ']c', direction = 'next', offset = 1 },
      }
      for _, binding in ipairs(nav_bindings) do
        vim.keymap.set('n', binding.key, function()
          local current_line = vim.api.nvim_win_get_cursor(0)[1]
          if binding.direction == 'prev' then
            for j = #hunk_positions, 1, -1 do
              if hunk_positions[j] < current_line then
                vim.api.nvim_win_set_cursor(0, { hunk_positions[j] + binding.offset, 0 })
                break
              end
            end
          else
            for _, pos in ipairs(hunk_positions) do
              if pos > current_line then
                vim.api.nvim_win_set_cursor(0, { pos + binding.offset, 0 })
                break
              end
            end
          end
        end, opts)
      end
    end
  end)
end

function M.render_history(buf, messages)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not messages or #messages == 0 then return end

  vim.schedule(function()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true

    local lines = {}
    for _, msg in ipairs(messages) do
      if msg.role == "user" then
        table.insert(lines, "> " .. msg.content)
        table.insert(lines, "")
      else
        if msg.tool_calls and #msg.tool_calls > 0 then
          for _, tc in ipairs(msg.tool_calls) do
            local status_icon = tc.status == "completed" and "[+]" or (tc.status == "failed" and "[!]" or "[?]")
            local title = tc.title or tc.kind or "tool"
            table.insert(lines, status_icon .. " " .. title)
          end
          table.insert(lines, "")
        end
        if msg.content and msg.content ~= "" then
          for line in msg.content:gmatch("[^\n]+") do
            table.insert(lines, line)
          end
        end
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
      end
    end

    local prompt_ln = M.get_prompt_line(buf)
    vim.api.nvim_buf_set_lines(buf, 0, prompt_ln - 1, false, lines)
  end)
end

local function stop_animation()
  animation.active = false
  animation.state = nil
  if animation.timer then
    pcall(vim.fn.timer_stop, animation.timer)
    animation.timer = nil
  end
  if animation.idle_timer then
    pcall(vim.fn.timer_stop, animation.idle_timer)
    animation.idle_timer = nil
  end
  if animation.extmark_id and animation.buf and vim.api.nvim_buf_is_valid(animation.buf) then
    pcall(vim.api.nvim_buf_del_extmark, animation.buf, NS_ANIM, animation.extmark_id)
    animation.extmark_id = nil
  end
end

local function render_anim_frame()
  if not animation.active or not animation.state then return end
  if not animation.buf or not vim.api.nvim_buf_is_valid(animation.buf) then
    stop_animation()
    return
  end

  local chars = SPINNERS[animation.state] or SPINNERS.generating
  local char = chars[animation.frame] or chars[1]
  animation.frame = (animation.frame % #chars) + 1

  local prompt_ln = M.get_prompt_line(animation.buf)
  local display = " " .. char .. " " .. animation.state .. " "

  animation.extmark_id = vim.api.nvim_buf_set_extmark(animation.buf, NS_ANIM, math.max(0, prompt_ln - 2), 0, {
    id = animation.extmark_id,
    virt_lines = { { { display, "Comment" } } },
    virt_lines_above = false
  })

  local delay = SPIN_TIMING[animation.state] or 100
  animation.timer = vim.fn.timer_start(delay, function()
    vim.schedule(render_anim_frame)
  end)
end

local function reset_idle_timer()
  if animation.idle_timer then
    pcall(vim.fn.timer_stop, animation.idle_timer)
  end
  animation.idle_timer = vim.fn.timer_start(1500, function()
    vim.schedule(stop_animation)
  end)
end

function M.start_animation(buf, anim_state)
  if animation.active and animation.state == anim_state and animation.buf == buf then
    reset_idle_timer()
    return
  end
  stop_animation()
  animation.active = true
  animation.state = anim_state
  animation.buf = buf
  reset_idle_timer()
  animation.frame = 1
  vim.schedule(render_anim_frame)
end

function M.stop_animation()
  stop_animation()
end

function M.setup_cursor_lock(buf)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = buf,
    callback = function()
      local prompt_ln = M.get_prompt_line(buf)
      local win = vim.fn.bufwinid(buf)
      if win == -1 then return end
      local cursor = vim.api.nvim_win_get_cursor(win)
      local row = cursor[1]
      if row < prompt_ln then
        vim.bo[buf].modifiable = false
      else
        vim.bo[buf].modifiable = true
      end
    end
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      local line_count = vim.api.nvim_buf_line_count(buf)
      local state = get_state(buf)
      if line_count == 0 or (state.prompt_extmark and not pcall(vim.api.nvim_buf_get_extmark_by_id, buf, NS_PROMPT, state.prompt_extmark, {})) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M.render_prompt(buf)
          end
        end)
      end
    end
  })

  vim.keymap.set({ "n", "i" }, "<BS>", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row, col = cursor[1], cursor[2]
    if row == prompt_ln and col == 0 then
      return
    end
    local mode = vim.fn.mode()
    if mode == "i" then
      return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", false)
    else
      return vim.api.nvim_feedkeys("X", "n", false)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "dd", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    local line_count = vim.api.nvim_buf_line_count(buf)
    if row == prompt_ln and line_count == prompt_ln then
      return
    end
    if row >= prompt_ln then
      return vim.api.nvim_feedkeys("dd", "n", false)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "x", function()
    local prompt_ln = M.get_prompt_line(buf)
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    if row >= prompt_ln then
      return vim.api.nvim_feedkeys("x", "n", false)
    end
  end, { buffer = buf, silent = true })
end

function M.goto_prompt(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local prompt_ln = M.get_prompt_line(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local prompt_line = math.min(prompt_ln, line_count)
  local line = vim.api.nvim_buf_get_lines(buf, prompt_line - 1, prompt_line, false)[1] or ""

  vim.bo[buf].modifiable = true
  vim.api.nvim_win_set_cursor(win, { prompt_line, #line })
  vim.cmd("startinsert!")
end

return M
