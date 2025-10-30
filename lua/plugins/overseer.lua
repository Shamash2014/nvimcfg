return {
  'stevearc/overseer.nvim',
  lazy = true,
  cmd = {
    'OverseerRun',
    'OverseerToggle',
    'OverseerBuild',
    'OverseerQuickAction',
    'OverseerTaskAction',
    'OverseerInfo',
    'OverseerOpen',
    'OverseerClose',
    'OverseerLoadBundle',
    'OverseerSaveBundle',
    'OverseerDeleteBundle',
    'OverseerRunCmd',
    'OverseerClearCache',
  },
  keys = {
    { '<leader>rr', '<cmd>OverseerRun<cr>', desc = 'Run Task' },
    { '<leader>ro', '<cmd>OverseerToggle<cr>', desc = 'Toggle Overseer' },
    { '<leader>rb', '<cmd>OverseerBuild<cr>', desc = 'Build Task' },
    { '<leader>rq', '<cmd>OverseerQuickAction<cr>', desc = 'Quick Action' },
    { '<leader>ra', '<cmd>OverseerTaskAction<cr>', desc = 'Task Action' },
  },
  config = function()
    local overseer = require("overseer")

    -- Helper functions for template conditions
    local has_docker_compose = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or
          vim.fn.filereadable("docker-compose.yaml") == 1 or
          vim.fn.filereadable("compose.yml") == 1 or
          vim.fn.filereadable("compose.yaml") == 1
    end

    local has_nix = function()
      return vim.fn.filereadable("flake.nix") == 1 or
          vim.fn.filereadable("shell.nix") == 1
    end

    local has_justfile = function()
      return vim.fn.filereadable("justfile") == 1 or
          vim.fn.filereadable("Justfile") == 1
    end

    local has_process_compose = function()
      return vim.fn.filereadable("process-compose.yml") == 1 or
          vim.fn.filereadable("process-compose.yaml") == 1
    end

    local get_just_recipes = function()
      if not has_justfile() then return {} end
      local recipes = {}
      local output = vim.fn.system("just --list --unsorted 2>/dev/null")
      for line in output:gmatch("[^\r\n]+") do
        local recipe = line:match("^%s*(%S+)")
        if recipe and recipe ~= "Available" and recipe ~= "" then
          table.insert(recipes, recipe)
        end
      end
      return recipes
    end

    local has_gradle = function()
      return vim.fn.filereadable("build.gradle") == 1 or
          vim.fn.filereadable("build.gradle.kts") == 1 or
          vim.fn.filereadable("settings.gradle") == 1 or
          vim.fn.filereadable("settings.gradle.kts") == 1 or
          vim.fn.executable("./gradlew") == 1
    end

    local gradle_cmd = function()
      return vim.fn.executable("./gradlew") == 1 and "./gradlew" or "gradle"
    end

    -- Docker Compose templates
    overseer.register_template({
      name = "docker compose up",
      builder = function()
        return {
          cmd = { "docker" },
          args = { "compose", "up", "-d" },
          components = { "default" },
        }
      end,
      condition = { callback = has_docker_compose },
    })

    overseer.register_template({
      name = "docker compose down",
      builder = function()
        return {
          cmd = { "docker" },
          args = { "compose", "down" },
          components = { "default" },
        }
      end,
      condition = { callback = has_docker_compose },
    })

    overseer.register_template({
      name = "docker compose stop",
      builder = function()
        return {
          cmd = { "docker" },
          args = { "compose", "stop" },
          components = { "default" },
        }
      end,
      condition = { callback = has_docker_compose },
    })

    overseer.register_template({
      name = "docker compose exec",
      builder = function(params, cb)
        vim.ui.input({
          prompt = "Service: ",
        }, function(service)
          if not service or service == "" then
            return cb(nil)
          end
          vim.ui.input({
            prompt = "Command: ",
            default = "/bin/bash",
          }, function(cmd)
            if not cmd then
              return cb(nil)
            end
            cb({
              cmd = { "docker" },
              args = { "compose", "exec", service, cmd },
              components = { "default" },
            })
          end)
        end)
      end,
      condition = { callback = has_docker_compose },
    })

    overseer.register_template({
      name = "docker compose logs",
      builder = function(params, cb)
        vim.ui.input({
          prompt = "Service (empty for all): ",
        }, function(service)
          local args = { "compose", "logs", "-f" }
          if service and service ~= "" then
            table.insert(args, service)
          end
          cb({
            cmd = { "docker" },
            args = args,
            components = { "default" },
          })
        end)
      end,
      condition = { callback = has_docker_compose },
    })

    -- Nix templates
    overseer.register_template({
      name = "nix develop",
      builder = function()
        return {
          cmd = { "nix" },
          args = { "develop" },
          components = { "default" },
        }
      end,
      condition = { callback = has_nix },
    })

    overseer.register_template({
      name = "nix build",
      builder = function()
        return {
          cmd = { "nix" },
          args = { "build" },
          components = { "default" },
        }
      end,
      condition = { callback = has_nix },
    })

    overseer.register_template({
      name = "nix run",
      builder = function(params, cb)
        if not cb then
          return {
            cmd = { "nix" },
            args = { "run", "." },
            components = { "default" },
          }
        end
        vim.ui.input({
          prompt = "Package: ",
          default = ".",
        }, function(pkg)
          if not pkg then
            return cb(nil)
          end
          cb({
            cmd = { "nix" },
            args = { "run", pkg },
            components = { "default" },
          })
        end)
      end,
      condition = { callback = has_nix },
    })

    -- Just templates
    overseer.register_template({
      name = "just",
      builder = function(params, cb)
        local recipes = get_just_recipes()
        if #recipes == 0 then
          vim.notify("No just recipes found", vim.log.levels.WARN)
          return cb(nil)
        end
        if #recipes == 1 then
          return cb({
            cmd = { "just" },
            args = { recipes[1] },
            components = { "default" },
          })
        else
          vim.ui.select(recipes, {
            prompt = "Select just recipe:",
          }, function(choice)
            if not choice then
              return cb(nil)
            end
            cb({
              cmd = { "just" },
              args = { choice },
              components = { "default" },
            })
          end)
        end
      end,
      condition = { callback = has_justfile },
    })

    -- Process Compose templates
    overseer.register_template({
      name = "process-compose up",
      builder = function()
        return {
          cmd = { "process-compose" },
          args = { "up" },
          components = { "default" },
        }
      end,
      condition = { callback = has_process_compose },
    })

    overseer.register_template({
      name = "process-compose down",
      builder = function()
        return {
          cmd = { "process-compose" },
          args = { "down" },
          components = { "default" },
        }
      end,
      condition = { callback = has_process_compose },
    })

    -- Direnv template
    overseer.register_template({
      name = "direnv allow",
      builder = function()
        return {
          cmd = { "direnv" },
          args = { "allow" },
          components = { "default" },
        }
      end,
      condition = {
        callback = function()
          return vim.fn.filereadable(".envrc") == 1
        end,
      },
    })

    -- Gradle templates
    overseer.register_template({
      name = "gradle build",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "build" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle clean",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "clean" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle assembleDebug",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "assembleDebug" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle assembleRelease",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "assembleRelease" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle installDebug",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "installDebug" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle bundleDebug",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "bundleDebug" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle bundleRelease",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "bundleRelease" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle test",
      builder = function()
        return {
          cmd = { gradle_cmd() },
          args = { "test" },
          components = { "default" },
        }
      end,
      condition = { callback = has_gradle },
    })

    overseer.register_template({
      name = "gradle tasks",
      builder = function(params, cb)
        local output = vim.fn.system(gradle_cmd() .. " tasks --all 2>/dev/null")
        local tasks = {}
        for line in output:gmatch("[^\r\n]+") do
          local task = line:match("^(%S+)%s+%-")
          if task then
            table.insert(tasks, task)
          end
        end
        if #tasks == 0 then
          vim.notify("No gradle tasks found", vim.log.levels.WARN)
          return cb(nil)
        end
        vim.ui.select(tasks, {
          prompt = "Select gradle task:",
        }, function(choice)
          if not choice then
            return cb(nil)
          end
          cb({
            cmd = { gradle_cmd() },
            args = { choice },
            components = { "default" },
          })
        end)
      end,
      condition = { callback = has_gradle },
    })
  end,
}