return {
  name = "code_repl",
  dir = vim.fn.stdpath("config") .. "/lua/code_repl",
  config = function()
    require("code_repl").setup({
      auto_start = true,
      persist_per_project = true,
      result_max_length = 100,
      show_errors_inline = true,
      auto_detect_language = true,
      default_repl = "bash",
    })
    
    -- Create user commands
    require("code_repl").create_commands()
  end,
  keys = {
    -- Generic evaluation (auto-detects language)
    { "<leader>re", function() require("code_repl").evaluate_line() end, 
      mode = "n", desc = "Evaluate line in REPL" },
    
    { "<leader>r<space>", function() require("code_repl").evaluate_line() end, 
      mode = "n", desc = "Evaluate line in REPL" },
    
    -- Evaluate selection
    { "<leader>re", function() require("code_repl").evaluate_selection() end, 
      mode = "v", desc = "Evaluate selection in REPL" },
    
    { "<leader>r<space>", function() require("code_repl").evaluate_selection() end,
      mode = "v", desc = "Evaluate selection in REPL" },

    -- Restart REPL
    { "<leader>rr", function() require("code_repl").restart_repl() end,
      mode = "n", desc = "Restart REPL" },
    
    -- Kill REPL
    { "<leader>rk", function() require("code_repl").kill_repl() end, 
      mode = "n", desc = "Kill REPL" },
    
    -- Show status
    { "<leader>rs", function() require("code_repl").status() end, 
      mode = "n", desc = "Show REPL status" },
  },
  cmd = {
    "REPLEval",
    "REPLEvalVisual",
    "REPLToggle",
    "REPLRestart",
    "REPLKill",
    "REPLStatus",
  },
}
