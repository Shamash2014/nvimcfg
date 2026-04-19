local M = {}

function M.setup_folds(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require('djinni.render.fold').foldexpr(v:lnum)"
    vim.wo.foldlevel = 99
  end)
end

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)

  if line:match("^@You") or line:match("^@Djinni") or line:match("^@System") then
    return ">1"
  end

  if line:match("^### Plan") or line:match("^### Agents") or line:match("^### Files") then
    return ">2"
  end

  if line:match("^[├]") then
    return ">3"
  end

  if line:match("^[└]") then
    return "3"
  end

  if line:match("^[│]") then
    return "3"
  end

  if line:match("^%-%-%-$") then
    return "0"
  end

  return "="
end

function M.auto_fold_completed(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local sections = {}
  local current_section = nil

  for i, line in ipairs(lines) do
    if line:match("^[├└]") then
      local is_start = line:match("^[├]")
      if is_start and not current_section then
        current_section = { start = i, has_done = false, is_active = false }
      end
      if line:match("✓") then
        if current_section then current_section.has_done = true end
      end
      if line:match("● running") or line:match("●●●") then
        if current_section then current_section.is_active = true end
      end
      if line:match("^[└]") and current_section then
        current_section.finish = i
        table.insert(sections, current_section)
        current_section = nil
      end
    end
  end

  vim.api.nvim_buf_call(buf, function()
    for _, s in ipairs(sections) do
      if s.has_done and not s.is_active and s.finish then
        M.fold_section(buf, s.start, s.finish)
      end
    end
  end)
end

function M.fold_section(buf, start_line, end_line)
  vim.api.nvim_buf_call(buf, function()
    pcall(vim.cmd, start_line .. "," .. end_line .. "fold")
  end)
end

local debounce_timers = {}

function M.register_autocmds(buf)
  local group = vim.api.nvim_create_augroup("djinni_fold_" .. buf, { clear = true })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    buffer = buf,
    callback = function()
      M.auto_fold_completed(buf)
    end,
  })

  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    buffer = buf,
    callback = function()
      local ok, bridge = pcall(require, "neowork.bridge")
      if ok and bridge and bridge.is_streaming and bridge.is_streaming(buf) then
        return
      end
      if debounce_timers[buf] then
        debounce_timers[buf]:stop()
      end
      debounce_timers[buf] = vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.setup_folds(buf)
          M.auto_fold_completed(buf)
        end
        debounce_timers[buf] = nil
      end, 200)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      if debounce_timers[buf] then
        debounce_timers[buf]:stop()
        debounce_timers[buf] = nil
      end
    end,
  })
end

return M
