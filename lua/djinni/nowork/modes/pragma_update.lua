return {
  name = "pragma_update",
  tail_stream = false,
  template_wrap = function(user_prompt) return user_prompt end,
  on_turn_end = function(text, droid, _tool_calls)
    local loc = droid and droid._pragma_loc
    local bufnr = droid and droid._pragma_buf
    if loc and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local update = require("djinni.pragmas.update")
      local clean = update.extract_description(text or "")
      if clean ~= "" then
        update.apply(bufnr, loc, clean)
      end
    end
    return "done"
  end,
}
