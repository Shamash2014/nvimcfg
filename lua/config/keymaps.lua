local map = vim.keymap.set

local function snacks()
  return require("snacks")
end

local function resession()
  return require("resession")
end

local function wt()
  return require("config.wt")
end

local function profile()
  return require("config.profile")
end

local function restart_nvim()
  local session = vim.fs.joinpath(vim.fn.stdpath("state"), "restart_session.vim")
  vim.cmd("mksession! " .. vim.fn.fnameescape(session))
  vim.fn.jobstart({ vim.v.progpath, "-S", session }, { detach = true })
  vim.cmd("qa!")
end

vim.api.nvim_create_user_command("Wt", function(opts)
  local args = opts.fargs
  local subcommand = args[1]
  if not subcommand or subcommand == "list" then
    wt().open_picker()
    return
  end

  if subcommand == "switch" then
    if args[2] then
      wt().switch_to(args[2], {}, function(ok, msg)
        if not ok then
          vim.notify(msg or "wt switch failed", vim.log.levels.ERROR, { title = "worktrunk" })
        end
      end)
    else
      wt().prompt_switch()
    end
    return
  end

  if subcommand == "create" then
    if args[2] then
      local base = args[3] or "@"
      wt().create(args[2], { base = base }, function(ok, msg)
        if not ok then
          vim.notify(msg or "wt create failed", vim.log.levels.ERROR, { title = "worktrunk" })
        end
      end)
    else
      wt().prompt_create()
    end
    return
  end

  if subcommand == "remove" then
    if args[2] then
      wt().remove(args[2], { yes = true }, function(ok, msg)
        if not ok then
          vim.notify(msg or "wt remove failed", vim.log.levels.ERROR, { title = "worktrunk" })
        end
      end)
    else
      wt().prompt_remove()
    end
    return
  end

  if subcommand == "merge" then
    local target = args[2]
    if target then
      wt().merge({ target = target, yes = true }, function(ok, msg)
        if not ok then
          vim.notify(msg or "wt merge failed", vim.log.levels.ERROR, { title = "worktrunk" })
        end
      end)
    else
      wt().prompt_merge()
    end
    return
  end

  local cmd = vim.list_extend({ "wt" }, args)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr ~= "" and result.stderr or result.stdout)
        if message == "" then
          message = "wt exited with code " .. result.code
        end
        vim.notify(message, vim.log.levels.ERROR, { title = "worktrunk" })
        return
      end

      local output = vim.trim(result.stdout)
      if output ~= "" then
        vim.notify(output, vim.log.levels.INFO, { title = "worktrunk" })
      end
    end)
  end)
end, { nargs = "*" })

local function input(prompt)
  local value = vim.fn.input(prompt)
  if value == "" then
    return nil
  end
  return value
end

local function open_oil(path)
  if path == nil or path == "" then
    vim.cmd("Oil")
    return
  end

  vim.cmd("Oil " .. vim.fn.fnameescape(path))
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("nvim2-lsp-keymaps", { clear = true }),
  callback = function(ev)
    local bufnr = ev.buf
    local opts = { buffer = bufnr, noremap = true, silent = true }

    map("n", "gD", vim.lsp.buf.declaration, opts)
    map("n", "gd", vim.lsp.buf.definition, opts)
    map("n", "K", vim.lsp.buf.hover, opts)
    map("n", "gi", vim.lsp.buf.implementation, opts)
    map("n", "gr", vim.lsp.buf.references, opts)
    map("n", "gs", vim.lsp.buf.signature_help, opts)
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    map("n", "<leader>cr", vim.lsp.buf.rename, opts)
    map("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    map("n", "<leader>ds", vim.lsp.buf.document_symbol, opts)
    map("n", "<leader>ws", vim.lsp.buf.workspace_symbol, opts)
    map("n", "<leader>e", vim.diagnostic.open_float, opts)
    map("n", "[d", vim.diagnostic.goto_prev, opts)
    map("n", "]d", vim.diagnostic.goto_next, opts)
    map("n", "<leader>cf", function()
      require("conform").format({ bufnr = bufnr, async = true, lsp_fallback = true })
    end, opts)
  end,
})

map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode" })
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map({ "n", "x", "o" }, "<leader>jl", "<Plug>(leap)", { desc = "Leap" })
map("n", "<leader>jL", "<Plug>(leap-from-window)", { desc = "Leap window" })

map("n", "<leader>wv", "<C-w>v", { desc = "Split vertical" })
map("n", "<leader>ws", "<C-w>s", { desc = "Split horizontal" })
map("n", "<leader>wd", "<C-w>c", { desc = "Close window" })
map("n", "<leader>wh", "<C-w>h", { desc = "Window left" })
map("n", "<leader>wj", "<C-w>j", { desc = "Window down" })
map("n", "<leader>wk", "<C-w>k", { desc = "Window up" })
map("n", "<leader>wl", "<C-w>l", { desc = "Window right" })
map("n", "<leader>wH", "<C-w><", { desc = "Decrease width" })
map("n", "<leader>wL", "<C-w>>", { desc = "Increase width" })
map("n", "<leader>wJ", "<C-w>-", { desc = "Decrease height" })
map("n", "<leader>wK", "<C-w>+", { desc = "Increase height" })
map("n", "[t", "<cmd>tabprevious<CR>", { desc = "Previous tab" })
map("n", "]t", "<cmd>tabnext<CR>", { desc = "Next tab" })

