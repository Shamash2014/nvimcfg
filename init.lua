local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

vim.loader.enable()

vim.o.hidden = true
vim.o.lazyredraw = true
vim.o.ttyfast = true
vim.o.synmaxcol = 200
vim.o.re = 0

local disabled_plugins = {
  "getscript", "getscriptPlugin", "vimball", "vimballPlugin",
  "2html_plugin", "logipat", "rrhelper", "spellfile_plugin",
  "matchit", "matchparen", "tarPlugin", "zipPlugin", "gzip",
  "netrwPlugin", "tohtml", "tutor"
}
for _, plugin in ipairs(disabled_plugins) do
  vim.g["loaded_" .. plugin] = 1
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.whichwrap = "h,l,<,>,[,],~"
vim.opt.breakindentopt = "shift:2,min:20"
vim.opt.showbreak = "↳ "
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 10
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.clipboard = "unnamedplus"
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo"
vim.opt.scrolloff = 8
vim.opt.foldlevelstart = 99
vim.opt.foldmethod = "marker"
vim.opt.spelloptions = "camel"
vim.opt.textwidth = 100
vim.opt.colorcolumn = "100"

-- Native completion settings
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.pumheight = 15
vim.opt.pumblend = 10

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("n", "<leader>w", "<C-w>", { desc = "Window" })

-- Tab navigation (aligned with window keys)
vim.keymap.set("n", "<leader>tj", "<cmd>tabnext<cr>", { desc = "Next tab" })
vim.keymap.set("n", "<leader>tk", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
vim.keymap.set("n", "<leader>th", "<cmd>tabfirst<cr>", { desc = "First tab" })
vim.keymap.set("n", "<leader>tl", "<cmd>tablast<cr>", { desc = "Last tab" })
vim.keymap.set("n", "<leader>tn", "<cmd>tabnew<cr>", { desc = "New tab" })
vim.keymap.set("n", "<leader>tc", "<cmd>tabclose<cr>", { desc = "Close tab" })

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true })
  end,
})

require("lazy").setup("plugins", {
  defaults = { lazy = true },
  performance = {
    cache = { enabled = true },
    reset_packpath = true,
    rtp = {
      reset = true,
      disabled_plugins = disabled_plugins,
    },
  },
  change_detection = {
    enabled = true,
    notify = false,
  },
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      if client.config and client.config.flags then
        client.config.flags.debounce_text_changes = 150
      end
      if client.server_capabilities then
        client.server_capabilities.textDocumentSync = client.server_capabilities.textDocumentSync or {}
        if type(client.server_capabilities.textDocumentSync) == "table" then
          client.server_capabilities.textDocumentSync.change = 2
        end
      end
    end
  end,
})

local function get_project_root(path)
  path = path or vim.fn.expand('%:p:h')
  if path == '' then
    path = vim.fn.getcwd()
  end

  -- Strategy 1: Git repository root
  local git_root = vim.fn.system("cd " .. vim.fn.shellescape(path) .. " && git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end

  -- Strategy 2: Look for project markers
  local markers = {
    '.git', '.svn', '.hg',
    '.envrc', 'flake.nix', 'shell.nix',
    'docker-compose.yml', 'docker-compose.yaml',
    'package.json', 'Cargo.toml', 'go.mod', 'pom.xml',
    'build.gradle', 'CMakeLists.txt', 'Makefile',
    'setup.py', 'pyproject.toml', 'tsconfig.json',
    'composer.json', '.project', '.vscode', '.idea',
    'mix.exs', 'pubspec.yaml'
  }

  -- Search upwards for markers
  local current = path
  local found_mix_exs = nil

  while current ~= '/' do
    for _, marker in ipairs(markers) do
      local marker_path = current .. '/' .. marker
      if vim.fn.isdirectory(marker_path) == 1 or vim.fn.filereadable(marker_path) == 1 then
        -- Special handling for Elixir umbrella projects
        if marker == 'mix.exs' then
          -- Check if this is an umbrella project
          local mix_content = vim.fn.readfile(marker_path)
          for _, line in ipairs(mix_content) do
            if line:match('apps_path:%s*"apps"') or line:match("apps_path:%s*'apps'") then
              -- This is an umbrella root, use it
              return current
            end
          end
          -- Not an umbrella, but remember the first mix.exs we found
          if not found_mix_exs then
            found_mix_exs = current
          end
          -- Continue searching upward for umbrella
        else
          return current
        end
      end
    end
    local parent = vim.fn.fnamemodify(current, ':h')
    if parent == current then
      break
    end
    current = parent
  end

  -- If we found a mix.exs but no umbrella, use it
  if found_mix_exs then
    return found_mix_exs
  end

  -- Strategy 3: Check if we're in a bare repository
  local is_bare = vim.fn.system("cd " .. vim.fn.shellescape(path) .. " && git rev-parse --is-bare-repository 2>/dev/null"):gsub("\n", "") == "true"
  if is_bare then
    local git_dir = vim.fn.system("cd " .. vim.fn.shellescape(path) .. " && git rev-parse --git-dir 2>/dev/null"):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if git_dir ~= "" then
      return vim.fn.fnamemodify(git_dir, ":h")
    end
  end

  -- Fallback to current working directory
  return vim.fn.getcwd()
end

vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "BufEnter" }, {
  callback = function()
    local current_path = vim.fn.expand("%:p:h")
    if current_path == "" then current_path = vim.fn.getcwd() end

    -- Update project root
    local project_root = get_project_root(current_path)
    vim.g.project_root = project_root

    -- Auto-change directory to project root
    if project_root and vim.fn.isdirectory(project_root) == 1 then
      if vim.fn.getcwd() ~= project_root then
        vim.cmd("cd " .. vim.fn.fnameescape(project_root))
      end
    end
  end,
})

