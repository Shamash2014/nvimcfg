local M = {}

local _config = {}

function M.setup(opts)
  opts = opts or {}
  -- Register any user-supplied custom providers
  for _, p in ipairs(opts.providers or {}) do
    require("acp.agents").register(p)
  end
  _config = opts
end

-- Work mode
function M.work_set()  require("acp.work").set(vim.fn.getcwd()) end
function M.work_run()  require("acp.work").run(vim.fn.getcwd()) end
function M.work_left() require("acp.work").check_left(vim.fn.getcwd()) end

function M.mailbox() require("acp.mailbox").open() end

function M.cancel(cwd)
  cwd = cwd or vim.fn.getcwd()
  require("acp.session").close(cwd)
  vim.notify("ACP session closed", vim.log.levels.INFO, { title = "acp" })
end

function M.status()
  local active = require("acp.session").active()
  local msg = "ACP: " .. #active .. " session(s)\n"
  for _, s in ipairs(active) do
    msg = msg .. "  " .. s.cwd .. " [" .. s.state .. "]\n"
  end
  vim.notify(msg, vim.log.levels.INFO, { title = "acp" })
end

function M.workbench_toggle()
  require("acp.workbench").toggle()
end

return M
