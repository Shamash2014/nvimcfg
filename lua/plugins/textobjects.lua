return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  branch = "main",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = "nvim-treesitter/nvim-treesitter",
  config = function()
    local select = require("nvim-treesitter-textobjects.select")
    local move = require("nvim-treesitter-textobjects.move")
    local swap = require("nvim-treesitter-textobjects.swap")
    local ts_repeat_move = require("nvim-treesitter-textobjects.repeatable_move")

    require("nvim-treesitter-textobjects").setup({
      select = { lookahead = true },
      move = { set_jumps = true },
    })

    -- Repeatable move: ; goes to the direction you were moving
    vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat_move.repeat_last_move)
    vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat_move.repeat_last_move_opposite)
    vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat_move.builtin_f_expr, { expr = true })
    vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat_move.builtin_F_expr, { expr = true })
    vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat_move.builtin_t_expr, { expr = true })
    vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat_move.builtin_T_expr, { expr = true })

    -- Select textobjects
    for _, mapping in ipairs({
      { "af", "@function.outer" },
      { "if", "@function.inner" },
      { "ac", "@class.outer" },
      { "ic", "@class.inner" },
      { "ab", "@block.outer" },
      { "ib", "@block.inner" },
      { "al", "@call.outer" },
      { "il", "@call.inner" },
      { "aa", "@parameter.outer" },
      { "ia", "@parameter.inner" },
    }) do
      vim.keymap.set({ "x", "o" }, mapping[1], function()
        select.select_textobject(mapping[2], "textobjects")
      end)
    end

    -- Swap parameters
    vim.keymap.set("n", "<leader>a", function()
      swap.swap_next("@parameter.inner")
    end)
    vim.keymap.set("n", "<leader>A", function()
      swap.swap_previous("@parameter.inner")
    end)

    -- Move to next/prev textobject
    for _, mapping in ipairs({
      { "]f", "goto_next_start", "@function.outer" },
      { "]c", "goto_next_start", "@class.outer" },
      { "]b", "goto_next_start", "@block.outer" },
      { "]a", "goto_next_start", "@parameter.outer" },
      { "]F", "goto_next_end", "@function.outer" },
      { "]C", "goto_next_end", "@class.outer" },
      { "]B", "goto_next_end", "@block.outer" },
      { "]A", "goto_next_end", "@parameter.outer" },
      { "[f", "goto_previous_start", "@function.outer" },
      { "[c", "goto_previous_start", "@class.outer" },
      { "[b", "goto_previous_start", "@block.outer" },
      { "[a", "goto_previous_start", "@parameter.outer" },
      { "[F", "goto_previous_end", "@function.outer" },
      { "[C", "goto_previous_end", "@class.outer" },
      { "[B", "goto_previous_end", "@block.outer" },
      { "[A", "goto_previous_end", "@parameter.outer" },
    }) do
      vim.keymap.set({ "n", "x", "o" }, mapping[1], function()
        move[mapping[2]](mapping[3], "textobjects")
      end)
    end
  end,
}
