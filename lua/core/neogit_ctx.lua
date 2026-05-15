local M = {}

function M.collect()
  local ok_status, status_mod = pcall(require, "neogit.buffers.status")
  local ok_git, git = pcall(require, "neogit.lib.git")
  if not ok_status or not ok_git then
    return nil, "Neogit helpers unavailable"
  end

  local status = status_mod.instance()
  if not status or not status.buffer or not status.buffer.ui then
    return nil, "no active Neogit status buffer"
  end

  local ui = status.buffer.ui
  local patches = {}
  local scope = "selected diff"
  local mode = vim.fn.mode()

  if mode:match("^[vV\022]") then
    local selection = ui:get_selection()
    for _, section in ipairs(selection.sections or {}) do
      for _, item in ipairs(section.items or {}) do
        if item.diff and item.diff.hunks then
          local hunks =
            ui:item_hunks(item, selection.first_line, selection.last_line, true)
          for _, hunk in ipairs(hunks) do
            table.insert(
              patches,
              git.index.generate_patch(hunk.hunk, { from = hunk.from, to = hunk.to })
            )
          end
        end
      end
    end
    scope = "selected hunks"
  else
    local selected = ui:get_hunk_or_filename_under_cursor()
    local item = ui:get_item_under_cursor()
    if selected and selected.hunk then
      table.insert(patches, git.index.generate_patch(selected.hunk))
      scope = "current hunk"
    elseif item and item.diff and item.diff.hunks and #item.diff.hunks > 0 then
      for _, hunk in ipairs(item.diff.hunks) do
        table.insert(patches, git.index.generate_patch(hunk))
      end
      scope = "current file diff"
    end
  end

  if #patches == 0 then
    return nil, "no hunk diff under cursor / selection"
  end
  return { patches = patches, scope = scope }
end

function M.review_prompt(ctx)
  return table.concat({
    "Review this " .. ctx.scope .. " for bugs, regressions, and risky changes.",
    "Focus on actionable findings.",
    "",
    "```diff",
    table.concat(ctx.patches, "\n"),
    "```",
  }, "\n")
end

function M.raw_diff(ctx)
  return table.concat(ctx.patches, "\n")
end

return M