vim.api.nvim_create_user_command("ProjectRoot", function()
  vim.notify("Project root: " .. (vim.g.project_root or vim.fn.getcwd()), vim.log.levels.INFO)
end, {})

-- Minimal statusline (Carmack-approved)
vim.opt.laststatus = 2

_G.lsp_status = function()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then return "" end
  local names = {}
  for _, client in ipairs(clients) do
    table.insert(names, client.name)
  end
  return " LSP:" .. table.concat(names, ",") .. " "
end

_G.overseer_status = function()
  if not package.loaded["overseer"] then
    return ""
  end

  local ok, overseer = pcall(require, "overseer")
  if not ok then return "" end

  local tasks = overseer.list_tasks({ recent_first = true })
  local running = 0
  local failed = 0

  for _, task in ipairs(tasks) do
    if task.status == "RUNNING" then
      running = running + 1
    elseif task.status == "FAILURE" then
      failed = failed + 1
    end
  end

  if running > 0 then
    return " ⏳" .. running .. " "
  elseif failed > 0 then
    return " ✗" .. failed .. " "
  end
  return ""
end

vim.opt.statusline = table.concat({
  " %<%f",                                    -- relative file path
  " %m%r",                                    -- modified/readonly flags
  "%=",                                       -- right align
  "%{v:lua.overseer_status()}",              -- running tasks
  "%{v:lua.lsp_status()}",                   -- LSP clients
  " %l:%c %P ",                              -- line:col percentage
}, "")

-- Unified toolchain selector
local function get_toolchain_info()
  local toolchains = {}

  -- Python virtual environment
  local venv = vim.fn.getenv("VIRTUAL_ENV")
  if venv ~= vim.NIL and venv ~= "" then
    local venv_name = vim.fn.fnamemodify(venv, ":t")
    table.insert(toolchains, {
      name = "Python venv: " .. venv_name,
      action = function()
        vim.cmd("VenvSelect")
      end,
      detail = venv
    })
  else
    table.insert(toolchains, {
      name = "Python: No venv selected",
      action = function()
        vim.cmd("VenvSelect")
      end,
      detail = "Click to select virtual environment"
    })
  end

  -- Node.js version
  local node_version = vim.fn.system("node --version 2>/dev/null"):gsub("\n", "")
  if node_version ~= "" then
    table.insert(toolchains, {
      name = "Node.js: " .. node_version,
      detail = vim.fn.system("which node 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Go version
  local go_version = vim.fn.system("go version 2>/dev/null"):match("go(%d+%.%d+%.%d+)")
  if go_version then
    table.insert(toolchains, {
      name = "Go: " .. go_version,
      detail = vim.fn.system("which go 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Rust version
  local rust_version = vim.fn.system("rustc --version 2>/dev/null"):match("rustc (%S+)")
  if rust_version then
    table.insert(toolchains, {
      name = "Rust: " .. rust_version,
      detail = vim.fn.system("which rustc 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Elixir version
  local elixir_version = vim.fn.system("elixir --version 2>/dev/null"):match("Elixir (%S+)")
  if elixir_version then
    table.insert(toolchains, {
      name = "Elixir: " .. elixir_version,
      detail = vim.fn.system("which elixir 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Dart version
  local dart_version = vim.fn.system("dart --version 2>&1"):match("Dart SDK version: (%S+)")
  if dart_version then
    table.insert(toolchains, {
      name = "Dart: " .. dart_version,
      detail = vim.fn.system("which dart 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Flutter version
  local flutter_version = vim.fn.system("flutter --version 2>&1"):match("Flutter (%S+)")
  if flutter_version then
    table.insert(toolchains, {
      name = "Flutter: " .. flutter_version,
      detail = vim.fn.system("which flutter 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Java version
  local java_version = vim.fn.system("java -version 2>&1"):match('version "(%S+)"')
  if java_version then
    table.insert(toolchains, {
      name = "Java: " .. java_version,
      detail = vim.fn.getenv("JAVA_HOME") or vim.fn.system("which java 2>/dev/null"):gsub("\n", "")
    })
  end

  -- Mise toolchains
  local mise_output = vim.fn.system("mise current 2>/dev/null")
  if mise_output ~= "" and not mise_output:match("^mise: command not found") then
    for line in mise_output:gmatch("[^\r\n]+") do
      if line ~= "" and not line:match("^%s*$") then
        table.insert(toolchains, {
          name = "Mise: " .. line,
          detail = "Managed by mise"
        })
      end
    end
  end

  -- Direnv status
  local direnv_status = vim.fn.getenv("DIRENV_DIR")
  if direnv_status ~= vim.NIL and direnv_status ~= "" then
    table.insert(toolchains, {
      name = "Direnv: Active",
      action = function()
        vim.fn.system("direnv reload")
        vim.notify("Direnv reloaded", vim.log.levels.INFO)
      end,
      detail = direnv_status
    })
  end

  return toolchains
end

vim.keymap.set("n", "<leader>pt", function()
  local toolchains = get_toolchain_info()

  if #toolchains == 0 then
    vim.notify("No toolchains detected", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, tc in ipairs(toolchains) do
    table.insert(items, tc.name)
  end

  vim.ui.select(items, {
    prompt = "Toolchains:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if idx and toolchains[idx].action then
      toolchains[idx].action()
    elseif idx and toolchains[idx].detail then
      vim.notify(toolchains[idx].detail, vim.log.levels.INFO)
    end
  end)
end, { desc = "Show Toolchains" })
