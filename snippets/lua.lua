local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Function snippet
  s("fn", fmt([[
local function {}({})
  {}
end
]], { i(1, "name"), i(2, "args"), i(3, "-- body") })),

  -- If statement
  s("if", fmt([[
if {} then
  {}
end
]], { i(1, "condition"), i(2, "-- body") })),

  -- For loop
  s("for", fmt([[
for {} = {}, {} do
  {}
end
]], { i(1, "i"), i(2, "1"), i(3, "10"), i(4, "-- body") })),

  -- While loop
  s("while", fmt([[
while {} do
  {}
end
]], { i(1, "condition"), i(2, "-- body") })),

  -- Require statement
  s("req", fmt("local {} = require('{}')", { i(1, "module"), i(2, "module") })),

  -- Table
  s("tbl", fmt([[
local {} = {{
  {}
}}
]], { i(1, "table"), i(2, "-- content") })),

  -- Print with variable
  s("pr", fmt("print('{}: ', {})", { i(1, "debug"), i(2, "variable") })),

  -- Vim keymap
  s("map", fmt("vim.keymap.set('{}', '{}', {}, {{ desc = '{}' }})", 
    { c(1, { t("n"), t("i"), t("v"), t("x") }), i(2, "<leader>"), i(3, "function"), i(4, "description") })),

  -- Vim autocmd
  s("autocmd", fmt([[
vim.api.nvim_create_autocmd('{}', {{
  pattern = '{}',
  callback = function()
    {}
  end,
}})
]], { i(1, "event"), i(2, "*"), i(3, "-- callback") })),
}