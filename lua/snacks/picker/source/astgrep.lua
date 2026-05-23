--- ast-grep finder for snacks.nvim picker
local M = {}

local uv = vim.uv or vim.loop

--- Build ast-grep command from filter/search text
--- @param opts snacks.picker.astgrep.Config
--- @param filter snacks.picker.Filter
local function get_cmd(opts, filter)
  local cmd = "ast-grep"
  local args = {
    "run",
    "--json=stream",
    "--no-heading",
    "--color=never",
    "--ignore=!.git",
    "--ignore=!.bare",
    "--threads=auto",
  }

  -- Pattern
  local pattern, pargs = Snacks.picker.util.parse(filter.search)
  vim.list_extend(args, pargs)

  args[#args + 1] = "-p"
  args[#args + 1] = pattern

  -- Language (auto-detect from filetype or use specified)
  if opts.lang then
    args[#args + 1] = "-l"
    args[#args + 1] = opts.lang
  end

  -- File type filter
  local types = type(opts.ft) == "table" and opts.ft or { opts.ft }
  ---@cast types string[]
  for _, t in ipairs(types) do
    args[#args + 1] = "-t"
    args[#args + 1] = t
  end

  -- Exclude patterns
  for _, e in ipairs(opts.exclude or {}) do
    vim.list_extend(args, { "-g", "!" .. e })
  end

  -- Include patterns
  local glob = type(opts.glob) == "table" and opts.glob or { opts.glob }
  ---@cast glob string[]
  for _, g in ipairs(glob) do
    vim.list_extend(args, { "-g", g })
  end

  -- Search directories
  local paths = {} ---@type string[]
  if opts.buffers then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.bo[buf].buflisted and uv.fs_stat(name) then
        paths[#paths + 1] = name
      end
    end
  end
  vim.list_extend(paths, opts.dirs or {})
  if opts.rtp then
    vim.list_extend(paths, Snacks.picker.util.rtp())
  end

  -- dirs
  if #paths > 0 then
    paths = vim.tbl_map(svim.fs.normalize, paths) ---@type string[]
    vim.list_extend(args, paths)
  end

  -- Additional args
  vim.list_extend(args, opts.args or {})

  return cmd, args
end

--- @param opts snacks.picker.astgrep.Config
--- @type snacks.picker.finder
function M.astgrep(opts, ctx)
  local absolute = (opts.dirs and #opts.dirs > 0) or opts.buffers or opts.rtp
  local cwd = not absolute and svim.fs.normalize(opts and opts.cwd or uv.cwd() or ".") or nil

  local cmd, args = get_cmd(opts, ctx.filter)

  return require("snacks.picker.source.proc").json(
    ctx:opts({
      notify = false,
      cmd = cmd,
      args = args,
      ---@param item snacks.picker.finder.Item
      transform = function(item)
        -- Parse JSON output from ast-grep
        local data = item.item ---@type table
        if not data then
          return false
        end

        -- Extract fields from ast-grep JSON
        local file = data.file or data.path
        local line = data.line or 1
        local col = data.column or 1
        local text = data.text or ""
        local replacement = data.replacement or data.rewrite

        item.file = file
        item.line = line
        item.pos = { line, col - 1 }
        item.end_pos = data.end and { data.end.line, data.end.column - 1 } or item.pos
        item.text = file .. ":" .. line .. ":" .. text
        item.cwd = cwd

        item.resolve = function()
          item.line = text
          item.line_number = line
          item.column = col
          if replacement then
            item.replacement = replacement
          end
        end

        return item
      end,
    }),
    ctx
  )
end

return M
