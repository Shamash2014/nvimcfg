return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    picker = {
      enabled = true,
      layout = {
        preset = "vscode",
        preview = false,
      },
      preview = {
        enabled = false,
      },
      win = {
        input = {
          keys = {
            ["<C-j>"] = { "list_down", mode = { "i", "n" } },
            ["<C-k>"] = { "list_up", mode = { "i", "n" } },
          },
        },
      },
      formatters = {
        file = {
          filename_first = true,
        },
      },
    },
    input = {
      enabled = true,
    },
    terminal = {
      enabled = true,
      win = {
        position = "bottom",
        height = 0.3,
        style = "terminal",
      },
    },
    words = {
      enabled = true,
      debounce = 200,
    },
    rename = {
      enabled = true,
    },
    quickfix = {
      enabled = true,
    },
    notifier = {
      enabled = false,
    },
    dashboard = {
      enabled = false,
    },
    dim = {
      enabled = false,
    },
    quickfile = {
      enabled = true,
    },
    bigfile = {
      enabled = true,
      size = 1.5 * 1024 * 1024,
    },
    zen = {
      enabled = true,
    },
    scope = {
      enabled = true,
    },
    scratch = {
      enabled = true,
    },
  },
  keys = {
    { "<leader><leader>", function()
      local root = vim.g.project_root or vim.fn.getcwd()
      require("snacks").picker.files({ cwd = root })
    end, desc = "Smart Find Files" },
    { "<leader>ff", function()
      local root = vim.g.project_root or vim.fn.getcwd()
      require("snacks").picker.files({ cwd = root })
    end, desc = "Find Files" },
    { "<leader>fr", function() require("snacks").picker.recent() end, desc = "Recent Files" },
    { "<leader>fb", function() require("snacks").picker.buffers() end, desc = "Find Buffers" },
    { "<leader>fc", function() require("snacks").picker.commands() end, desc = "Find Commands" },

    { "<leader>se", function()
      vim.ui.select({
        "Files", "Grep", "Buffers", "Commands",
        "Symbols", "Workspace Symbols", "Diagnostics",
        "Git Log", "Recent", "Help", "Marks"
      }, {
        prompt = "Search:",
      }, function(choice)
        local root = vim.g.project_root or vim.fn.getcwd()
        local snacks = require("snacks")
        if choice == "Files" then snacks.picker.files({ cwd = root })
        elseif choice == "Grep" then snacks.picker.grep({ cwd = root })
        elseif choice == "Buffers" then snacks.picker.buffers()
        elseif choice == "Commands" then snacks.picker.commands()
        elseif choice == "Symbols" then snacks.picker.lsp_symbols()
        elseif choice == "Workspace Symbols" then snacks.picker.lsp_workspace_symbols()
        elseif choice == "Diagnostics" then snacks.picker.diagnostics()
        elseif choice == "Git Log" then snacks.picker.git_log()
        elseif choice == "Recent" then snacks.picker.recent()
        elseif choice == "Help" then snacks.picker.help()
        elseif choice == "Marks" then snacks.picker.marks()
        end
      end)
    end, desc = "Search Everything" },
    { "<leader>sg", function()
      local root = vim.g.project_root or vim.fn.getcwd()
      require("snacks").picker.grep({ cwd = root })
    end, desc = "Grep" },
    { "<leader>sw", function() require("snacks").picker.grep_word() end, desc = "Search Word" },
    { "<leader>s*", function()
      local word = vim.fn.expand("<cword>")
      local root = vim.g.project_root or vim.fn.getcwd()
      require("snacks").picker.grep({ search = word, cwd = root })
    end, desc = "Grep Word Under Cursor" },
    { "<leader>ss", function() require("snacks").picker.lines() end, desc = "Search Lines in Buffer" },
    { "<leader>si", function() require("snacks").picker.lsp_symbols() end, desc = "Search Symbols" },
    { "<leader>sI", function() require("snacks").picker.lsp_workspace_symbols() end, desc = "Search Workspace Symbols" },
    { "<leader>sd", function() require("snacks").picker.diagnostics() end, desc = "Search Diagnostics" },
    { "<leader>sD", function() require("snacks").picker.diagnostics_buffer() end, desc = "Buffer Diagnostics" },
    { "<leader>sr", function() require("snacks").picker.resume() end, desc = "Resume Search" },

    { "<leader>hh", function() require("snacks").picker.help() end, desc = "Help Tags" },
    { "<leader>hk", function() require("snacks").picker.keymaps() end, desc = "Keymaps" },
    { "<leader>hm", function() require("snacks").picker.man() end, desc = "Man Pages" },

    { "<leader>fm", function() require("snacks").picker.marks() end, desc = "Marks" },
    { "<leader>fq", function() require("snacks").picker.qflist() end, desc = "Quickfix List" },
    { "<leader>fl", function() require("snacks").picker.loclist() end, desc = "Location List" },

    { "<leader>bb", function() require("snacks").picker.buffers() end, desc = "Buffer List" },
    { "<leader>bd", "<cmd>bdelete<cr>", desc = "Delete Buffer" },
    { "<leader>bD", "<cmd>bdelete!<cr>", desc = "Force Delete Buffer" },
    { "<leader>bt", function()
      local tabs = {}
      for i = 1, vim.fn.tabpagenr('$') do
        local winnr = vim.fn.tabpagewinnr(i)
        local bufnr = vim.fn.tabpagebuflist(i)[winnr]
        local bufname = vim.fn.bufname(bufnr)
        local name = bufname ~= "" and vim.fn.fnamemodify(bufname, ":~:.") or "[No Name]"
        table.insert(tabs, string.format("Tab %d: %s", i, name))
      end
      vim.ui.select(tabs, {
        prompt = "Select Tab:",
      }, function(choice, idx)
        if idx then vim.cmd(idx .. "tabnext") end
      end)
    end, desc = "Pick Tab" },

    { "<leader>tn", "<cmd>tabnew<cr>", desc = "New Tab" },
    { "<leader>tc", "<cmd>tabclose<cr>", desc = "Close Tab" },
    { "<leader>to", "<cmd>tabonly<cr>", desc = "Close Other Tabs" },
    { "<leader>tl", "<cmd>tabnext<cr>", desc = "Next Tab" },
    { "<leader>th", "<cmd>tabprevious<cr>", desc = "Previous Tab" },
    { "]t", "<cmd>tabnext<cr>", desc = "Next Tab" },
    { "[t", "<cmd>tabprevious<cr>", desc = "Previous Tab" },

    { "<leader>ww", "<C-w>w", desc = "Switch Window" },
    { "<leader>wd", "<C-w>c", desc = "Delete Window" },
    { "<leader>w-", "<C-w>s", desc = "Split Below" },
    { "<leader>w|", "<C-w>v", desc = "Split Right" },
    { "<leader>wh", "<C-w>h", desc = "Window Left" },
    { "<leader>wj", "<C-w>j", desc = "Window Down" },
    { "<leader>wk", "<C-w>k", desc = "Window Up" },
    { "<leader>wl", "<C-w>l", desc = "Window Right" },

    { "<leader>ott", function()
      local cwd = vim.g.project_root or vim.fn.getcwd(0)
      vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
      vim.cmd("terminal")
      vim.cmd("startinsert")
    end, desc = "Open Terminal" },
    { "<leader>otc", function()
      local cmd = vim.fn.input("Command: ")
      if cmd ~= "" then
        vim.g.last_terminal_command = cmd
        local cwd = vim.g.project_root or vim.fn.getcwd(0)
        vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
        vim.cmd("terminal " .. cmd)
        vim.cmd("startinsert")
      end
    end, desc = "Open Command in Terminal" },
    { "<leader>otq", function() require("snacks").terminal.toggle() end, desc = "Toggle Terminal" },
    { "<c-/>", function() require("snacks").terminal.toggle() end, desc = "Toggle Terminal", mode = { "n", "t" } },
    { "<leader>otr", function()
      if vim.g.last_terminal_command then
        local cwd = vim.g.project_root or vim.fn.getcwd(0)
        vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
        vim.cmd("terminal " .. vim.g.last_terminal_command)
        vim.cmd("startinsert")
      else
        vim.notify("No previous command to rerun", vim.log.levels.WARN)
      end
    end, desc = "Rerun Last Command" },

    { "<leader>gl", function() require("snacks").picker.git_log() end, desc = "Git Log" },

    { "<leader>qq", "<cmd>qa<cr>", desc = "Quit All" },
    { "<leader>qtd", function() require("snacks").dim.toggle() end, desc = "Toggle Dim" },
    { "<leader>qtz", function() require("snacks").zen.toggle() end, desc = "Toggle Zen" },
    { "<leader>z", function() require("snacks").zen.zoom() end, desc = "Zen Zoom" },

    { "<leader>cr", function() require("snacks").rename() end, desc = "Rename" },
    { "<leader>os", function() require("snacks").scratch() end, desc = "Scratch Buffer" },
    { "<leader>oS", function() require("snacks").scratch.select() end, desc = "Select Scratch" },
    { "<leader>oc", function() require("snacks").picker.commands() end, desc = "Command Palette" },
  },
}
