local M = {}

M.defaults = {
  session_dir = vim.fn.stdpath("data") .. "/annotations",
  capture_mode = "snippet", -- "location" or "snippet"
  auto_open_panel = true,
  notify = true,
  window = {
    width = 0.3,
  },
  input = {
    width = 50,
    border = "rounded",
  },
  format = {
    header = function(info)
      return {
        "# " .. info.title,
        "",
        "**File:** " .. info.file_path,
        "**Started:** " .. info.timestamp,
        "**Project:** " .. info.cwd,
        "",
        "---",
        "",
      }
    end,
    footer = function(info)
      return {
        "---",
        "",
        "**Ended:** " .. info.timestamp,
      }
    end,
    resumed = function(info)
      return {
        "",
        "---",
        "",
        "**Resumed:** " .. info.timestamp,
        "",
        "---",
        "",
      }
    end,
  },
}

M.config = {}

function M.apply(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})
  return M.config
end

return M
