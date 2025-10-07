return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "windwp/nvim-ts-autotag",
      "JoosepAlviste/nvim-ts-context-commentstring",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        indent = { enable = true },
        autotag = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["a="] = "@assignment.outer",
              ["i="] = "@assignment.inner",
              ["ar"] = "@return.outer",
              ["ir"] = "@return.inner",
              ["ao"] = "@comment.outer",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]b"] = "@block.outer",
              ["]l"] = "@loop.outer",
              ["]i"] = "@conditional.outer",
              ["]a"] = "@parameter.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[b"] = "@block.outer",
              ["[l"] = "@loop.outer",
              ["[i"] = "@conditional.outer",
              ["[a"] = "@parameter.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]B"] = "@block.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[B"] = "@block.outer",
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["gss"] = "@parameter.inner",
            },
            swap_previous = {
              ["gsS"] = "@parameter.inner",
            },
          },
          lsp_interop = {
            enable = true,
            border = 'none',
            peek_definition_code = {
              ["gpf"] = "@function.outer",
              ["gpc"] = "@class.outer",
            },
          },
        },
      })
    end,
  },

  {
    "echasnovski/mini.bracketed",
    version = false,
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("mini.bracketed").setup({
        buffer = { suffix = 'b', options = {} },
        comment = { suffix = 'c', options = {} },
        diagnostic = { suffix = 'd', options = {} },
        file = { suffix = 'f', options = {} },
        jump = { suffix = 'j', options = {} },
        quickfix = { suffix = 'q', options = {} },
        treesitter = { suffix = 't', options = {} },
        window = { suffix = 'w', options = {} },
      })

      local keymap = vim.keymap.set
      keymap("n", "]e", ":move .+1<CR>==", { desc = "Move line down" })
      keymap("n", "[e", ":move .-2<CR>==", { desc = "Move line up" })
      keymap("v", "]e", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
      keymap("v", "[e", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })
    end,
  },

  {
    "echasnovski/mini.ai",
    version = false,
    keys = {
      { "a", mode = { "x", "o" } },
      { "i", mode = { "x", "o" } },
    },
    config = function()
      local spec_treesitter = require('mini.ai').gen_spec.treesitter
      require("mini.ai").setup({
        custom_textobjects = {
          e = function()
            local from = { line = 1, col = 1 }
            local to = {
              line = vim.fn.line('$'),
              col = math.max(vim.fn.getline('$'):len(), 1)
            }
            return { from = from, to = to }
          end,
          F = spec_treesitter({ a = "@call.outer", i = "@call.inner" }),
          a = spec_treesitter({ a = "@parameter.outer", i = "@parameter.inner" }),
          i = spec_treesitter({ a = "@conditional.outer", i = "@conditional.inner" }),
          l = spec_treesitter({ a = "@loop.outer", i = "@loop.inner" }),
          o = spec_treesitter({
            a = { "@conditional.outer", "@loop.outer" },
            i = { "@conditional.inner", "@loop.inner" },
          }),
        },
      })
    end,
  },

  {
    "echasnovski/mini.hipatterns",
    version = false,
    event = "BufReadPost",
    config = function()
      require("mini.hipatterns").setup({
        highlighters = {
          fixme = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
          hack  = { pattern = '%f[%w]()HACK()%f[%W]', group = 'MiniHipatternsHack' },
          todo  = { pattern = '%f[%w]()TODO()%f[%W]', group = 'MiniHipatternsTodo' },
          note  = { pattern = '%f[%w]()NOTE()%f[%W]', group = 'MiniHipatternsNote' },
        },
      })
    end,
  },

  {
    "brenoprata10/nvim-highlight-colors",
    event = "BufReadPost",
    opts = {
      render = "virtual",
      virtual_symbol = "■",
      enable_named_colors = true,
      enable_tailwind = true,
    },
  },

  {
    "chrisgrieser/nvim-lsp-endhints",
    event = "LspAttach",
    opts = {
      icons = {
        type = "⇒ ",
        parameter = "← ",
        offspec = " ",
      },
      label = {
        padding = 1,
        marginLeft = 0,
        bracketedParameters = true,
      },
      autoEnableHints = true,
    },
  },

  {
    "kylechui/nvim-surround",
    version = "*",
    keys = {
      { "ys", mode = "n" },
      { "yss", mode = "n" },
      { "ds", mode = "n" },
      { "cs", mode = "n" },
      { "S", mode = "x" },
    },
    config = function()
      require("nvim-surround").setup({})
    end,
  },

  {
    "Wansmer/sibling-swap.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    keys = {
      { "<C-.>", mode = "n" },
      { "<C-,>", mode = "n" },
    },
    opts = {
      keymaps = {
        ["<C-.>"] = "swap_with_right",
        ["<C-,>"] = "swap_with_left",
      },
    },
  },

  {
    "aaronik/treewalker.nvim",
    keys = {
      { "<leader>j", "<cmd>Treewalker Down<cr>", desc = "AST Down" },
      { "<leader>k", "<cmd>Treewalker Up<cr>", desc = "AST Up" },
      { "<leader>h", "<cmd>Treewalker Left<cr>", desc = "AST Left" },
      { "<leader>l", "<cmd>Treewalker Right<cr>", desc = "AST Right" },
    },
  },

  {
    "folke/flash.nvim",
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    },
  },


  {
    "mbbill/undotree",
    cmd = "UndotreeToggle",
    keys = {
      { "<leader>ou", "<cmd>UndotreeToggle<cr>", desc = "Undo Tree" },
    },
    config = function()
      vim.g.undotree_WindowLayout = 2
      vim.g.undotree_ShortIndicators = 1
      vim.g.undotree_SetFocusWhenToggle = 1
    end,
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = true,
      ts_config = {
        lua = { "string" },
        javascript = { "template_string" },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        desc = "Format"
      },
    },
    config = function()
      local formatters_by_ft = {}

      if vim.fn.executable("stylua") == 1 then
        formatters_by_ft.lua = { "stylua" }
      end

      if vim.fn.executable("ruff") == 1 then
        formatters_by_ft.python = { "ruff_format" }
      end

      if vim.fn.executable("prettier") == 1 then
        formatters_by_ft.javascript = { "prettier" }
        formatters_by_ft.typescript = { "prettier" }
        formatters_by_ft.typescriptreact = { "prettier" }
        formatters_by_ft.javascriptreact = { "prettier" }
        formatters_by_ft.json = { "prettier" }
        formatters_by_ft.html = { "prettier" }
        formatters_by_ft.css = { "prettier" }
        formatters_by_ft.yaml = { "prettier" }
        formatters_by_ft.markdown = { "prettier" }
      end

      if vim.fn.executable("mix") == 1 then
        formatters_by_ft.elixir = { "mix" }
      end

      local go_formatters = {}
      if vim.fn.executable("goimports") == 1 then
        table.insert(go_formatters, "goimports")
      end
      if vim.fn.executable("gofumpt") == 1 then
        table.insert(go_formatters, "gofumpt")
      end
      if #go_formatters > 0 then
        formatters_by_ft.go = go_formatters
      end

      if vim.fn.executable("rustfmt") == 1 then
        formatters_by_ft.rust = { "rustfmt" }
      end

      if vim.fn.executable("nixfmt") == 1 then
        formatters_by_ft.nix = { "nixfmt" }
      end

      require("conform").setup({
        formatters_by_ft = formatters_by_ft,
        format_on_save = function(bufnr)
          if vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr)) > 100000 then
            return
          end
          return { timeout_ms = 1000, lsp_fallback = true }
        end,
      })
    end,
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require("lint")
      local linters_by_ft = {}

      if vim.fn.executable("ruff") == 1 then
        linters_by_ft.python = { "ruff" }
      end

      if vim.fn.executable("eslint") == 1 then
        linters_by_ft.javascript = { "eslint" }
        linters_by_ft.typescript = { "eslint" }
        linters_by_ft.javascriptreact = { "eslint" }
        linters_by_ft.typescriptreact = { "eslint" }
      end

      if vim.fn.executable("golangci-lint") == 1 then
        linters_by_ft.go = { "golangcilint" }
      end

      lint.linters_by_ft = linters_by_ft

      local lint_augroup = vim.api.nvim_create_augroup("nvim_lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          if vim.fn.getfsize(vim.api.nvim_buf_get_name(0)) > 100000 then
            return
          end
          lint.try_lint()
        end,
      })
    end,
  },

  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "folke/snacks.nvim",
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>",        desc = "Neogit Status" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit Commit" },
      { "<leader>gp", "<cmd>Neogit push<cr>",   desc = "Neogit Push" },
      { "<leader>gl", "<cmd>Neogit pull<cr>",   desc = "Neogit Pull" },
      { "<leader>gb", "<cmd>Neogit branch<cr>", desc = "Neogit Branch" },
    },
    opts = {
      kind = "vsplit",
      integrations = {
        diffview = true,
        snacks = true,
      },
    },
  },

  {
    "APZelos/blamer.nvim",
    event = "BufReadPost",
    config = function()
      vim.g.blamer_enabled = 1
      vim.g.blamer_delay = 300
      vim.g.blamer_show_in_insert_modes = 0
      vim.g.blamer_prefix = " "
      vim.g.blamer_template = "<author>, <author-time> • <summary>"
      vim.g.blamer_date_format = "%Y-%m-%d"
    end,
    keys = {
      { "<leader>gtb", "<cmd>BlamerToggle<cr>", desc = "Toggle Inline Blame" },
    },
  },

  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>",          desc = "Diff View" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
    },
    opts = {},
  },

  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = "BufReadPost",
    config = function()
      require("git-conflict").setup({
        default_mappings = true,
        default_commands = true,
        disable_diagnostics = false,
        list_opener = function()
          require("snacks").picker.qflist()
        end,
        highlights = {
          incoming = "DiffAdd",
          current = "DiffText",
        },
      })

      vim.keymap.set("n", "<leader>gco", "<cmd>GitConflictChooseOurs<cr>", { desc = "Choose Ours" })
      vim.keymap.set("n", "<leader>gct", "<cmd>GitConflictChooseTheirs<cr>", { desc = "Choose Theirs" })
      vim.keymap.set("n", "<leader>gcb", "<cmd>GitConflictChooseBoth<cr>", { desc = "Choose Both" })
      vim.keymap.set("n", "<leader>gc0", "<cmd>GitConflictChooseNone<cr>", { desc = "Choose None" })
      vim.keymap.set("n", "<leader>gcl", "<cmd>GitConflictListQf<cr>", { desc = "List Conflicts" })
      vim.keymap.set("n", "]x", "<cmd>GitConflictNextConflict<cr>", { desc = "Next Conflict" })
      vim.keymap.set("n", "[x", "<cmd>GitConflictPrevConflict<cr>", { desc = "Prev Conflict" })
    end,
  },

  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    keys = {
      { "<leader>e",  "<cmd>Oil<cr>", desc = "Oil File Manager" },
      { "<leader>fj", "<cmd>Oil<cr>", desc = "Jump to Oil" },
    },
    opts = {
      default_file_explorer = true,
      columns = {
        "icon",
      },
      view_options = {
        show_hidden = false,
      },
    },
  },

  {
    "stevearc/overseer.nvim",
    lazy = true,
    cmd = {
      "OverseerRun",
      "OverseerToggle",
      "OverseerBuild",
      "OverseerQuickAction",
      "OverseerTaskAction",
      "OverseerInfo",
      "OverseerOpen",
      "OverseerClose",
      "OverseerLoadBundle",
      "OverseerSaveBundle",
      "OverseerDeleteBundle",
      "OverseerRunCmd",
      "OverseerClearCache",
    },
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>",         desc = "Run Task" },
      { "<leader>ro", "<cmd>OverseerToggle<cr>",      desc = "Toggle Overseer" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>",       desc = "Build Task" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick Action" },
      { "<leader>ra", "<cmd>OverseerTaskAction<cr>",  desc = "Task Action" },
    },
    opts = {
      dap = true,
      task_list = {
        direction = "bottom",
        min_height = 15,
        max_height = 30,
        default_detail = 2,
        bindings = {
          ["?"] = "ShowHelp",
          ["g?"] = "ShowHelp",
          ["<CR>"] = "RunAction",
          ["<C-e>"] = "Edit",
          ["o"] = "Open",
          ["<C-v>"] = "OpenVsplit",
          ["<C-s>"] = "OpenSplit",
          ["<C-f>"] = "OpenFloat",
          ["<C-q>"] = "OpenQuickFix",
          ["p"] = "TogglePreview",
          ["<C-l>"] = "IncreaseDetail",
          ["<C-h>"] = "DecreaseDetail",
          ["L"] = "IncreaseAllDetail",
          ["H"] = "DecreaseAllDetail",
          ["["] = "DecreaseWidth",
          ["]"] = "IncreaseWidth",
          ["{"] = "PrevTask",
          ["}"] = "NextTask",
        },
      },
      component_aliases = {
        default = {
          { "display_duration", detail_level = 2 },
          "on_exit_set_status",
          "on_complete_notify",
          "on_complete_dispose",
        },
      },
    },
    config = function(_, opts)
      local overseer = require("overseer")
      overseer.setup(opts)

      local has_docker_compose = function()
        return vim.fn.filereadable("docker-compose.yml") == 1 or
            vim.fn.filereadable("docker-compose.yaml") == 1 or
            vim.fn.filereadable("compose.yml") == 1 or
            vim.fn.filereadable("compose.yaml") == 1
      end

      local has_nix = function()
        return vim.fn.filereadable("flake.nix") == 1 or
            vim.fn.filereadable("shell.nix") == 1
      end

      local has_justfile = function()
        return vim.fn.filereadable("justfile") == 1 or
            vim.fn.filereadable("Justfile") == 1
      end

      local has_process_compose = function()
        return vim.fn.filereadable("process-compose.yml") == 1 or
            vim.fn.filereadable("process-compose.yaml") == 1
      end

      local get_just_recipes = function()
        if not has_justfile() then return {} end
        local recipes = {}
        local output = vim.fn.system("just --list --unsorted 2>/dev/null")
        for line in output:gmatch("[^\r\n]+") do
          local recipe = line:match("^%s*(%S+)")
          if recipe and recipe ~= "Available" and recipe ~= "" then
            table.insert(recipes, recipe)
          end
        end
        return recipes
      end

      overseer.register_template({
        name = "docker compose up",
        builder = function()
          return {
            cmd = { "docker" },
            args = { "compose", "up", "-d" },
            components = { "default" },
          }
        end,
        condition = { callback = has_docker_compose },
      })

      overseer.register_template({
        name = "docker compose down",
        builder = function()
          return {
            cmd = { "docker" },
            args = { "compose", "down" },
            components = { "default" },
          }
        end,
        condition = { callback = has_docker_compose },
      })

      overseer.register_template({
        name = "docker compose stop",
        builder = function()
          return {
            cmd = { "docker" },
            args = { "compose", "stop" },
            components = { "default" },
          }
        end,
        condition = { callback = has_docker_compose },
      })

      overseer.register_template({
        name = "docker compose exec",
        builder = function(params, cb)
          vim.ui.input({
            prompt = "Service: ",
          }, function(service)
            if not service or service == "" then
              return cb(nil)
            end
            vim.ui.input({
              prompt = "Command: ",
              default = "/bin/bash",
            }, function(cmd)
              if not cmd then
                return cb(nil)
              end
              cb({
                cmd = { "docker" },
                args = { "compose", "exec", service, cmd },
                components = { "default" },
              })
            end)
          end)
        end,
        condition = { callback = has_docker_compose },
      })

      overseer.register_template({
        name = "docker compose logs",
        builder = function(params, cb)
          vim.ui.input({
            prompt = "Service (empty for all): ",
          }, function(service)
            local args = { "compose", "logs", "-f" }
            if service and service ~= "" then
              table.insert(args, service)
            end
            cb({
              cmd = { "docker" },
              args = args,
              components = { "default" },
            })
          end)
        end,
        condition = { callback = has_docker_compose },
      })

      overseer.register_template({
        name = "nix develop",
        builder = function()
          return {
            cmd = { "nix" },
            args = { "develop" },
            components = { "default" },
          }
        end,
        condition = { callback = has_nix },
      })

      overseer.register_template({
        name = "nix build",
        builder = function()
          return {
            cmd = { "nix" },
            args = { "build" },
            components = { "default" },
          }
        end,
        condition = { callback = has_nix },
      })

      overseer.register_template({
        name = "nix run",
        builder = function(params, cb)
          if not cb then
            return {
              cmd = { "nix" },
              args = { "run", "." },
              components = { "default" },
            }
          end
          vim.ui.input({
            prompt = "Package: ",
            default = ".",
          }, function(pkg)
            if not pkg then
              return cb(nil)
            end
            cb({
              cmd = { "nix" },
              args = { "run", pkg },
              components = { "default" },
            })
          end)
        end,
        condition = { callback = has_nix },
      })

      overseer.register_template({
        name = "just",
        builder = function(params, cb)
          local recipes = get_just_recipes()
          if #recipes == 0 then
            vim.notify("No just recipes found", vim.log.levels.WARN)
            return cb(nil)
          end

          if #recipes == 1 then
            return cb({
              cmd = { "just" },
              args = { recipes[1] },
              components = { "default" },
            })
          else
            vim.ui.select(recipes, {
              prompt = "Select just recipe:",
            }, function(choice)
              if not choice then
                return cb(nil)
              end
              cb({
                cmd = { "just" },
                args = { choice },
                components = { "default" },
              })
            end)
          end
        end,
        condition = { callback = has_justfile },
      })

      overseer.register_template({
        name = "process-compose up",
        builder = function()
          return {
            cmd = { "process-compose" },
            args = { "up" },
            components = { "default" },
          }
        end,
        condition = { callback = has_process_compose },
      })

      overseer.register_template({
        name = "process-compose down",
        builder = function()
          return {
            cmd = { "process-compose" },
            args = { "down" },
            components = { "default" },
          }
        end,
        condition = { callback = has_process_compose },
      })

      overseer.register_template({
        name = "direnv allow",
        builder = function()
          return {
            cmd = { "direnv" },
            args = { "allow" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable(".envrc") == 1
          end,
        },
      })

      local has_gradle = function()
        return vim.fn.filereadable("build.gradle") == 1 or
            vim.fn.filereadable("build.gradle.kts") == 1 or
            vim.fn.filereadable("settings.gradle") == 1 or
            vim.fn.filereadable("settings.gradle.kts") == 1 or
            vim.fn.executable("./gradlew") == 1
      end

      local gradle_cmd = function()
        return vim.fn.executable("./gradlew") == 1 and "./gradlew" or "gradle"
      end

      overseer.register_template({
        name = "gradle build",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "build" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle clean",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "clean" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle assembleDebug",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "assembleDebug" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle assembleRelease",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "assembleRelease" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle installDebug",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "installDebug" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle bundleDebug",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "bundleDebug" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle bundleRelease",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "bundleRelease" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle test",
        builder = function()
          return {
            cmd = { gradle_cmd() },
            args = { "test" },
            components = { "default" },
          }
        end,
        condition = { callback = has_gradle },
      })

      overseer.register_template({
        name = "gradle tasks",
        builder = function(params, cb)
          local output = vim.fn.system(gradle_cmd() .. " tasks --all 2>/dev/null")
          local tasks = {}
          for line in output:gmatch("[^\r\n]+") do
            local task = line:match("^(%S+)%s+%-")
            if task then
              table.insert(tasks, task)
            end
          end

          if #tasks == 0 then
            vim.notify("No gradle tasks found", vim.log.levels.WARN)
            return cb(nil)
          end

          vim.ui.select(tasks, {
            prompt = "Select gradle task:",
          }, function(choice)
            if not choice then
              return cb(nil)
            end
            cb({
              cmd = { gradle_cmd() },
              args = { choice },
              components = { "default" },
            })
          end)
        end,
        condition = { callback = has_gradle },
      })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "*",
        callback = function()
          vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true })
        end,
      })
    end,
  },


  {
    "tpope/vim-sleuth",
    event = { "BufReadPost", "BufNewFile" },
  },


  {
    "tpope/vim-abolish",
    cmd = { "Abolish", "Subvert" },
    keys = {
      { "<leader>s/", "<cmd>Subvert/", desc = "Subvert (smart replace)" },
    },
  },

  {
    "amrbashir/nvim-docs-view",
    cmd = { "DocsViewToggle" },
    keys = {
      { "<leader>hd", "<cmd>DocsViewToggle<cr>", desc = "Toggle Docs View" },
    },
    opts = {
      position = "right",
      width = 60,
    },
  },

  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    keys = {
      {
        "<leader>cr",
        function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end,
        expr = true,
        desc = "Inc Rename",
      },
    },
    config = function()
      require("inc_rename").setup({
        input_buffer_type = "snacks_input",
      })
    end,
  },

  {
    "ekickx/clipboard-image.nvim",
    keys = {
      { "<leader>ip", "<cmd>PasteImg<cr>", desc = "Paste Image from Clipboard" },
    },
    opts = {
      default = {
        img_dir = "assets/images",
        img_name = function()
          return os.date("%Y-%m-%d-%H-%M-%S")
        end,
      },
      markdown = {
        img_dir = { "%:p:h", "assets", "images" },
        img_dir_txt = "./assets/images",
      },
    },
  },

  {
    "XXiaoA/ns-textobject.nvim",
    keys = {
      { "an", mode = { "o", "x" } },
      { "in", mode = { "o", "x" } },
    },
    config = function()
      vim.keymap.set({ "o", "x" }, "an", function()
        require("ns-textobject").select_namespace(true)
      end, { desc = "Around namespace" })

      vim.keymap.set({ "o", "x" }, "in", function()
        require("ns-textobject").select_namespace(false)
      end, { desc = "Inside namespace" })
    end,
  },

  {
    "chrisgrieser/nvim-various-textobjs",
    keys = {
      { "av", mode = { "o", "x" } },
      { "iv", mode = { "o", "x" } },
      { "ak", mode = { "o", "x" } },
      { "ik", mode = { "o", "x" } },
      { "an", mode = { "o", "x" } },
      { "in", mode = { "o", "x" } },
      { "ai", mode = { "o", "x" } },
      { "ii", mode = { "o", "x" } },
      { "aS", mode = { "o", "x" } },
      { "iS", mode = { "o", "x" } },
      { "au", mode = { "o", "x" } },
      { "ad", mode = { "o", "x" } },
    },
    config = function()
      local textobjs = require("various-textobjs")

      -- Value (function arguments, array elements, etc.)
      vim.keymap.set({ "o", "x" }, "av", function() textobjs.value("outer") end, { desc = "Around value" })
      vim.keymap.set({ "o", "x" }, "iv", function() textobjs.value("inner") end, { desc = "Inside value" })

      -- Key (object keys, parameter names)
      vim.keymap.set({ "o", "x" }, "ak", function() textobjs.key("outer") end, { desc = "Around key" })
      vim.keymap.set({ "o", "x" }, "ik", function() textobjs.key("inner") end, { desc = "Inside key" })

      -- Number
      vim.keymap.set({ "o", "x" }, "an", function() textobjs.number("outer") end, { desc = "Around number" })
      vim.keymap.set({ "o", "x" }, "in", function() textobjs.number("inner") end, { desc = "Inside number" })

      -- Indentation
      vim.keymap.set({ "o", "x" }, "ai", function() textobjs.indentation("outer", "outer") end, { desc = "Around indent" })
      vim.keymap.set({ "o", "x" }, "ii", function() textobjs.indentation("inner", "inner") end, { desc = "Inside indent" })

      -- Subword (camelCase/snake_case)
      vim.keymap.set({ "o", "x" }, "aS", function() textobjs.subword("outer") end, { desc = "Around subword" })
      vim.keymap.set({ "o", "x" }, "iS", function() textobjs.subword("inner") end, { desc = "Inside subword" })

      -- URL
      vim.keymap.set({ "o", "x" }, "au", function() textobjs.url() end, { desc = "Around URL" })

      -- Diagnostic
      vim.keymap.set({ "o", "x" }, "ad", function() textobjs.diagnostic() end, { desc = "Around diagnostic" })
    end,
  },

  {
    "m4xshen/hardtime.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      max_count = 4,
      disable_mouse = false,
      restriction_mode = "hint",
    },
  },


  {
    "tiagovla/scope.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("scope").setup({
        restore_state = true,
      })
    end,
  },

  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = "make install_jsregexp",
    lazy = true,
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    config = function()
      require("luasnip.loaders.from_vscode").lazy_load()
    end,
  },

  {
    "stevearc/resession.nvim",
    lazy = false,
    dependencies = {
      "stevearc/overseer.nvim",
    },
    opts = {
      extensions = {
        overseer = {},
      },
    },
    keys = {
      { "<leader>qs", function() require("resession").save() end, desc = "Save Session" },
      { "<leader>qr", function() require("resession").load() end, desc = "Load Session" },
      { "<leader>qd", function() require("resession").delete() end, desc = "Delete Session" },
      { "<leader>qf", function() require("resession").list() end, desc = "List Sessions" },
      { "<leader>qD", function() require("resession").save(vim.fn.getcwd(), { dir = "dirsession" }) end, desc = "Save Dir Session" },
      { "<leader>qL", function() require("resession").load(vim.fn.getcwd(), { dir = "dirsession" }) end, desc = "Load Dir Session" },
    },
  },

  {
    "tpope/vim-dadbod",
    cmd = { "DB", "DBUI" },
  },

  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection" },
    keys = {
      { "<leader>od", "<cmd>DBUIToggle<cr>", desc = "Toggle Database UI" },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_notifications = 1
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 40

      vim.g.db_ui_table_helpers = {
        mysql = {
          Count = "SELECT COUNT(1) FROM {optional_schema}{table}",
          Explain = "EXPLAIN {last_query}",
        },
        postgres = {
          Count = "SELECT COUNT(1) FROM {optional_schema}{table}",
          Explain = "EXPLAIN ANALYZE {last_query}",
        },
      }
    end,
  },

  {
    "wojciech-kulik/xcodebuild.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
    ft = { "swift", "objc", "objcpp" },
    config = function()
      require("xcodebuild").setup({
        restore_on_start = true,
        auto_save = true,
        show_build_progress_bar = true,
        logs = {
          auto_open_on_failed_build = true,
          auto_focus = true,
          auto_close_on_success = false,
          only_summary = false,
        },
        marks = {
          show_signs = true,
          success_sign = "✓",
          failure_sign = "✗",
          show_test_duration = true,
        },
        test_explorer = {
          enabled = true,
          auto_open = true,
          auto_focus = false,
        },
        code_coverage = {
          enabled = true,
        },
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "swift", "objc", "objcpp" },
        callback = function(ev)
          local opts = { buffer = ev.buf }
          vim.keymap.set("n", "<leader>cbb", "<cmd>XcodebuildBuild<cr>",
            vim.tbl_extend("force", opts, { desc = "Build" }))
          vim.keymap.set("n", "<leader>cbr", "<cmd>XcodebuildBuildRun<cr>",
            vim.tbl_extend("force", opts, { desc = "Build & Run" }))
          vim.keymap.set("n", "<leader>cbt", "<cmd>XcodebuildTest<cr>", vim.tbl_extend("force", opts, { desc = "Test" }))
          vim.keymap.set("n", "<leader>cbT", "<cmd>XcodebuildTestClass<cr>",
            vim.tbl_extend("force", opts, { desc = "Test Class" }))
          vim.keymap.set("n", "<leader>cbe", "<cmd>XcodebuildTestExplorer<cr>",
            vim.tbl_extend("force", opts, { desc = "Test Explorer" }))
          vim.keymap.set("n", "<leader>cbd", "<cmd>XcodebuildSelectDevice<cr>",
            vim.tbl_extend("force", opts, { desc = "Select Device" }))
          vim.keymap.set("n", "<leader>cbs", "<cmd>XcodebuildSelectScheme<cr>",
            vim.tbl_extend("force", opts, { desc = "Select Scheme" }))
          vim.keymap.set("n", "<leader>cbl", "<cmd>XcodebuildToggleLogs<cr>",
            vim.tbl_extend("force", opts, { desc = "Toggle Logs" }))
          vim.keymap.set("n", "<leader>cbx", "<cmd>XcodebuildCleanBuild<cr>",
            vim.tbl_extend("force", opts, { desc = "Clean Build" }))
          vim.keymap.set("n", "<leader>cbc", "<cmd>XcodebuildToggleCodeCoverage<cr>",
            vim.tbl_extend("force", opts, { desc = "Toggle Coverage" }))
        end,
      })
    end,
  },

  {
    "editorconfig/editorconfig-vim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      vim.g.EditorConfig_exclude_patterns = { 'fugitive://.*', 'scp://.*' }
      vim.g.EditorConfig_max_line_indicator = "line"
    end,
  },

  {
    "direnv/direnv.vim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.direnv_auto = 1
      vim.g.direnv_silent_load = 1

      -- Export direnv on startup and directory change
      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
        callback = function()
          if vim.fn.executable('direnv') == 1 then
            vim.cmd("DirenvExport")
          end
        end,
      })
    end,
  },

  {
    "dgagn/diagflow.nvim",
    event = "LspAttach",
    opts = {
      placement = "top",
      scope = "cursor",
      severity_colors = {
        error = "DiagnosticError",
        warning = "DiagnosticWarn",
        info = "DiagnosticInfo",
        hint = "DiagnosticHint",
      },
      format = function(diagnostic)
        local source = diagnostic.source and ("[" .. diagnostic.source .. "] ") or ""
        return source .. diagnostic.message
      end,
      gap_size = 1,
      padding_top = 0,
      padding_right = 0,
    },
  },

  {
    "ivanjermakov/troublesum.nvim",
    event = "LspAttach",
    opts = {
      enabled = true,
      severity_format = { "E", "W", "I", "H" },
      severity_highlight = {
        "DiagnosticError",
        "DiagnosticWarn",
        "DiagnosticInfo",
        "DiagnosticHint",
      },
    },
  },

  {
    "linux-cultist/venv-selector.nvim",
    dependencies = {
      "mfussenegger/nvim-dap-python",
    },
    branch = "regexp",
    ft = "python",
    cmd = "VenvSelect",
    opts = {
      search_venv_managers = true,
      search_workspace = true,
      search = true,
      dap_enabled = true,
      fd_binary_name = vim.fn.executable("fd") == 1 and "fd" or "find",
    },
    config = function(_, opts)
      require("venv-selector").setup(opts)
    end,
  },
}
