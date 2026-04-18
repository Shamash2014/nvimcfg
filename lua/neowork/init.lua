local M = {}
M._did_setup = M._did_setup or false

function M.setup(opts)
  if M._did_setup then return end
  M._did_setup = true
  require("neowork.config").setup(opts)
  require("neowork.highlight").setup()
  require("neowork.scheduler").setup()
  M._setup_commands()
  M._setup_autocmds()
end

function M._setup_commands()
  vim.api.nvim_create_user_command("Neowork", function(cmd)
    local args = cmd.args or ""
    if args == "" or args == "index" then
      require("neowork.index").open()
    elseif args == "new" then
      vim.ui.input({ prompt = "Session name: " }, function(name)
        local filepath = require("neowork.util").new_session(vim.fn.getcwd(), name)
        if filepath then require("neowork.document").open(filepath, { split = "edit" }) end
      end)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "index", "new" }
    end,
    desc = "Neowork session manager",
  })

  vim.api.nvim_create_user_command("NeoworkNew", function()
    vim.cmd("Neowork new")
  end, { desc = "Create new neowork session" })

  vim.api.nvim_create_user_command("NeoworkIndex", function()
    vim.cmd("Neowork index")
  end, { desc = "Open neowork index" })

  vim.api.nvim_create_user_command("NeoworkIndexToggle", function()
    require("neowork.index").toggle()
  end, { desc = "Toggle neowork index" })

  vim.api.nvim_create_user_command("NeoworkPlanToggle", function()
    require("neowork.plan").toggle(vim.api.nvim_get_current_buf())
  end, { desc = "Toggle neowork plan visibility" })

  vim.api.nvim_create_user_command("NeoworkTranscript", function()
    require("neowork.transcript").open(vim.api.nvim_get_current_buf())
  end, { desc = "Open neowork transcript (doc snapshot)" })

  vim.api.nvim_create_user_command("NeoworkTranscriptFull", function()
    require("neowork.transcript").open_full(vim.api.nvim_get_current_buf())
  end, { desc = "Open neowork full transcript (all events)" })
end

function M._setup_autocmds()
  local group = vim.api.nvim_create_augroup("neowork", { clear = true })

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = group,
    pattern = "*/.neowork/*.md",
    callback = function(ev)
      local buf = ev.buf
      local filepath = vim.api.nvim_buf_get_name(buf)
      local dir = vim.fn.fnamemodify(filepath, ":h")
      if vim.fn.fnamemodify(dir, ":t") ~= ".neowork" then return end
      local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if first_line ~= "---" then return end
      require("neowork.document").attach(buf)
      require("neowork.keymaps").setup_document_keymaps(buf)
      require("neowork.highlight").apply(buf)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
          require("neowork.document").goto_compose(buf)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*/.neowork/*.md",
    callback = function(ev)
      local buf = ev.buf
      if not vim.b[buf].neowork_chat then return end
      require("neowork.summary").render_inline(buf)
      require("neowork.document").ensure_composer(buf)
      local cur_row = vim.api.nvim_win_get_cursor(0)[1]
      if cur_row <= 1 then
        require("neowork.document").goto_compose(buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*/.neowork/*.md",
    callback = function(ev)
      local buf = ev.buf
      if not vim.b[buf].neowork_chat then return end
      require("neowork.keymaps").setup_document_keymaps(buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    pattern = "*/.neowork/*.md",
    callback = function(ev)
      local buf = ev.buf
      if not vim.b[buf].neowork_chat then return end
      local document = require("neowork.document")
      local compose = document.find_compose_line(buf)
      if not compose then
        document.ensure_composer(buf)
        compose = document.find_compose_line(buf)
        if not compose then return end
      end

      local row = vim.api.nvim_win_get_cursor(0)[1]
      if row > compose then
        local lc = vim.api.nvim_buf_line_count(buf)
        local term_row
        for i = compose, lc - 1 do
          local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
          if line == "---" then term_row = i + 1; break end
        end
        if not term_row or row < term_row then return end
      end

      document.goto_compose(buf)
    end,
  })

  local function detach_buf(buf)
    for _, modname in ipairs({ "neowork.bridge", "neowork.stream", "neowork.plan", "neowork.keymaps", "neowork.commands", "neowork.document" }) do
      local mod = package.loaded[modname]
      if mod and type(mod.detach) == "function" then
        pcall(mod.detach, buf)
      end
    end
  end

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      if not vim.b[ev.buf].neowork_chat then return end
      detach_buf(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimLeavePre", "ExitPre" }, {
    group = group,
    callback = function()
      pcall(require("neowork.scheduler").stop)
      local bridge = package.loaded["neowork.bridge"]
      if not bridge then return end
      for buf, _ in pairs(bridge._sessions or {}) do
        pcall(detach_buf, buf)
      end
    end,
  })
end

return M
