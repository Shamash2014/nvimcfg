-- Check if this is an Angular project
local is_angular_project = vim.fn.filereadable(vim.fn.getcwd() .. "/angular.json") == 1

-- Start Angular Language Server for Angular HTML templates
if is_angular_project and vim.fn.executable("ngserver") == 1 and _G.lsp_config then
  local ng_probe_locations = { vim.fn.getcwd() .. "/node_modules/@angular/language-service" }

  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "angular-html",
    cmd = {
      "ngserver",
      "--stdio",
      "--tsProbeLocations",
      table.concat(ng_probe_locations, ","),
      "--ngProbeLocations",
      table.concat(ng_probe_locations, ","),
    },
    root_dir = vim.fs.root(0, { "angular.json", "project.json", ".git" }),
    filetypes = { "html" },
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
end

-- Always start HTML language server for HTML features
if vim.fn.executable("vscode-html-language-server") == 1 and _G.lsp_config then
  vim.lsp.start(vim.tbl_extend("force", _G.lsp_config, {
    name = "html",
    cmd = { "vscode-html-language-server", "--stdio" },
    root_dir = vim.fs.root(0, { "package.json", ".git" }),
    init_options = {
      configurationSection = { "html", "css", "javascript" },
      embeddedLanguages = {
        css = true,
        javascript = true,
      },
      provideFormatter = true,
      emmet = {
        showExpandedAbbreviation = "always",
        showAbbreviationSuggestions = true,
        syntaxProfiles = {
          html = "xhtml",
        },
        variables = {
          lang = "en",
        },
        excludeSuggestions = [],
        preferences = {},
      },
    },
    single_file_support = true,
  }))
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.html = { "prettier" }
end
