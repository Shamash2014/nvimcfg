vim.filetype.add({
  extension = {
    md = function(path, bufnr)
      local f = io.open(path, "r")
      if not f then return end
      local first = f:read("*l")
      if first ~= "---" then
        f:close()
        return
      end
      for _ = 2, 15 do
        local line = f:read("*l")
        if not line or line == "---" then break end
        if line:match("^provider:%s*%S") then
          f:close()
          return "nowork-chat"
        end
      end
      f:close()
    end,
  },
})
