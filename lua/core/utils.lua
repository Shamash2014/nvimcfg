local function get_project_root(path)
  path = path or vim.fn.expand('%:p:h')
  if path == '' then
    path = vim.fn.getcwd()
  end

  return vim.fs.root(path, {
    ".git", "package.json", "Makefile", "Cargo.toml", "go.mod",
    "mix.exs", "pubspec.yaml", ".envrc", ".mise.toml", ".tool-versions",
    "flake.nix", "shell.nix", "default.nix", "justfile", "Justfile",
    "docker-compose.yml", "docker-compose.yaml", "build.gradle",
    "build.gradle.kts", "pom.xml", "CMakeLists.txt", "setup.py",
    "pyproject.toml", "tsconfig.json", "composer.json", ".project",
    ".vscode", "process-compose.yml", "process-compose.yaml",
    ".nvmrc", ".python-version", ".ruby-version", ".java-version"
  })
end

-- Auto change directory to project root
local function setup_auto_root()
  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("AutoRoot", { clear = true }),
    callback = function()
      -- Skip special buffers
      local bt = vim.bo.buftype
      if bt ~= "" and bt ~= "acwrite" then
        return
      end

      -- Get the project root for current buffer
      local root = get_project_root()
      if root and root ~= vim.fn.getcwd() then
        vim.cmd("lcd " .. vim.fn.fnameescape(root))
      end
    end,
  })
end

return {
  get_project_root = get_project_root,
  setup_auto_root = setup_auto_root,
}