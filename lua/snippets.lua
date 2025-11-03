local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

ls.config.set_config({
  history = true,
  updateevents = "TextChanged,TextChangedI",
  enable_autosnippets = true,
})

vim.keymap.set({ "i", "s" }, "<C-k>", function()
  if ls.expand_or_jumpable() then
    ls.expand_or_jump()
  end
end, { silent = true, desc = "Expand or jump snippet" })

vim.keymap.set({ "i", "s" }, "<C-j>", function()
  if ls.jumpable(-1) then
    ls.jump(-1)
  end
end, { silent = true, desc = "Jump back in snippet" })

vim.keymap.set("i", "<C-l>", function()
  if ls.choice_active() then
    ls.change_choice(1)
  end
end, { desc = "Change snippet choice" })

require("luasnip.loaders.from_vscode").lazy_load()

ls.add_snippets("all", {
  s("date", f(function() return { os.date("%Y-%m-%d") } end, {})),
  s("todo", fmt("TODO({}): {}", { i(1, "name"), i(2, "todo") })),
  s("fixme", fmt("FIXME({}): {}", { i(1, "name"), i(2, "fixme") })),
})

ls.add_snippets("lua", {
  s("req", fmt('local {} = require("{}")', { i(1, "module"), rep(1) })),
  s("func", fmt([[
    function {}({})
      {}
    end
  ]], { i(1, "name"), i(2, "args"), i(3, "body") })),
})

return ls
