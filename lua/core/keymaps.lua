local M = {}

local map = vim.keymap.set

local function open_oil(path)
  if path == nil or path == "" then
    vim.cmd("Oil")
    return
  end

  vim.cmd("Oil " .. vim.fn.fnameescape(path))
end

local function snacks()
  local ok, mod = pcall(require, "snacks")
  return ok and mod or nil
end

function M.setup()
  map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
  map("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode" })
  map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search" })
  map({ "n", "x", "o" }, "<leader>jl", "<Plug>(leap)", { desc = "Leap" })
  map("n", "<leader>jL", "<Plug>(leap-from-window)", { desc = "Leap window" })

  map("n", "<leader>wv", "<C-w>v", { desc = "Split vertical" })
  map("n", "<leader>wd", "<C-w>c", { desc = "Close window" })
  map("n", "<leader>wh", "<C-w>h", { desc = "Window left" })
  map("n", "<leader>wj", "<C-w>j", { desc = "Window down" })
  map("n", "<leader>wk", "<C-w>k", { desc = "Window up" })
  map("n", "<leader>wl", "<C-w>l", { desc = "Window right" })
  map("n", "<leader>wH", "<C-w><", { desc = "Decrease width" })
  map("n", "<leader>wL", "<C-w>>", { desc = "Increase width" })
  map("n", "<leader>wJ", "<C-w>-", { desc = "Decrease height" })
  map("n", "<leader>wK", "<C-w>+", { desc = "Increase height" })

  map("n", "[t", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
  map("n", "]t", "<cmd>tabnext<cr>", { desc = "Next tab" })
  map("n", "<leader>tt", "<cmd>tabnew<cr>", { desc = "New tab" })
  map("n", "<leader>tk", "<cmd>tabclose<cr>", { desc = "Kill tab" })
  map("n", "<leader>to", "<cmd>tabonly<cr>", { desc = "Close other tabs" })
  map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })

  map("n", "<leader>bb", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.buffers then
      sn.picker.buffers({
        hidden = true,
        unloaded = true,
        nofile = true,
        current = true,
      })
      return
    end

    vim.cmd("buffers")
  end, { desc = "Switch buffer" })
  map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Kill buffer" })
  map("n", "<leader>bD", function()
    local sn = snacks()
    if sn and sn.bufdelete and sn.bufdelete.delete then
      sn.bufdelete.delete({ force = true })
      return
    end

    vim.cmd("bdelete!")
  end, { desc = "Force kill buffer" })
  map("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "Next buffer" })
  map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

  map("n", "<leader>ff", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.files then
      sn.picker.files()
      return
    end

    vim.cmd("edit .")
  end, { desc = "Find files" })
  map("n", "<leader>fr", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.recent then
      sn.picker.recent()
      return
    end

    vim.cmd("oldfiles")
  end, { desc = "Recent files" })
  map("n", "<leader>fg", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.git_files then
      sn.picker.git_files()
      return
    end

    vim.notify("Snacks git files unavailable", vim.log.levels.WARN, { title = "Files" })
  end, { desc = "Git files" })
  map("n", "<leader>fd", function()
    open_oil(vim.fn.getcwd())
  end, { desc = "Explorer" })
  map("n", "<leader>fD", function()
    open_oil(vim.fn.expand("%:p:h"))
  end, { desc = "Open parent directory" })
  map("n", "<leader>fj", function()
    open_oil(vim.fn.expand("%:p:h"))
  end, { desc = "Jump to file in explorer" })

  map("n", "<leader>sg", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.grep then
      sn.picker.grep()
      return
    end

    vim.notify("Snacks grep unavailable", vim.log.levels.WARN, { title = "Search" })
  end, { desc = "Grep" })
  map("n", "<leader>sw", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.grep_word then
      sn.picker.grep_word()
      return
    end

    vim.notify("Snacks grep word unavailable", vim.log.levels.WARN, { title = "Search" })
  end, { desc = "Grep word" })
  map("n", "<leader>si", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.lsp_symbols then
      sn.picker.lsp_symbols()
      return
    end

    vim.notify("Snacks LSP symbols unavailable", vim.log.levels.WARN, { title = "Search" })
  end, { desc = "LSP symbols" })
  map("n", "<leader>sb", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.lines then
      sn.picker.lines()
      return
    end

    vim.notify("Snacks buffer lines unavailable", vim.log.levels.WARN, { title = "Search" })
  end, { desc = "Buffer lines" })
  map("n", "<leader>:", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.command_history then
      sn.picker.command_history()
      return
    end

    vim.notify("Snacks command history unavailable", vim.log.levels.WARN, { title = "Search" })
  end, { desc = "Command history" })

  map("n", "<leader>ao", "<cmd>AcpOpen<cr>", { desc = "Open ACP transcript" })
  map("n", "<leader>gb", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.git_branches then
      sn.picker.git_branches()
      return
    end

    vim.notify("Snacks git branches unavailable", vim.log.levels.WARN, { title = "Git" })
  end, { desc = "Git branches" })
  map("n", "<leader>gd", "<cmd>CodeDiff<cr>", { desc = "CodeDiff (working tree)" })
  map("n", "<leader>gH", "<cmd>CodeDiff history %<cr>", { desc = "CodeDiff file history" })
  map("n", "<leader>gg", "<cmd>Neogit<cr>", { desc = "Neogit" })
  map("n", "<leader>gs", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.git_status then
      sn.picker.git_status()
      return
    end

    vim.cmd("Neogit")
  end, { desc = "Git status" })
  map("n", "<leader>sn", function()
    local sn = snacks()
    if sn and sn.picker and sn.picker.notifications then
      sn.picker.notifications()
      return
    end

    vim.notify("Snacks notifications unavailable", vim.log.levels.WARN, { title = "ACP" })
  end, { desc = "Notifications" })

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

  map("n", "<leader>pl", "<cmd>SessionLoad<cr>", { desc = "Load recent session" })
  map("n", "<leader>ps", "<cmd>SessionSave<cr>", { desc = "Save session" })

  map("n", "<leader>ot", function()
    local sn = snacks()
    if sn and sn.terminal and sn.terminal.toggle then
      sn.terminal.toggle(nil, { win = { position = "right" } })
      return
    end
    vim.cmd("botright vsplit | terminal")
    vim.cmd("startinsert")
  end, { desc = "Open terminal" })
end

return M
