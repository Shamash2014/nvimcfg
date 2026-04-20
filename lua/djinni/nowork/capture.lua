local M = {}

function M.route(snippet)
  local picker = require("djinni.nowork.picker")
  local compose = require("djinni.nowork.compose")
  local droid_mod = require("djinni.nowork.droid")
  local alt_buf = vim.fn.bufnr("#")

  local function launch_new()
    compose.open(nil, {
      alt_buf = alt_buf,
      title = " compose → new routine droid ",
      initial = snippet,
      on_submit = function(text) require("djinni.nowork").routine(text, {}) end,
    })
  end

  if picker.count({ mode_filter = { "routine", "autorun" } }) == 0 then
    launch_new()
    return
  end

  picker.pick({
    mode_filter = { "routine", "autorun" },
    on_droid = function(d)
      compose.open(d, {
        alt_buf = alt_buf,
        title = " append → " .. d.id .. " ",
        initial = snippet,
        on_submit = function(text) droid_mod.stage_append(d, text) end,
      })
    end,
  })
end

return M