map("n", "<leader>qq", "<cmd>qa<CR>", { desc = "Quit all" })
map("n", "<leader>bb", function()
  snacks().picker.buffers()
end, { desc = "Switch buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Kill buffer" })
map("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>qf", function()
  require("quicker").toggle({ focus = true })
end, { desc = "Toggle quickfix" })
map("n", "<leader>ql", function()
  require("quicker").toggle({ loclist = true, focus = true })
end, { desc = "Toggle loclist" })
map("n", "<leader>qe", function()
  require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
end, { desc = "Expand quickfix" })
map("n", "<leader>qc", function()
  require("quicker").collapse()
end, { desc = "Collapse quickfix" })

map("n", "<leader>ss", function()
  local name = input("Session save name: ")
  if name then
    resession().save(name, { dir = "dirsession" })
  end
end, { desc = "Save session" })
map("n", "<leader>sl", function()
  local name = input("Session load name: ")
  if name then
    resession().load(name, { dir = "dirsession" })
  end
end, { desc = "Load session" })
map("n", "<leader>sd", function()
  local name = input("Session delete name: ")
  if name then
    resession().delete(name, { dir = "dirsession" })
  end
end, { desc = "Delete session" })
map("n", "<leader>sr", function()
  resession().load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true })
end, { desc = "Restore cwd session" })

map("n", "<leader>h", function()
  vim.cmd("help")
end, { desc = "Help" })
map("n", "<leader>ts", "<cmd>TSManager<CR>", { desc = "Tree-sitter manager" })
map("n", "<leader>up", function()
  profile().pick()
end, { desc = "Select profile" })

map("n", "<leader>ff", function()
  snacks().picker.files()
end, { desc = "Find files" })
map("n", "<leader>fr", function()
  snacks().picker.recent()
end, { desc = "Recent files" })
map("n", "<leader>fg", function()
  snacks().picker.git_files()
end, { desc = "Git files" })
map("n", "<leader>fd", function()
  open_oil(vim.fn.getcwd())
end, { desc = "Explorer" })
map("n", "<leader>fD", function()
  open_oil(vim.fn.expand("%:p:h"))
end, { desc = "Open parent directory" })
map("n", "<leader>pp", function()
  snacks().picker.projects()
end, { desc = "Projects" })
map("n", "<leader>sg", function()
  snacks().picker.grep()
end, { desc = "Grep" })
map("n", "<leader>sb", function()
  snacks().picker.lines()
end, { desc = "Buffer lines" })
map("n", "<leader>sn", function()
  snacks().picker.notifications()
end, { desc = "Notifications" })
map("n", "<leader>:", function()
  snacks().picker.command_history()
end, { desc = "Command history" })
map("n", "<leader>oE", function()
  require("config.env").sync()
end, { desc = "Sync env" })
map("n", "<leader>oy", function()
  require("yaml-companion").open_ui_select()
end, { desc = "YAML schema" })
map("n", "<leader>oc", "<cmd>ReferencerToggle<CR>", { desc = "Toggle references" })
map("n", "<leader>oC", "<cmd>ReferencerUpdate<CR>", { desc = "Refresh references" })
map("n", "<leader>oR", restart_nvim, { desc = "Restart Neovim" })
map("n", "<leader>gwl", function()
  wt().open_picker()
end, { desc = "Worktree list" })
map("n", "<leader>gws", function()
  wt().prompt_switch()
end, { desc = "Worktree switch" })
map("n", "<leader>gwc", function()
  wt().prompt_create()
end, { desc = "Worktree create" })
map("n", "<leader>gwr", function()
  wt().prompt_remove()
end, { desc = "Worktree remove" })
map("n", "<leader>gm", function()
  wt().merge({ yes = true }, function(ok, msg)
    if not ok then
      vim.notify(msg or "wt merge failed", vim.log.levels.ERROR, { title = "worktrunk" })
    end
  end)
end, { desc = "Worktree merge" })

map("n", "<leader>gb", function()
  snacks().picker.git_branches()
end, { desc = "Git branches" })
map("n", "<leader>gs", function()
  snacks().picker.git_status()
end, { desc = "Git status" })
map("n", "<leader>gg", "<cmd>Neogit<CR>", { desc = "Neogit" })
map("n", "<leader>gd", "<cmd>DiffviewOpen<CR>", { desc = "Diffview open" })
map("n", "<leader>gH", "<cmd>DiffviewFileHistory %<CR>", { desc = "Diffview history" })

map("n", "<leader>dv", "<cmd>DapViewOpen<CR>", { desc = "DAP view open" })
map("n", "<leader>dV", "<cmd>DapViewClose<CR>", { desc = "DAP view close" })
map("n", "<leader>dc", function()
  require("dap").continue()
end, { desc = "DAP continue" })
map("n", "<leader>dn", function()
  require("dap").step_over()
end, { desc = "DAP step over" })
map("n", "<leader>di", function()
  require("dap").step_into()
end, { desc = "DAP step into" })
map("n", "<leader>do", function()
  require("dap").step_out()
end, { desc = "DAP step out" })
map("n", "<leader>db", function()
  require("dap").toggle_breakpoint()
end, { desc = "DAP breakpoint" })
map("n", "<leader>dB", function()
  local condition = vim.fn.input("Breakpoint condition: ")
  if condition == "" then
    require("dap").toggle_breakpoint()
  else
    require("dap").set_breakpoint(condition)
  end
end, { desc = "DAP conditional breakpoint" })
map("n", "<leader>dr", function()
  require("dap").restart()
end, { desc = "DAP restart" })
