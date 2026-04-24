local M = {}

local function touched_lines(droid)
  local bag = droid.state and droid.state.touched
  local out = {}
  if bag and bag.items then
    for _, it in ipairs(bag.items) do
      out[#out + 1] = string.format("  %s:%d  %s",
        it.filename or "?", it.lnum or 0, it.text or "")
    end
  end
  if #out == 0 then
    out[1] = "  (none yet)"
  end
  return out
end

function M.open(droid, opts)
  opts = opts or {}
  local cwd = droid.opts and droid.opts.cwd or vim.fn.getcwd()
  local diff = vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " diff --stat") or ""
  if diff == "" then diff = "(no diff)" end
  local lines = { "# git diff --stat", diff, "", "# touched files:" }
  for _, l in ipairs(touched_lines(droid)) do lines[#lines + 1] = l end

  local droid_mod = require("djinni.nowork.droid")
  local title = " routine review — <C-s> continue · <C-r> correction · <C-c> close "
  local footer = " <C-s> looks good, continue · <C-r> compose correction · <C-c> close "
  local on_submit = function()
    droid_mod.stage_append(droid, "User reviewed changes; continue.")
    return true
  end
  local extra_keys = {
    ["<C-r>"] = function(close)
      close()
      require("djinni.nowork.compose").open_routine_chat(droid)
    end,
  }
  if opts.readonly then
    title = " routine diff — <C-c> close "
    footer = " <C-c> close "
    on_submit = function() return true end
    extra_keys = {}
  end

  require("djinni.nowork.plan_buffer").open({
    title = title,
    footer = footer,
    content = table.concat(lines, "\n"),
    filetype = "diff",
    readonly = true,
    on_submit = on_submit,
    extra_keys = extra_keys,
  })
end

return M
