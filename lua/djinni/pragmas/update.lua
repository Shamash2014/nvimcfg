local locator = require("djinni.pragmas.locator")

local M = {}

local MAX_FILE_LINES = 500

local function file_excerpt(bufnr)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(total, MAX_FILE_LINES), false)
  return table.concat(lines, "\n")
end

local function build_prompt(loc, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local pragma_label = "@" .. loc.pragma_kind
  if loc.pragma_name then pragma_label = pragma_label .. ":" .. loc.pragma_name end

  local parts = {
    "You are updating a single pragma description in a source file.",
    "",
    "File: " .. (path ~= "" and path or "(unnamed)"),
    "Filetype: " .. (loc.filetype or "(unknown)"),
    "Pragma: " .. pragma_label,
    "",
    "Current description hint (from the user — may be empty):",
    "{{HINT}}",
    "",
    "Surrounding code (capped at " .. tostring(MAX_FILE_LINES) .. " lines):",
    "```" .. (loc.filetype or ""),
    file_excerpt(bufnr),
    "```",
    "",
    "Write a concise description (1-4 lines, plain text, no markdown, no preamble,",
    "no quotes around it) that accurately summarises what this pragma covers,",
    "using the surrounding code for context. Output ONLY the description text —",
    "no XML tags, no fences, no explanations, no leading/trailing blank lines.",
  }
  return table.concat(parts, "\n")
end

local PREAMBLE_PATTERNS = {
  "^[Hh]ere[%w']*[%s]+",
  "^[Ss]ure[!,.%s]",
  "^[Cc]ertainly[!,.%s]",
  "^[Oo]kay[!,.%s]",
  "^[Oo]f course[!,.%s]",
  "^[Tt]he description[%s]",
  "^[Tt]his pragma[%s]",
  "^[Tt]his feature[%s]",
  "^[Bb]ased on[%s]",
  "^[Ll]et me[%s]",
  "^[Ii]'ll[%s]",
  ":[%s]*$",
}

local function looks_like_preamble(line)
  for _, p in ipairs(PREAMBLE_PATTERNS) do
    if line:match(p) then return true end
  end
  return false
end

function M.extract_description(text)
  if not text or text == "" then return "" end
  local cleaned = text
  cleaned = cleaned:gsub("```[%w]*\n", ""):gsub("\n```", ""):gsub("```", "")
  cleaned = cleaned:gsub("<Description>%s*", ""):gsub("%s*</Description>", "")

  local kept = {}
  for _, line in ipairs(vim.split(cleaned, "\n", { plain = true })) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not looks_like_preamble(trimmed) then
      table.insert(kept, trimmed)
    end
  end
  return table.concat(kept, "\n")
end

function M.apply(bufnr, loc, plain_text)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local lines = {}
  for _, l in ipairs(vim.split(plain_text, "\n", { plain = true })) do
    local trimmed = vim.trim(l)
    if trimmed ~= "" then
      table.insert(lines, loc.indent .. loc.comment_marker .. " " .. trimmed)
    end
  end
  if #lines == 0 then return end

  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  if loc.desc_start and loc.desc_end then
    vim.api.nvim_buf_set_lines(bufnr, loc.desc_start - 1, loc.desc_end, false, lines)
  else
    vim.api.nvim_buf_set_lines(bufnr, loc.pragma_row - 1, loc.pragma_row - 1, false, lines)
  end
  vim.bo[bufnr].modifiable = was_modifiable
end

function M.dispatch(loc, bufnr, prompt)
  local droid_mod = require("djinni.nowork.droid")
  local droid = droid_mod.new("pragma_update", prompt, {
    cwd = vim.fn.getcwd(),
    log_buffer = { hidden_default = true },
  })
  if droid then
    droid._pragma_loc = loc
    droid._pragma_buf = bufnr
  end
  return droid
end

function M.start(bufnr, row)
  bufnr = (bufnr == 0 or bufnr == nil) and vim.api.nvim_get_current_buf() or bufnr
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  local loc = locator.locate(bufnr, row)
  if not loc then
    vim.notify("djinni: no pragma at cursor", vim.log.levels.WARN)
    return
  end
  local prompt_template = build_prompt(loc, bufnr)

  local label = "@" .. loc.pragma_kind
  if loc.pragma_name then label = label .. ":" .. loc.pragma_name end

  require("djinni.nowork.compose").open(nil, {
    alt_buf = bufnr,
    title = " pragma → " .. label .. " ",
    initial = loc.hint_text or "",
    on_submit = function(user_text)
      local hint = user_text or ""
      local full = prompt_template:gsub("{{HINT}}", function() return hint end, 1)
      M.dispatch(loc, bufnr, full)
    end,
  })
end

return M
