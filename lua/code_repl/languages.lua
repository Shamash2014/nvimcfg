local M = {}

-- Language-specific REPL configurations
local configs = {
  python = {
    cmd = "python3",
    args = { "-i" },
    prompt = ">>>",
    multiline_prompt = "...",
    env = {},
    result_pattern = "^(?!>>>|\\[\\^])(.+)$",
  },
  
  javascript = {
    cmd = "node",
    args = { "-i" },
    prompt = ">",
    env = {},
  },
  
  typescript = {
    cmd = "ts-node",
    args = {},
    prompt = ">",
    env = {},
  },
  
  lua = {
    cmd = "lua",
    args = { "-i" },
    prompt = ">",
    env = {},
  },
  
  go = {
    cmd = "gore",
    args = {},
    prompt = ">",
    env = {},
  },
  
  bash = {
    cmd = "bash",
    args = {},
    prompt = "$",
    env = {},
  },
  
  sh = {
    cmd = "sh",
    args = {},
    prompt = "$",
    env = {},
  },
  
  ruby = {
    cmd = "irb",
    args = { "--inf-ruby-mode" },
    prompt = ">>",
    env = {},
  },
  
  php = {
    cmd = "php",
    args = { "-a" },
    prompt = ">",
    env = {},
  },
  
  perl = {
    cmd = "perl",
    args = { "-d", "-e", "0", "-e", "$|++;}" },
    prompt = ">",
    env = {},
  },
}

function M.get(language)
  return configs[language]
end

function M.list()
  local list = {}
  for lang, config in pairs(configs) do
    table.insert(list, {
      language = lang,
      cmd = config.cmd,
      available = vim.fn.executable(config.cmd) == 1,
    })
  end
  return list
end

function M.available()
  local available = {}
  for lang, config in pairs(configs) do
    if vim.fn.executable(config.cmd) == 1 then
      table.insert(available, lang)
    end
  end
  return available
end

return M
