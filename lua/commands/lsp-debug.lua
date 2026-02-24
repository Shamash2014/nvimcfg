vim.api.nvim_create_user_command("LspDebug", function()
  local active_clients = vim.lsp.get_clients()

  if #active_clients == 0 then
    vim.notify("No active LSP clients", vim.log.levels.INFO)
    return
  end

  local lines = { "Active LSP Clients:", "" }

  for _, client in ipairs(active_clients) do
    local status = "running"
    if type(client.is_stopped) == "function" then
      local ok, stopped = pcall(client.is_stopped)
      if ok and stopped then
        status = "stopped"
      end
    end

    local cmd_str = "unknown"
    if client.config.cmd and type(client.config.cmd) == "table" then
      cmd_str = table.concat(client.config.cmd, " ")
    elseif client.config.cmd and type(client.config.cmd) == "function" then
      cmd_str = "<function>"
    end

    table.insert(lines, string.format("  • %s (id: %d) - %s", client.name, client.id, status))
    table.insert(lines, string.format("    cmd: %s", cmd_str))
    table.insert(lines, string.format("    root: %s", client.config.root_dir or "none"))
    table.insert(lines, "")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local width = 80
  local height = math.min(#lines + 2, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " LSP Debug Info ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
  vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, nowait = true })
end, { desc = "Show LSP debug information" })

vim.api.nvim_create_user_command("LspErrors", function()
  local log_path = vim.lsp.get_log_path()

  vim.cmd("split " .. log_path)

  vim.cmd("normal! G")

  vim.fn.search("ERROR\\|error\\|unhandled", "b")
  vim.cmd("normal! zz")

  vim.notify("Opened LSP log at: " .. log_path, vim.log.levels.INFO)
end, { desc = "Open LSP log and jump to recent errors" })
