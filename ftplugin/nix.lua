-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'NixBuild',
  function()
    vim.cmd('terminal nix-build')
  end, { desc = 'Build Nix expression' })

vim.api.nvim_buf_create_user_command(0, 'NixShell',
  function()
    vim.cmd('terminal nix-shell')
  end, { desc = 'Enter Nix shell' })

vim.api.nvim_buf_create_user_command(0, 'NixFormat',
  function()
    vim.cmd('terminal nixfmt %')
  end, { desc = 'Format Nix file' })

vim.api.nvim_buf_create_user_command(0, 'NixCheck',
  function()
    vim.cmd('terminal nix-instantiate --parse %')
  end, { desc = 'Check Nix syntax' })

vim.api.nvim_buf_create_user_command(0, 'NixEval',
  function()
    vim.cmd('terminal nix-instantiate --eval %')
  end, { desc = 'Evaluate Nix expression' })

local project_root = vim.fs.root(0, {"flake.nix"})
if project_root then
  vim.api.nvim_buf_create_user_command(0, 'NixFlakeBuild',
    function()
      vim.cmd('terminal nix build')
    end, { desc = 'Build Nix flake' })

  vim.api.nvim_buf_create_user_command(0, 'NixFlakeCheck',
    function()
      vim.cmd('terminal nix flake check')
    end, { desc = 'Check Nix flake' })

  vim.api.nvim_buf_create_user_command(0, 'NixDevelop',
    function()
      vim.cmd('terminal nix develop')
    end, { desc = 'Enter Nix flake development shell' })
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("nixfmt") == 1 then
  conform.formatters_by_ft.nix = { "nixfmt" }
end
