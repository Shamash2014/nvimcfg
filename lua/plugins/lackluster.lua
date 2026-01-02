-- Lackluster monochrome theme
return {
  "slugbyte/lackluster.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    local lackluster = require("lackluster")

    lackluster.setup({
      -- Override ALL colors to be pure grayscale only
      tweak_color = {
        lack = "#808080",      -- Main gray
        luster = "#CCCCCC",    -- Light gray
        orange = "#999999",    -- Gray
        yellow = "#888888",    -- Gray
        green = "#777777",     -- Gray (no green!)
        blue = "#AAAAAA",      -- Gray (no blue!)
        red = "#FF4444",       -- Keep red ONLY for errors
      },
      -- Make all syntax elements use grays (these default to blue!)
      tweak_syntax = {
        string = "#AAAAAA",
        string_escape = "#999999",     -- Default: blue
        comment = "#CCCCCC",           -- Comments brighter
        builtin = "#BBBBBB",           -- Default: blue
        type = "#AAAAAA",
        keyword = "#DDDDDD",           -- Keywords brighter
        keyword_return = "#DDDDDD",    -- Default: blue
        keyword_exception = "#CCCCCC", -- Default: blue
      },
    })

    vim.cmd.colorscheme("lackluster")

    -- Force override any remaining color highlights
    vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#5f9f5f" })
    vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#9f9f5f" })
    vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = "#9f5f5f" })
    vim.api.nvim_set_hl(0, "DiffAdd", { bg = "#1a2f1a" })
    vim.api.nvim_set_hl(0, "DiffChange", { bg = "#2f2f1a" })
    vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#2f1a1a" })
    vim.api.nvim_set_hl(0, "DiffText", { bg = "#3f3f2a" })
    vim.api.nvim_set_hl(0, "Directory", { fg = "#DDDDDD", bold = true })

    -- Override any plugin colors that might be green/blue
    vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#999999" })
    vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#CCCCCC" })
    vim.api.nvim_set_hl(0, "NeoTreeGitAdded", { fg = "#5f9f5f" })
    vim.api.nvim_set_hl(0, "NeoTreeGitModified", { fg = "#9f9f5f" })
    vim.api.nvim_set_hl(0, "TelescopeSelection", { bg = "#404040" })
    vim.api.nvim_set_hl(0, "TelescopeMatching", { fg = "#FFFFFF", bold = true })

    -- Override ALL Treesitter highlights to monochrome
    local treesitter_groups = {
      -- Comments
      ["@comment"] = { fg = "#CCCCCC", italic = true },
      ["@comment.documentation"] = { fg = "#CCCCCC", italic = true },

      -- Strings
      ["@string"] = { fg = "#AAAAAA" },
      ["@string.regex"] = { fg = "#AAAAAA" },
      ["@string.escape"] = { fg = "#999999" },
      ["@string.special"] = { fg = "#AAAAAA" },
      ["@character"] = { fg = "#AAAAAA" },
      ["@character.special"] = { fg = "#999999" },

      -- Constants
      ["@constant"] = { fg = "#BBBBBB" },
      ["@constant.builtin"] = { fg = "#BBBBBB" },
      ["@number"] = { fg = "#BBBBBB" },
      ["@boolean"] = { fg = "#BBBBBB" },
      ["@float"] = { fg = "#BBBBBB" },

      -- Functions
      ["@function"] = { fg = "#DDDDDD", bold = true },
      ["@function.builtin"] = { fg = "#CCCCCC" },
      ["@function.call"] = { fg = "#CCCCCC" },
      ["@method"] = { fg = "#DDDDDD", bold = true },
      ["@method.call"] = { fg = "#CCCCCC" },
      ["@constructor"] = { fg = "#DDDDDD" },

      -- Keywords
      ["@keyword"] = { fg = "#DDDDDD", bold = true },
      ["@keyword.function"] = { fg = "#DDDDDD", bold = true },
      ["@keyword.operator"] = { fg = "#CCCCCC" },
      ["@keyword.return"] = { fg = "#DDDDDD", bold = true },
      ["@conditional"] = { fg = "#DDDDDD" },
      ["@repeat"] = { fg = "#DDDDDD" },
      ["@exception"] = { fg = "#CCCCCC" },
      ["@label"] = { fg = "#BBBBBB" },

      -- Variables
      ["@variable"] = { fg = "#C0C0C0" },
      ["@variable.builtin"] = { fg = "#BBBBBB" },
      ["@variable.member"] = { fg = "#C0C0C0" },
      ["@parameter"] = { fg = "#C0C0C0" },
      ["@field"] = { fg = "#C0C0C0" },
      ["@property"] = { fg = "#C0C0C0" },

      -- Types
      ["@type"] = { fg = "#BBBBBB" },
      ["@type.builtin"] = { fg = "#BBBBBB" },
      ["@type.qualifier"] = { fg = "#BBBBBB" },
      ["@type.definition"] = { fg = "#BBBBBB" },

      -- Operators and punctuation
      ["@operator"] = { fg = "#999999" },
      ["@punctuation"] = { fg = "#999999" },
      ["@punctuation.bracket"] = { fg = "#999999" },
      ["@punctuation.delimiter"] = { fg = "#999999" },
      ["@punctuation.special"] = { fg = "#999999" },

      -- Tags (HTML/JSX)
      ["@tag"] = { fg = "#CCCCCC" },
      ["@tag.attribute"] = { fg = "#AAAAAA" },
      ["@tag.delimiter"] = { fg = "#999999" },

      -- Namespaces
      ["@namespace"] = { fg = "#BBBBBB" },
      ["@include"] = { fg = "#CCCCCC" },

      -- Attributes
      ["@attribute"] = { fg = "#999999" },
      ["@decorator"] = { fg = "#999999" },
      ["@annotation"] = { fg = "#999999" },

      -- Text/Markup
      ["@text"] = { fg = "#C0C0C0" },
      ["@text.title"] = { fg = "#DDDDDD", bold = true },
      ["@text.emphasis"] = { fg = "#CCCCCC", italic = true },
      ["@text.underline"] = { fg = "#CCCCCC", underline = true },
      ["@text.uri"] = { fg = "#AAAAAA", underline = true },

      -- Markup
      ["@markup.heading"] = { fg = "#DDDDDD", bold = true },
      ["@markup.strong"] = { fg = "#CCCCCC", bold = true },
      ["@markup.italic"] = { fg = "#CCCCCC", italic = true },
      ["@markup.link"] = { fg = "#AAAAAA", underline = true },
      ["@markup.raw"] = { fg = "#AAAAAA" },
      ["@markup.list"] = { fg = "#BBBBBB" },
    }

    -- Apply all treesitter overrides
    for group, opts in pairs(treesitter_groups) do
      vim.api.nvim_set_hl(0, group, opts)
    end

    -- Add language-specific overrides for common problematic highlights
    local languages = {"typescript", "javascript", "tsx", "jsx", "dart", "go", "python", "rust", "lua", "vim", "yaml", "json", "html", "css"}

    for _, lang in ipairs(languages) do
      -- Strings (often green)
      vim.api.nvim_set_hl(0, "@string." .. lang, { fg = "#AAAAAA" })
      vim.api.nvim_set_hl(0, "@string.regex." .. lang, { fg = "#AAAAAA" })

      -- Functions (often blue)
      vim.api.nvim_set_hl(0, "@function." .. lang, { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "@method." .. lang, { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "@function.call." .. lang, { fg = "#CCCCCC" })
      vim.api.nvim_set_hl(0, "@method.call." .. lang, { fg = "#CCCCCC" })

      -- Keywords (might be colored)
      vim.api.nvim_set_hl(0, "@keyword." .. lang, { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "@keyword.function." .. lang, { fg = "#DDDDDD", bold = true })

      -- Types (often blue/green)
      vim.api.nvim_set_hl(0, "@type." .. lang, { fg = "#BBBBBB" })
      vim.api.nvim_set_hl(0, "@type.builtin." .. lang, { fg = "#BBBBBB" })

      -- Constants
      vim.api.nvim_set_hl(0, "@constant." .. lang, { fg = "#BBBBBB" })
      vim.api.nvim_set_hl(0, "@boolean." .. lang, { fg = "#BBBBBB" })
      vim.api.nvim_set_hl(0, "@number." .. lang, { fg = "#BBBBBB" })

      -- Variables
      vim.api.nvim_set_hl(0, "@variable." .. lang, { fg = "#C0C0C0" })
      vim.api.nvim_set_hl(0, "@parameter." .. lang, { fg = "#C0C0C0" })
      vim.api.nvim_set_hl(0, "@field." .. lang, { fg = "#C0C0C0" })
      vim.api.nvim_set_hl(0, "@property." .. lang, { fg = "#C0C0C0" })
    end

    -- Special YAML overrides (YAML keys are often blue/green)
    vim.api.nvim_set_hl(0, "@field.yaml", { fg = "#DDDDDD", bold = true })
    vim.api.nvim_set_hl(0, "@property.yaml", { fg = "#DDDDDD", bold = true })
    vim.api.nvim_set_hl(0, "@label.yaml", { fg = "#DDDDDD", bold = true })
    vim.api.nvim_set_hl(0, "yamlKey", { fg = "#DDDDDD", bold = true })
    vim.api.nvim_set_hl(0, "yamlBlockMappingKey", { fg = "#DDDDDD", bold = true })
    vim.api.nvim_set_hl(0, "yamlFlowMappingKey", { fg = "#DDDDDD", bold = true })

    -- Force override after colorscheme loads (delayed)
    vim.defer_fn(function()
      -- Re-apply critical overrides after everything loads
      vim.api.nvim_set_hl(0, "@string", { fg = "#AAAAAA" })
      vim.api.nvim_set_hl(0, "@function", { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "@keyword", { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "@type", { fg = "#BBBBBB" })
      vim.api.nvim_set_hl(0, "@constant", { fg = "#BBBBBB" })

      -- Common problematic groups
      vim.api.nvim_set_hl(0, "String", { fg = "#AAAAAA" })
      vim.api.nvim_set_hl(0, "Function", { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "Keyword", { fg = "#DDDDDD", bold = true })
      vim.api.nvim_set_hl(0, "Type", { fg = "#BBBBBB" })
      vim.api.nvim_set_hl(0, "Constant", { fg = "#BBBBBB" })

      -- Diagnostics that might have colors
      vim.api.nvim_set_hl(0, "DiagnosticHint", { fg = "#999999" })
      vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#AAAAAA" })
      vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = "#CCCCCC" })
    end, 100)
  end,
}