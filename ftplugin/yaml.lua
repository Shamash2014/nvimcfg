-- Contextual commands for command palette
vim.api.nvim_buf_create_user_command(0, 'YAMLLint',
  function()
    vim.cmd('terminal yamllint %')
  end, { desc = 'Lint YAML file' })

vim.api.nvim_buf_create_user_command(0, 'YAMLFormat',
  function()
    vim.cmd('terminal npx prettier --write %')
  end, { desc = 'Format YAML file' })

vim.api.nvim_buf_create_user_command(0, 'YAMLValidate',
  function()
    vim.cmd('terminal python -c "import yaml; yaml.safe_load(open(\'%\'))"')
  end, { desc = 'Validate YAML syntax' })

-- Kubernetes-specific commands if this looks like a k8s file (optimized detection)
local function is_kubernetes_file()
  -- Only read first 10 lines to avoid performance issues
  local ok, first_lines = pcall(vim.api.nvim_buf_get_lines, 0, 0, 10, false)
  if not ok then return false end

  for _, line in ipairs(first_lines) do
    if line:match('apiVersion:') or line:match('kind:') then
      return true
    end
  end
  return false
end

local is_kubernetes = is_kubernetes_file()

if is_kubernetes then
  vim.api.nvim_buf_create_user_command(0, 'KubectlApply',
    function()
      vim.cmd('terminal kubectl apply -f %')
    end, { desc = 'Apply Kubernetes manifest' })

  vim.api.nvim_buf_create_user_command(0, 'KubectlValidate',
    function()
      vim.cmd('terminal kubectl apply --dry-run=client -f %')
    end, { desc = 'Validate Kubernetes manifest' })
end

local ok, lint = pcall(require, 'lint')
if ok and vim.fn.executable("yamllint") == 1 then
  lint.linters_by_ft.yaml = { "yamllint" }
end

local ok_conform, conform = pcall(require, 'conform')
if ok_conform and vim.fn.executable("prettier") == 1 then
  conform.formatters_by_ft.yaml = { "prettier" }
end
