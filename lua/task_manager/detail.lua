local M = {}

local ns_id = vim.api.nvim_create_namespace("TaskManagerDetail")

function M.open(card, opts)
  opts = opts or {}
  local on_save = opts.on_save

  local width = math.min(60, vim.o.columns - 4)
  local height = math.min(20, vim.o.lines - 4)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "task-manager-detail"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. card.title .. " ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = true
  vim.wo[win].wrap = true

  local field_map = {}

  local function render_detail()
    if not vim.api.nvim_buf_is_valid(buf) then return end

    local status_text = ({
      [" "] = "○ Not Started",
      ["~"] = "◐ In Progress",
      ["x"] = "● Done",
    })[card.checkbox] or "○ Not Started"

    local priority_str = card.priority or "none"
    local tags_str = #(card.tags or {}) > 0 and table.concat(card.tags, ", ") or "none"
    local due_str = card.due or "none"
    local created_str = card.created or "unknown"

    local detail_lines = {
      "",
      "  Status:    " .. status_text,
      "  Priority:  " .. priority_str,
      "  Tags:      " .. tags_str,
      "  Due:       " .. due_str,
      "  Created:   " .. created_str,
      "",
      "  ─── Description ───",
    }

    field_map = {
      [2] = "status",
      [3] = "priority",
      [4] = "tags",
      [5] = "due",
    }

    if card.description and card.description ~= "" then
      for _, line in ipairs(vim.split(card.description, "\n")) do
        table.insert(detail_lines, "  " .. line)
        field_map[#detail_lines] = "description"
      end
    else
      table.insert(detail_lines, "  (empty)")
      field_map[#detail_lines] = "description"
    end

    table.insert(detail_lines, "")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, detail_lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    for i, line in ipairs(detail_lines) do
      local colon_pos = line:find(":")
      if line:match("^  %w") and colon_pos then
        vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, 2, {
          end_col = math.min(colon_pos, #line),
          hl_group = "Keyword",
        })
      end
      if line:match("^  ───") then
        vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, 0, {
          end_col = #line,
          hl_group = "FloatBorder",
        })
      end
    end
  end

  render_detail()

  local function edit_field()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    local field = field_map[row]
    if not field then return end

    if field == "status" then
      vim.ui.select({ "Not Started", "In Progress", "Done" }, { prompt = "Status:" }, function(choice)
        if not choice then return end
        if choice == "Not Started" then card.checkbox = " "
        elseif choice == "In Progress" then card.checkbox = "~"
        elseif choice == "Done" then
          card.checkbox = "x"
          card.done = os.date("%Y-%m-%d")
        end
        if on_save then on_save(card) end
        vim.schedule(render_detail)
      end)
    elseif field == "priority" then
      vim.ui.select({ "high", "medium", "low", "none" }, { prompt = "Priority:" }, function(choice)
        if not choice then return end
        card.priority = choice ~= "none" and choice or nil
        if on_save then on_save(card) end
        vim.schedule(render_detail)
      end)
    elseif field == "tags" then
      vim.ui.input({ prompt = "Tags (comma-separated): ", default = table.concat(card.tags or {}, ", ") }, function(val)
        if val then
          card.tags = {}
          for tag in val:gmatch("[^,%s]+") do
            table.insert(card.tags, tag)
          end
          if on_save then on_save(card) end
          vim.schedule(render_detail)
        end
      end)
    elseif field == "due" then
      vim.ui.input({ prompt = "Due (YYYY-MM-DD or +3d/+1w): ", default = card.due or "" }, function(val)
        if val then
          local actions = require("task_manager.actions")
          actions.set_due(card, val)
          if on_save then on_save(card) end
          vim.schedule(render_detail)
        end
      end)
    elseif field == "description" then
      vim.ui.input({ prompt = "Description: ", default = card.description or "" }, function(val)
        if val then
          card.description = val
          if on_save then on_save(card) end
          vim.schedule(render_detail)
        end
      end)
    end
  end

  local bopts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, bopts)
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, bopts)
  vim.keymap.set("n", "e", edit_field, bopts)
  vim.keymap.set("n", "<CR>", edit_field, bopts)
end

return M
