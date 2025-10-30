-- Check if this is an Angular project
local is_angular_project = vim.fn.filereadable(vim.fn.getcwd() .. "/angular.json") == 1

-- Start Angular Language Server for Angular projects
if is_angular_project and vim.fn.executable("ngserver") == 1 and _G.lsp_config then
  -- Get the TypeScript lib path from node_modules
  local ts_lib_path = vim.fn.getcwd() .. "/node_modules/typescript/lib"
  local ng_probe_locations = { vim.fn.getcwd() .. "/node_modules/@angular/language-service" }

  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "angular",
    cmd = {
      "ngserver",
      "--stdio",
      "--tsProbeLocations",
      table.concat(ng_probe_locations, ","),
      "--ngProbeLocations",
      table.concat(ng_probe_locations, ","),
    },
    root_dir = vim.fs.root(0, { "angular.json", "project.json", ".git" }),
    filetypes = { "typescript", "html", "typescriptreact", "typescript.tsx" },
    on_new_config = function(new_config, new_root_dir)
      new_config.cmd = {
        "ngserver",
        "--stdio",
        "--tsProbeLocations",
        new_root_dir .. "/node_modules",
        "--ngProbeLocations",
        new_root_dir .. "/node_modules",
      }
    end,
  }))
else
  -- Use vtsls for non-Angular TypeScript projects
  if vim.fn.executable("vtsls") == 1 and _G.lsp_config then
    vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
      name = "vtsls",
      cmd = { "vtsls", "--stdio" },
      root_dir = vim.fs.root(0, { "package.json", "tsconfig.json", "jsconfig.json", ".git" }),
    }))
  end
end

if vim.fn.executable("node") == 1 then
  local ok, dap = pcall(require, 'dap')
  if not ok then return end

  if not dap.adapters.node2 then
    dap.adapters.node2 = {
      type = 'executable',
      command = 'node',
      args = { vim.fn.stdpath('data') .. '/mason/packages/node-debug2-adapter/out/src/nodeDebug.js' },
    }
  end

  if not dap.configurations.typescript then
    dap.configurations.typescript = {
      {
        type = 'node2',
        request = 'launch',
        name = 'Launch file',
        program = '${file}',
        cwd = vim.fn.getcwd(),
        sourceMaps = true,
        protocol = 'inspector',
        console = 'integratedTerminal',
      },
      {
        type = 'node2',
        request = 'attach',
        name = 'Attach',
        processId = require('dap.utils').pick_process,
        cwd = vim.fn.getcwd(),
      },
    }
  end
end

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("eslint") == 1 then
  lint.linters_by_ft.typescript = { "eslint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.typescript = { "prettier" }
end
