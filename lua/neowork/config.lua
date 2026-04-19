local config = require("neowork.config.init")
local schema = require("neowork.config.schema")

local M = {}

local initialized = false

local function ensure_init()
  if initialized then return end
  config.init(schema)
  initialized = true
end

function M.setup(opts)
  ensure_init()
  local ok, errors = config.apply(config.LAYERS.SETUP, opts or {})
  if not ok then
    vim.notify("Neowork config setup failed: " .. table.concat(errors or {}, ", "), vim.log.levels.ERROR)
  end
end

function M.get(key)
  ensure_init()
  local proxy = config.get(0)
  if key then
    return proxy[key]
  end
  return proxy
end

function M.get_neowork_dir(root)
  local dir_name = M.get("neowork_dir")
  return root .. "/" .. dir_name
end

function M.get_transcripts_dir(root)
  return M.get_neowork_dir(root) .. "/transcripts"
end

function M.get_archive_dir(root)
  return M.get_neowork_dir(root) .. "/archive"
end

function M.get_max_turns()
  return M.get("max_visible_turns")
end

function M.get_flush_interval()
  return M.get("flush_interval_ms")
end

return M
