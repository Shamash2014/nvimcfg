return {
  {
    "stevearc/overseer.nvim",
    opts = {
      task_list = {
        direction = "bottom",
        min_height = 10,
        max_height = 20,
        default_detail = 1,
      },
      dap = false,
    },
    config = function(_, opts)
      local overseer = require("overseer")
      overseer.setup(opts)

      -- Register overseer task templates
      -- Flutter/Dart task templates
      overseer.register_template({
        name = "flutter run",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "run", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter build",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "build", "apk", "--debug" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter test",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "test" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      overseer.register_template({
        name = "flutter pub get",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "pub", "get" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("pubspec.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "flutter clean",
        builder = function()
          return {
            cmd = { "flutter" },
            args = { "clean" },
            components = { "default" },
          }
        end,
        condition = {
          filetype = { "dart" },
        },
      })

      -- Docker Compose task templates
      overseer.register_template({
        name = "docker-compose up",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "up", "-d" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose down",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "down" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose stop",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "stop" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose exec",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "exec", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "docker-compose run --rm",
        builder = function()
          local service = vim.fn.input("Service name: ")
          local command = vim.fn.input("Command: ", "/bin/bash")
          return {
            cmd = { "docker-compose" },
            args = { "run", "--rm", service, command },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      overseer.register_template({
        name = "aider --watch-files",
        builder = function()
          return {
            cmd = { "aider" },
            args = { "--watch-files" },
            components = { "default" },
          }
        end,
      })

      overseer.register_template({
        name = "docker-compose up -d --build",
        builder = function()
          return {
            cmd = { "docker-compose" },
            args = { "build", "--no-cache" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("docker-compose.yml") == 1 or vim.fn.filereadable("docker-compose.yaml") == 1
          end,
        },
      })

      -- Ionic task templates (using zsh with asdf for proper Node.js version)
      overseer.register_template({
        name = "ionic serve",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic serve" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic serve --lab",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic serve --lab" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic serve --port",
        builder = function()
          local port = vim.fn.input("Port: ", "8100")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic serve --port " .. port },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic build",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic build" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic capacitor run ios",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic capacitor run ios" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1 and vim.fn.isdirectory("ios") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic capacitor run android",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic capacitor run android" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1 and vim.fn.isdirectory("android") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic generate component",
        builder = function()
          local component_name = vim.fn.input("Component name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic generate component " .. component_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ionic generate page",
        builder = function()
          local page_name = vim.fn.input("Page name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ionic generate page " .. page_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("ionic.config.json") == 1
          end,
        },
      })

      -- Angular CLI task templates (using zsh with asdf for proper Node.js version)
      overseer.register_template({
        name = "ng serve",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng serve" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng serve --port",
        builder = function()
          local port = vim.fn.input("Port: ", "4200")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng serve --port " .. port },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng serve --open",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng serve --open" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng build",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng build" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng build --prod",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng build --configuration=production" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng test",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng test" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng test --watch=false",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng test --watch=false" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng e2e",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng e2e" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng lint",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng lint" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng generate component",
        builder = function()
          local component_name = vim.fn.input("Component name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng generate component " .. component_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng generate service",
        builder = function()
          local service_name = vim.fn.input("Service name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng generate service " .. service_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng generate module",
        builder = function()
          local module_name = vim.fn.input("Module name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng generate module " .. module_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng generate guard",
        builder = function()
          local guard_name = vim.fn.input("Guard name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng generate guard " .. guard_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "ng generate pipe",
        builder = function()
          local pipe_name = vim.fn.input("Pipe name: ")
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && ng generate pipe " .. pipe_name },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("angular.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm install",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && npm install" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm run build",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && npm run build" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      overseer.register_template({
        name = "npm run start",
        builder = function()
          return {
            cmd = { "zsh" },
            args = { "-c", "source ~/.zshrc && npm run start" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("package.json") == 1
          end,
        },
      })

      -- iOS CocoaPods task templates
      overseer.register_template({
        name = "pod install",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "install" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      overseer.register_template({
        name = "pod update",
        builder = function()
          return {
            cmd = { "pod" },
            args = { "update" },
            components = { "default" },
          }
        end,
        condition = {
          callback = function()
            return vim.fn.filereadable("Podfile") == 1 or vim.fn.filereadable("ios/Podfile") == 1
          end,
        },
      })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "*",
        callback = function()
          vim.keymap.set("t", "jk", "<C-\\><C-n>", { buffer = true, desc = "Exit terminal mode" })
        end,
      })
    end,
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>",         desc = "Run Task" },
      { "<leader>rt", "<cmd>OverseerToggle<cr>",      desc = "Toggle Overseer" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>",       desc = "Build Task" },
      { "<leader>rq", "<cmd>OverseerQuickAction<cr>", desc = "Quick Action" },
      { "<leader>ra", "<cmd>OverseerTaskAction<cr>",  desc = "Task Action" },
    },
  },
}