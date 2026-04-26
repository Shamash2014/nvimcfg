local M = {}

local OVERLAY_NS = vim.api.nvim_create_namespace("nowork_compose_chrome")
local SIGIL_OPEN = "▾"
local SIGIL_CLOSED = "▸"

local HL_LINKS = {
  NeoworkIdxTitle = "NeogitSectionHeader",
  NeoworkIdxSection = "NeogitSubtleText",
  NeoworkIdxMuted = "NeogitGraphAuthor",
  NeoworkIdxRule = "NeogitFloatHeader",
  NoworkComposeSigil = "NeogitGraphAuthor",
  NoworkComposeHeading = "NeogitSectionHeader",
}

local function group_exists(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
  if not ok or not hl then return false end
  return next(hl) ~= nil
end

function M.apply_highlights()
  for from, to in pairs(HL_LINKS) do
    if group_exists(to) then
      pcall(vim.api.nvim_set_hl, 0, from, { link = to, default = true })
    end
  end
end

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if type(line) == "string" and line:match("^## ") then
    return ">1"
  end
  return "="
end

function M.statuscol_expr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)
  if type(line) ~= "string" or not line:match("^## ") then
    return " "
  end
  local closed = vim.fn.foldclosed(lnum) ~= -1
  return closed and SIGIL_CLOSED or SIGIL_OPEN
end

local function clear_overlay(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, OVERLAY_NS, 0, -1)
  end
end

function M.apply_section_overlay(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  clear_overlay(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local heading = line:match("^## (.+)$")
    if heading then
      local closed = vim.fn.foldclosed(i) ~= -1
      local sigil = closed and SIGIL_CLOSED or SIGIL_OPEN
      pcall(vim.api.nvim_buf_set_extmark, buf, OVERLAY_NS, i - 1, 0, {
        end_col = 3,
        conceal = "",
        virt_text = { { sigil .. " ", "NoworkComposeSigil" }, { heading, "NoworkComposeHeading" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
      })
    end
  end
end

function M.toggle_section_fold(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.fn.getline(lnum)
  if type(line) == "string" and line:match("^## ") then
    if vim.fn.foldclosed(lnum) == -1 then
      pcall(vim.cmd, "silent! foldclose")
    else
      pcall(vim.cmd, "silent! foldopen")
    end
    M.apply_section_overlay(buf)
    return
  end
  pcall(vim.cmd, "normal! \t")
end

function M.apply_neogit_chrome(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return
  end
  M.apply_highlights()
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = "v:lua.require('djinni.nowork.compose_chrome').foldexpr(v:lnum)"
  vim.wo[win].foldlevel = 99
  vim.wo[win].foldenable = true
  vim.wo[win].foldtext = "v:lua.require('djinni.nowork.compose_chrome').foldtext()"
  vim.wo[win].fillchars = "fold: ,foldopen:" .. SIGIL_OPEN .. ",foldclose:" .. SIGIL_CLOSED
  vim.wo[win].statuscolumn = " %{v:lua.require'djinni.nowork.compose_chrome'.statuscol_expr()} "
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "nvic"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  M.apply_section_overlay(buf)
end

function M.foldtext()
  local first = vim.fn.getline(vim.v.foldstart)
  local heading = first and first:match("^## (.+)$") or first
  local count = vim.v.foldend - vim.v.foldstart
  return string.format("  %s %s  (%d lines)", SIGIL_CLOSED, heading or "", count)
end

return M
