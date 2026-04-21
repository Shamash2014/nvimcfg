local M = {}

M._select_stack = {}
M._select_open_count = 0

local function get_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok then return nil end
  return snacks
end

local function reopen_previous_select()
  local previous = table.remove(M._select_stack)
  if not previous then return false end
  M.select(previous.items, previous.opts, previous.callback)
  return true
end

function M.select(items, opts, callback)
  opts = opts or {}
  M._select_open_count = M._select_open_count + 1
  local snacks = get_snacks()
  if not snacks or not snacks.picker then
    return vim.ui.select(items, opts, callback)
  end

  local entry = {
    items = vim.deepcopy(items or {}),
    opts = vim.deepcopy(opts),
    callback = callback,
  }

  local picker_items = {}
  for i, item in ipairs(items or {}) do
    local text = opts.format_item and opts.format_item(item) or tostring(item)
    picker_items[#picker_items + 1] = {
      text = text,
      value = item,
      index = i,
    }
  end

  local completed = false
  snacks.picker({
    title = opts.prompt or "Select",
    items = picker_items,
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      if completed then return end
      completed = true
      picker:close()
      vim.schedule(function()
        if callback then
          M._select_stack[#M._select_stack + 1] = entry
          local before = M._select_open_count
          callback(item and item.value, item and item.index)
          if M._select_stack[#M._select_stack] == entry and M._select_open_count == before then
            M._select_stack = {}
          end
        end
      end)
    end,
    on_close = function()
      if completed then return end
      completed = true
      vim.schedule(function()
        if reopen_previous_select() then return end
        if callback then callback(nil, nil) end
      end)
    end,
  })
end

function M.popup(lines, opts)
  opts = opts or {}
  local snacks = get_snacks()
  if not snacks or not snacks.win then
    return nil
  end

  local win_opts = {
    text = lines,
    title = opts.title,
    title_pos = opts.title_pos or "center",
    border = opts.border or "rounded",
    width = opts.width or 0.8,
    height = opts.height or 0.8,
    enter = opts.enter ~= false,
    keys = vim.tbl_extend("force", {
      q = "close",
      ["<Esc>"] = "close",
    }, opts.keys or {}),
    wo = opts.wo or {},
    bo = vim.tbl_extend("force", {
      bufhidden = "wipe",
      modifiable = false,
    }, opts.bo or {}),
    on_buf = opts.on_buf,
    on_win = opts.on_win,
  }

  if opts.filetype then
    win_opts.bo.filetype = opts.filetype
  end

  return snacks.win(win_opts)
end

function M.picker(opts)
  local snacks = get_snacks()
  if not snacks or not snacks.picker then
    vim.notify("[djinni] Snacks.nvim required for this picker", vim.log.levels.WARN)
    return
  end
  snacks.picker(opts)
end

function M.get_picker()
  local snacks = get_snacks()
  if not snacks then return nil end
  return snacks.picker
end

return M
