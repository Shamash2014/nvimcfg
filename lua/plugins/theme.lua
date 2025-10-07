return {
  name = "custom-theme",
  dir = vim.fn.stdpath("config"),
  lazy = false,
  priority = 1000,
  config = function()
    local colors = {
      bg = "#000000",
      fg = "#ffffff",
      comment = "#808080",
      error = "#ff0000",
    }

    local highlights = {
      -- Editor
      Normal = { fg = colors.fg, bg = colors.bg },
      Comment = { fg = colors.comment, bg = colors.bg },
      Error = { fg = colors.error, bg = colors.bg },
      ErrorMsg = { fg = colors.error, bg = colors.bg },
      WarningMsg = { fg = colors.error, bg = colors.bg },

      -- All syntax elements (monotone white)
      Identifier = { fg = colors.fg, bg = colors.bg },
      Statement = { fg = colors.fg, bg = colors.bg },
      PreProc = { fg = colors.fg, bg = colors.bg },
      Type = { fg = colors.fg, bg = colors.bg },
      Special = { fg = colors.fg, bg = colors.bg },
      Underlined = { fg = colors.fg, bg = colors.bg },
      Todo = { fg = colors.fg, bg = colors.bg },
      Constant = { fg = colors.fg, bg = colors.bg },
      String = { fg = colors.fg, bg = colors.bg },
      Character = { fg = colors.fg, bg = colors.bg },
      Number = { fg = colors.fg, bg = colors.bg },
      Boolean = { fg = colors.fg, bg = colors.bg },
      Float = { fg = colors.fg, bg = colors.bg },
      Function = { fg = colors.fg, bg = colors.bg },
      Conditional = { fg = colors.fg, bg = colors.bg },
      Repeat = { fg = colors.fg, bg = colors.bg },
      Label = { fg = colors.fg, bg = colors.bg },
      Operator = { fg = colors.fg, bg = colors.bg },
      Keyword = { fg = colors.fg, bg = colors.bg },
      Exception = { fg = colors.fg, bg = colors.bg },
      Include = { fg = colors.fg, bg = colors.bg },
      Define = { fg = colors.fg, bg = colors.bg },
      Macro = { fg = colors.fg, bg = colors.bg },
      PreCondit = { fg = colors.fg, bg = colors.bg },
      StorageClass = { fg = colors.fg, bg = colors.bg },
      Structure = { fg = colors.fg, bg = colors.bg },
      Typedef = { fg = colors.fg, bg = colors.bg },
      Tag = { fg = colors.fg, bg = colors.bg },
      SpecialChar = { fg = colors.fg, bg = colors.bg },
      Delimiter = { fg = colors.fg, bg = colors.bg },
      SpecialComment = { fg = colors.comment, bg = colors.bg },
      Debug = { fg = colors.fg, bg = colors.bg },

      -- UI elements
      StatusLine = { fg = colors.fg, bg = colors.bg },
      StatusLineNC = { fg = colors.comment, bg = colors.bg },
      WinSeparator = { fg = colors.comment, bg = colors.bg },
      VertSplit = { fg = colors.comment, bg = colors.bg },
      LineNr = { fg = colors.comment, bg = colors.bg },
      CursorLineNr = { fg = colors.fg, bg = colors.bg },
      Visual = { fg = colors.bg, bg = colors.fg },
      Search = { fg = colors.bg, bg = colors.fg },
      IncSearch = { fg = colors.bg, bg = colors.fg },
      Pmenu = { fg = colors.fg, bg = colors.bg },
      PmenuSel = { fg = colors.bg, bg = colors.fg },
      PmenuSbar = { fg = colors.comment, bg = colors.bg },
      PmenuThumb = { fg = colors.fg, bg = colors.bg },
      CursorLine = { bg = colors.bg },
      CursorColumn = { bg = colors.bg },
      ColorColumn = { bg = colors.bg },
      Folded = { fg = colors.comment, bg = colors.bg },
      FoldColumn = { fg = colors.comment, bg = colors.bg },
      SignColumn = { fg = colors.fg, bg = colors.bg },
      NonText = { fg = colors.comment, bg = colors.bg },
      SpecialKey = { fg = colors.comment, bg = colors.bg },
      Title = { fg = colors.fg, bg = colors.bg },
      Directory = { fg = colors.fg, bg = colors.bg },
      ModeMsg = { fg = colors.fg, bg = colors.bg },
      MoreMsg = { fg = colors.fg, bg = colors.bg },
      Question = { fg = colors.fg, bg = colors.bg },
      WildMenu = { fg = colors.bg, bg = colors.fg },
      TabLine = { fg = colors.fg, bg = colors.bg },
      TabLineFill = { fg = colors.fg, bg = colors.bg },
      TabLineSel = { fg = colors.fg, bg = colors.bg },

      -- Diagnostics
      DiagnosticError = { fg = colors.error, bg = colors.bg },
      DiagnosticWarn = { fg = colors.fg, bg = colors.bg },
      DiagnosticInfo = { fg = colors.fg, bg = colors.bg },
      DiagnosticHint = { fg = colors.comment, bg = colors.bg },
      DiagnosticSignError = { fg = colors.error, bg = colors.bg },
      DiagnosticSignWarn = { fg = colors.fg, bg = colors.bg },
      DiagnosticSignInfo = { fg = colors.fg, bg = colors.bg },
      DiagnosticSignHint = { fg = colors.comment, bg = colors.bg },
    }

    for group, opts in pairs(highlights) do
      vim.api.nvim_set_hl(0, group, opts)
    end

    -- Treesitter highlights (all white except comments and errors)
    local treesitter_groups = {
      "@variable", "@variable.builtin", "@variable.parameter", "@variable.member",
      "@constant", "@constant.builtin", "@constant.macro", "@module", "@module.builtin",
      "@label", "@string", "@string.documentation", "@string.regexp", "@string.escape",
      "@string.special", "@string.special.symbol", "@string.special.url", "@string.special.path",
      "@character", "@character.special", "@boolean", "@number", "@number.float",
      "@type", "@type.builtin", "@type.definition", "@attribute", "@attribute.builtin",
      "@property", "@function", "@function.builtin", "@function.call", "@function.macro",
      "@function.method", "@function.method.call", "@constructor", "@operator",
      "@keyword", "@keyword.coroutine", "@keyword.function", "@keyword.operator",
      "@keyword.import", "@keyword.type", "@keyword.modifier", "@keyword.repeat",
      "@keyword.return", "@keyword.debug", "@keyword.exception", "@keyword.conditional",
      "@keyword.conditional.ternary", "@keyword.directive", "@keyword.directive.define",
      "@punctuation.delimiter", "@punctuation.bracket", "@punctuation.special",
      "@markup.strong", "@markup.italic", "@markup.strikethrough", "@markup.underline",
      "@markup.heading", "@markup.heading.1", "@markup.heading.2", "@markup.heading.3",
      "@markup.heading.4", "@markup.heading.5", "@markup.heading.6", "@markup.quote",
      "@markup.math", "@markup.link", "@markup.link.label", "@markup.link.url",
      "@markup.raw", "@markup.raw.block", "@markup.list", "@markup.list.checked",
      "@markup.list.unchecked", "@diff.plus", "@diff.minus", "@diff.delta",
      "@tag", "@tag.attribute", "@tag.delimiter"
    }

    for _, group in ipairs(treesitter_groups) do
      vim.api.nvim_set_hl(0, group, { fg = colors.fg, bg = colors.bg })
    end

    -- Comment groups
    local comment_groups = {
      "@comment", "@comment.documentation", "@comment.todo", "@comment.note"
    }

    for _, group in ipairs(comment_groups) do
      vim.api.nvim_set_hl(0, group, { fg = colors.comment, bg = colors.bg })
    end

    -- Error groups
    local error_groups = {
      "@comment.error", "@comment.warning"
    }

    for _, group in ipairs(error_groups) do
      vim.api.nvim_set_hl(0, group, { fg = colors.error, bg = colors.bg })
    end

    -- Maintain theme after other colorschemes
    vim.api.nvim_create_autocmd("ColorScheme", {
      pattern = "*",
      callback = function()
        vim.schedule(function()
          for group, opts in pairs(highlights) do
            vim.api.nvim_set_hl(0, group, opts)
          end
          for _, group in ipairs(treesitter_groups) do
            vim.api.nvim_set_hl(0, group, { fg = colors.fg, bg = colors.bg })
          end
          for _, group in ipairs(comment_groups) do
            vim.api.nvim_set_hl(0, group, { fg = colors.comment, bg = colors.bg })
          end
          for _, group in ipairs(error_groups) do
            vim.api.nvim_set_hl(0, group, { fg = colors.error, bg = colors.bg })
          end
        end)
      end,
    })
  end,
}
