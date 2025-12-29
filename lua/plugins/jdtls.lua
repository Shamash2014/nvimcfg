return {
  "mfussenegger/nvim-jdtls",
  ft = "java",
  dependencies = {
    "mfussenegger/nvim-dap",
  },
  config = function()
    local jdtls = require("jdtls")

    local home = os.getenv("HOME")
    local workspace_dir = home .. "/.cache/jdtls-workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")

    -- Capabilities from blink.cmp
    local capabilities = require("blink.cmp").get_lsp_capabilities()

    local config = {
      cmd = {
        "jdtls",
        "-data", workspace_dir,
      },
      root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" }),
      capabilities = capabilities,
      settings = {
        java = {
          signatureHelp = { enabled = true },
          eclipse = {
            downloadSources = true,
          },
          configuration = {
            updateBuildConfiguration = "interactive",
          },
          maven = {
            downloadSources = true,
          },
          implementationsCodeLens = {
            enabled = true,
          },
          referencesCodeLens = {
            enabled = true,
          },
          references = {
            includeDecompiledSources = true,
          },
          format = {
            enabled = true,
          },
        },
      },
      init_options = {
        bundles = {},
      },
      on_attach = function(client, bufnr)
        -- Java specific keybindings
        local opts = { buffer = bufnr, silent = true }

        -- Code actions
        vim.keymap.set("n", "<localleader>o", jdtls.organize_imports,
          vim.tbl_extend("force", opts, { desc = "Organize Imports" }))
        vim.keymap.set("n", "<localleader>ev", jdtls.extract_variable,
          vim.tbl_extend("force", opts, { desc = "Extract Variable" }))
        vim.keymap.set("v", "<localleader>ev", function()
          jdtls.extract_variable(true)
        end, vim.tbl_extend("force", opts, { desc = "Extract Variable" }))
        vim.keymap.set("n", "<localleader>ec", jdtls.extract_constant,
          vim.tbl_extend("force", opts, { desc = "Extract Constant" }))
        vim.keymap.set("v", "<localleader>ec", function()
          jdtls.extract_constant(true)
        end, vim.tbl_extend("force", opts, { desc = "Extract Constant" }))
        vim.keymap.set("v", "<localleader>em", function()
          jdtls.extract_method(true)
        end, vim.tbl_extend("force", opts, { desc = "Extract Method" }))

        -- Test runner
        vim.keymap.set("n", "<localleader>tc", jdtls.test_class,
          vim.tbl_extend("force", opts, { desc = "Test Class" }))
        vim.keymap.set("n", "<localleader>tm", jdtls.test_nearest_method,
          vim.tbl_extend("force", opts, { desc = "Test Method" }))

        -- DAP will be automatically set up by nvim-jdtls if available
        jdtls.setup_dap({ hotcodereplace = "auto" })
        require("jdtls.dap").setup_dap_main_class_configs()
      end,
    }

    -- Try to find and load java-debug extension
    -- Install java-debug manually from: https://github.com/microsoft/java-debug
    -- Place the jar in ~/.tools/java-debug/
    local java_debug_path = vim.fn.glob(home .. "/.tools/java-debug/com.microsoft.java.debug.plugin-*.jar", true)
    if java_debug_path ~= "" then
      vim.list_extend(config.init_options.bundles, { java_debug_path })
    end

    -- Try to find and load java-test extension
    -- Install vscode-java-test manually from: https://github.com/microsoft/vscode-java-test
    -- Place the jars in ~/.tools/java-test/
    local java_test_path = vim.fn.glob(home .. "/.tools/java-test/*.jar", true)
    if java_test_path ~= "" then
      vim.list_extend(config.init_options.bundles, vim.split(java_test_path, "\n"))
    end

    -- Start or attach jdtls
    jdtls.start_or_attach(config)
  end,
}