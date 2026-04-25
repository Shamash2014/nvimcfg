local M = {}

function M.render_slices(text, log_buf)
  local slices = require("djinni.nowork.parser").extract_log_slices(text)
  for _, s in ipairs(slices) do
    if s.kind == "block" then
      local open_tag
      if s.title and s.title ~= "" then
        open_tag = "<" .. s.tag .. " title=\"" .. s.title .. "\">"
      else
        open_tag = "<" .. s.tag .. ">"
      end
      log_buf:append(open_tag)
      for _, line in ipairs(vim.split(s.body or "", "\n", { plain = true })) do
        log_buf:append(line)
      end
      log_buf:append("</" .. s.tag .. ">")
    else
      log_buf:append(s.tag)
    end
  end
end

return M
