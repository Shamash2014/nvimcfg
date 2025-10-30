-- Elixir Expert Configuration
local expert_ls_found = false

-- Expert LSP support
local expert_cmd = vim.fn.expand("~/.tools/expert/expert")
if vim.fn.executable(expert_cmd) == 1 and _G.lsp_config then
  expert_ls_found = true
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "expert",
    cmd = { expert_cmd },
    root_dir = vim.fs.root(0, { "mix.exs", ".git" }),
    filetypes = { "elixir", "eelixir", "heex", "surface" },
    root_markers = { "mix.exs", ".git" },
    settings = {
      expert = {
        dialyzerEnabled = true,
        mixEnv = "prod",
        signatures = true,
        hover = true,
        symbols = true,
        completion = {
          enable = true,
          autoImport = true,
        },
      },
    },
  }))

  if not expert_ls_found then
    vim.notify("expert-ls not found at " .. expert_cmd, ". Install with: mix escript.install expert_ls", vim.log.levels.WARN)
  end
end

-- Mix task runner with completion
if vim.fn.executable("mix") == 1 then
  vim.api.nvim_create_user_command("Mix", function(opts)
    local f = opts.fargs and opts.fargs[1] or ""
    if f == "" then
      local tasks = {
        "compile", "test", "run", "deps.compile", "deps.get", "format", "credo", "ecto.install",
        "ecto.clean", "phx.digest", "phx.server", "phx.gen.cert", "release", "audit",
        "escript.build", "inch.report", "xref", "coveralls.html", "docs"
      }
      if #tasks > 0 then
        vim.ui.select(tasks, {
          prompt = "Mix tasks:",
          format_item = function(item) return "• " .. item end,
        }, function(choice)
          if choice then
            vim.cmd("silent! mix " .. choice)
          end
        end)
      else
        vim.notify("No mix tasks found", vim.log.levels.WARN)
      end
    else
      vim.cmd("silent! mix " .. table.concat(opts.fargs, " "))
    end
  end, {
    nargs = "*",
    complete = function()
      return vim.fn.system(
      "mix help --commands 2>/dev/null | grep -E '^[[:space:]]+(.+)' | sed 's/^[[:space:]]*//' | sort"):gmatch(
      "[^\r\n]+")
    end,
    desc = "Run Mix task",
  })
end
-- Formatting with conform
local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("mix") == 1 then
  conform.formatters_by_ft.elixir = { "mix" }
end

-- Essential keymaps
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("ElixirExpert", {}),
  pattern = "*.ex,*.exs,*.heex",
  callback = function()
    vim.keymap.set("n", "<leader>ec", "<cmd>lua vim.cmd('Mix compile')<CR>", { buffer = true, desc = "Compile Elixir" })
  end,
})
