local M = {}

local Popup = {}
Popup.__index = Popup

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "StackPopupKey", { fg = "#DDDDDD", bold = true })
  hl(0, "StackPopupHeader", { fg = "#DDDDDD", bold = true })
  hl(0, "StackPopupDisabled", { fg = "#666666" })
  hl(0, "StackPopupLabel", { fg = "#AAAAAA" })
end

local Builder = {}
Builder.__index = Builder

function Builder.new()
  local self = setmetatable({}, Builder)
  self.state = {
    name = "Popup",
    groups = {},
    current_group = nil,
  }
  return self
end

function Builder:name(n)
  self.state.name = n
  return self
end

function Builder:group_heading(heading)
  local group = {
    heading = heading,
    actions = {},
  }
  table.insert(self.state.groups, group)
  self.state.current_group = group
  return self
end

function Builder:action(key, label, callback, opts)
  opts = opts or {}
  if not self.state.current_group then
    self:group_heading("")
  end

  table.insert(self.state.current_group.actions, {
    key = key,
    label = label,
    callback = callback,
    enabled = opts.enabled ~= false,
  })
  return self
end

function Builder:action_if(cond, key, label, callback, opts)
  if cond then
    return self:action(key, label, callback, opts)
  end
  return self
end

function Builder:spacer()
  if self.state.current_group then
    table.insert(self.state.current_group.actions, { spacer = true })
  end
  return self
end

function Builder:build()
  return Popup.new(self.state)
end

function Popup.new(state)
  local self = setmetatable({}, Popup)
  self.state = state
  self.buf = nil
  self.win = nil
  return self
end

function Popup:render_lines()
  local lines = {}
  local highlights = {}
  local max_width = 40

  for _, group in ipairs(self.state.groups) do
    if group.heading and group.heading ~= "" then
      table.insert(lines, group.heading)
      table.insert(highlights, {
        line = #lines - 1,
        col = 0,
        end_col = #group.heading,
        hl = "StackPopupHeader",
      })
    end

    local row_actions = {}
    for _, action in ipairs(group.actions) do
      if action.spacer then
        if #row_actions > 0 then
          local line, hl = self:render_action_row(row_actions, max_width)
          table.insert(lines, line)
          for _, h in ipairs(hl) do
            h.line = #lines - 1
            table.insert(highlights, h)
          end
          row_actions = {}
        end
      else
        table.insert(row_actions, action)
        if #row_actions == 2 then
          local line, hl = self:render_action_row(row_actions, max_width)
          table.insert(lines, line)
          for _, h in ipairs(hl) do
            h.line = #lines - 1
            table.insert(highlights, h)
          end
          row_actions = {}
        end
      end
    end

    if #row_actions > 0 then
      local line, hl = self:render_action_row(row_actions, max_width)
      table.insert(lines, line)
      for _, h in ipairs(hl) do
        h.line = #lines - 1
        table.insert(highlights, h)
      end
    end

    table.insert(lines, "")
  end

  if lines[#lines] == "" then
    table.remove(lines)
  end

  return lines, highlights
end

function Popup:render_action_row(actions, max_width)
  local col_width = math.floor(max_width / 2)
  local parts = {}
  local highlights = {}

  for i, action in ipairs(actions) do
    local offset = (i - 1) * col_width
    local key_str = " " .. action.key .. " "
    local label_str = action.label

    if action.enabled then
      table.insert(highlights, {
        col = offset + 1,
        end_col = offset + 1 + #action.key,
        hl = "StackPopupKey",
      })
      table.insert(highlights, {
        col = offset + 1 + #action.key + 1,
        end_col = offset + 1 + #action.key + 1 + #label_str,
        hl = "StackPopupLabel",
      })
    else
      table.insert(highlights, {
        col = offset,
        end_col = offset + #key_str + #label_str,
        hl = "StackPopupDisabled",
      })
    end

    local cell = key_str .. label_str
    local padding = col_width - #cell
    if padding > 0 and i < #actions then
      cell = cell .. string.rep(" ", padding)
    end
    table.insert(parts, cell)
  end

  return table.concat(parts, ""), highlights
end

function Popup:mappings()
  local maps = {}

  maps["q"] = function()
    self:close()
  end
  maps["<Esc>"] = function()
    self:close()
  end

  for _, group in ipairs(self.state.groups) do
    for _, action in ipairs(group.actions) do
      if action.key and action.callback and action.enabled then
        maps[action.key] = function()
          self:close()
          vim.schedule(action.callback)
        end
      end
    end
  end

  return maps
end

function Popup:close()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  self.win = nil
  self.buf = nil
end

function Popup:show()
  setup_highlights()

  if M.current and M.current.win and vim.api.nvim_win_is_valid(M.current.win) then
    M.current:close()
  end
  M.current = self

  local lines, highlights = self:render_lines()

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

  vim.bo[self.buf].modifiable = false
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].filetype = "StackPopup"

  local ns = vim.api.nvim_create_namespace("stack_popup")
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(self.buf, ns, hl.hl, hl.line, hl.col, hl.end_col)
  end

  local height = #lines
  vim.cmd("botright " .. height .. "split")
  self.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.win, self.buf)

  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].signcolumn = "no"
  vim.wo[self.win].foldcolumn = "0"
  vim.wo[self.win].cursorline = false
  vim.wo[self.win].winfixheight = true
  vim.wo[self.win].statuscolumn = ""

  local maps = self:mappings()
  for key, fn in pairs(maps) do
    vim.keymap.set("n", key, fn, { buffer = self.buf, nowait = true, silent = true })
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        self:close()
      end)
    end,
  })
end

function M.builder()
  return Builder.new()
end

return M
