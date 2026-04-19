local M = {}

local TITLE = "CI Watch"

function M.view(run_id, opts)
  opts = opts or {}
  if not run_id or run_id == "" then
    vim.notify("CI logs: no run id", vim.log.levels.ERROR, { title = TITLE })
    return
  end
  local github = require("core.ci_watch.github")
  vim.notify("Fetching logs for run " .. tostring(run_id) .. "…", vim.log.levels.INFO, { title = TITLE })
  github.fetch_run_log(run_id, { failed_only = opts.failed_only ~= false }, function(out, err)
    if err or not out then
      vim.notify("CI logs: " .. (err or "no output"), vim.log.levels.ERROR, { title = TITLE })
      return
    end
    local lines = vim.split(out, "\n", { plain = true })
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      vim.notify("CI logs: empty output for run " .. tostring(run_id), vim.log.levels.WARN, { title = TITLE })
      return
    end
    vim.cmd("botright 20split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "log"
    vim.api.nvim_buf_set_name(buf, string.format("ci-log://%s", tostring(run_id)))
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = buf, silent = true, desc = "Close CI logs" })
  end)
end

return M
