local M = {}

M._defaults = {
  neowork_dir = ".neowork",
  max_visible_turns = 2,
  flush_interval_ms = 500,
  auto_scroll = true,
  auto_compact = true,
  auto_save = true,
  max_tool_output_lines = 200,
  schedule_poll_ms = 30000,
  provider = "claude-code",
  model = "",
  index = {
    sort = "status",
    project_scope = "current",
  },
  folds = {
    frontmatter = true,
    thinking = true,
    tool_output = true,
    plan = true,
  },
}

M._opts = {}

function M.setup(opts)
  M._opts = vim.tbl_deep_extend("force", {}, M._defaults, opts or {})
end

function M.get(key)
  if not next(M._opts) then
    M.setup()
  end
  if key then
    return M._opts[key]
  end
  return M._opts
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
