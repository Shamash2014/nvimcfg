local jdtls_bin = vim.fn.expand('~/.tools/jdtls/bin/jdtls')

if vim.fn.executable(jdtls_bin) == 0 then
  vim.notify("jdtls not found at ~/.tools/jdtls/bin/jdtls", vim.log.levels.WARN)
  return
end

local jdtls = require('jdtls')
local home = os.getenv('HOME')
local workspace_dir = home .. '/.cache/jdtls/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

local config = {
  name = "jdtls",
  cmd = { jdtls_bin, '-data', workspace_dir },
  root_dir = vim.fs.root(0, {'.git', 'mvnw', 'gradlew', 'pom.xml', 'build.gradle'}),
  settings = {
    java = {
      eclipse = { downloadSources = true },
      configuration = { updateBuildConfiguration = "interactive" },
      maven = { downloadSources = true },
      implementationsCodeLens = { enabled = true },
      referencesCodeLens = { enabled = true },
      references = { includeDecompiledSources = true },
      inlayHints = {
        parameterNames = { enabled = "all" },
      },
      format = { enabled = true },
    },
  },
  init_options = {
    bundles = {}
  },
}

jdtls.start_or_attach(config)
