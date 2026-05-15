local M = {}

local function shutdown_agents()
  local ok, at = pcall(require, "core.agent_term")
  if ok and type(at.shutdown_all) == "function" then
    pcall(at.shutdown_all)
  end
end

local function shutdown_jobs()
  local ok, chans = pcall(vim.api.nvim_list_chans)
  if not ok or not chans then return end
  for _, ch in ipairs(chans) do
    if ch.id and ch.argv then
      pcall(vim.fn.jobstop, ch.id)
    end
  end
end

function M.shutdown()
  shutdown_agents()
  shutdown_jobs()
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("nvim3_exit", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = function()
      M.shutdown()
    end,
  })
end

return M
