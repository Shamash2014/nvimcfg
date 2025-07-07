local overseer = require("overseer")

-- Flutter Run
overseer.register_template({
  name = "flutter run",
  builder = function()
    return {
      strategy = "terminal",
      cmd = { "flutter" },
      args = { "run" },
      components = {
        "default",
        {
          "on_output_parse",
          problem_matcher = {
            {
              owner = "flutter",
              pattern = {
                {
                  regexp = "^(.*):(\\d+):(\\d+):\\s+(warning|error):\\s+(.*)$",
                  file = 1,
                  line = 2,
                  column = 3,
                  severity = 4,
                  message = 5,
                },
              },
            },
          },
        },
        "on_exit_set_status",
        "on_complete_notify",
      },
      env = {
        FLUTTER_ROOT = vim.fn.expand("$FLUTTER_ROOT"),
      },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})

-- Flutter Build
overseer.register_template({
  name = "flutter build",
  builder = function()
    local target = vim.fn.input("Build target (apk/ios/web): ", "apk")
    if target == "" then
      target = "apk"
    end
    
    return {
      cmd = { "flutter" },
      args = { "build", target },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
      env = {
        FLUTTER_ROOT = vim.fn.expand("$FLUTTER_ROOT"),
      },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})

-- Flutter Test
overseer.register_template({
  name = "flutter test",
  builder = function()
    return {
      cmd = { "flutter" },
      args = { "test" },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
      env = {
        FLUTTER_ROOT = vim.fn.expand("$FLUTTER_ROOT"),
      },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})

-- Dart Run
overseer.register_template({
  name = "dart run",
  builder = function()
    local file = vim.fn.expand("%:p")
    if vim.fn.fnamemodify(file, ":e") ~= "dart" then
      file = vim.fn.input("Dart file to run: ", "lib/main.dart")
    end
    
    return {
      cmd = { "dart" },
      args = { "run", file },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    filetype = { "dart" },
  },
})

-- Flutter Clean
overseer.register_template({
  name = "flutter clean",
  builder = function()
    return {
      cmd = { "flutter" },
      args = { "clean" },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
      env = {
        FLUTTER_ROOT = vim.fn.expand("$FLUTTER_ROOT"),
      },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})

-- Flutter Pub Get
overseer.register_template({
  name = "flutter pub get",
  builder = function()
    return {
      cmd = { "flutter" },
      args = { "pub", "get" },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
      env = {
        FLUTTER_ROOT = vim.fn.expand("$FLUTTER_ROOT"),
      },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})

-- Docker Compose Up
overseer.register_template({
  name = "docker compose up",
  builder = function()
    local args = { "compose", "up" }
    local detached = vim.fn.confirm("Run in detached mode?", "&Yes\n&No", 2)
    if detached == 1 then
      table.insert(args, "-d")
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or 
             vim.fn.filereadable("docker-compose.yaml") == 1 or
             vim.fn.filereadable("compose.yml") == 1 or
             vim.fn.filereadable("compose.yaml") == 1
    end,
  },
})

-- Docker Compose Down
overseer.register_template({
  name = "docker compose down",
  builder = function()
    local args = { "compose", "down" }
    local volumes = vim.fn.confirm("Remove volumes?", "&Yes\n&No", 2)
    if volumes == 1 then
      table.insert(args, "-v")
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or 
             vim.fn.filereadable("docker-compose.yaml") == 1 or
             vim.fn.filereadable("compose.yml") == 1 or
             vim.fn.filereadable("compose.yaml") == 1
    end,
  },
})

-- Docker Compose Build
overseer.register_template({
  name = "docker compose build",
  builder = function()
    local args = { "compose", "build" }
    local no_cache = vim.fn.confirm("Build without cache?", "&Yes\n&No", 2)
    if no_cache == 1 then
      table.insert(args, "--no-cache")
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or 
             vim.fn.filereadable("docker-compose.yaml") == 1 or
             vim.fn.filereadable("compose.yml") == 1 or
             vim.fn.filereadable("compose.yaml") == 1
    end,
  },
})

-- Docker Compose Logs
overseer.register_template({
  name = "docker compose logs",
  builder = function()
    local service = vim.fn.input("Service name (leave empty for all): ")
    local args = { "compose", "logs", "-f" }
    if service ~= "" then
      table.insert(args, service)
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or 
             vim.fn.filereadable("docker-compose.yaml") == 1 or
             vim.fn.filereadable("compose.yml") == 1 or
             vim.fn.filereadable("compose.yaml") == 1
    end,
  },
})

-- Docker Run
overseer.register_template({
  name = "docker run",
  builder = function()
    local image = vim.fn.input("Docker image: ")
    if image == "" then
      vim.notify("Image name is required", vim.log.levels.ERROR)
      return nil
    end
    
    local args = { "run", "--rm" }
    
    -- Interactive mode
    local interactive = vim.fn.confirm("Run in interactive mode?", "&Yes\n&No", 1)
    if interactive == 1 then
      table.insert(args, "-it")
    end
    
    -- Port mapping
    local port = vim.fn.input("Port mapping (e.g., 8080:80, leave empty for none): ")
    if port ~= "" then
      table.insert(args, "-p")
      table.insert(args, port)
    end
    
    -- Volume mapping
    local volume = vim.fn.input("Volume mapping (e.g., ./data:/app/data, leave empty for none): ")
    if volume ~= "" then
      table.insert(args, "-v")
      table.insert(args, volume)
    end
    
    -- Environment variables
    local env = vim.fn.input("Environment variables (e.g., KEY=value, leave empty for none): ")
    if env ~= "" then
      table.insert(args, "-e")
      table.insert(args, env)
    end
    
    -- Container name
    local name = vim.fn.input("Container name (leave empty for auto): ")
    if name ~= "" then
      table.insert(args, "--name")
      table.insert(args, name)
    end
    
    table.insert(args, image)
    
    -- Command to run inside container
    local cmd = vim.fn.input("Command to run (leave empty for default): ")
    if cmd ~= "" then
      for part in cmd:gmatch("%S+") do
        table.insert(args, part)
      end
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.executable("docker") == 1
    end,
  },
})

-- Docker Build
overseer.register_template({
  name = "docker build",
  builder = function()
    local args = { "build" }
    
    -- Tag
    local tag = vim.fn.input("Image tag: ")
    if tag ~= "" then
      table.insert(args, "-t")
      table.insert(args, tag)
    end
    
    -- No cache
    local no_cache = vim.fn.confirm("Build without cache?", "&Yes\n&No", 2)
    if no_cache == 1 then
      table.insert(args, "--no-cache")
    end
    
    -- Build context
    local context = vim.fn.input("Build context (default: .): ", ".")
    table.insert(args, context)
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("Dockerfile") == 1
    end,
  },
})

-- Docker Exec
overseer.register_template({
  name = "docker exec",
  builder = function()
    local container = vim.fn.input("Container name/ID: ")
    if container == "" then
      vim.notify("Container name/ID is required", vim.log.levels.ERROR)
      return nil
    end
    
    local args = { "exec", "-it", container }
    
    local cmd = vim.fn.input("Command to execute (default: /bin/bash): ", "/bin/bash")
    for part in cmd:gmatch("%S+") do
      table.insert(args, part)
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.executable("docker") == 1
    end,
  },
})

-- Docker Compose Exec
overseer.register_template({
  name = "docker compose exec",
  builder = function()
    local service = vim.fn.input("Service name: ")
    if service == "" then
      vim.notify("Service name is required", vim.log.levels.ERROR)
      return nil
    end
    
    local args = { "compose", "exec", service }
    
    local cmd = vim.fn.input("Command to execute (default: /bin/bash): ", "/bin/bash")
    for part in cmd:gmatch("%S+") do
      table.insert(args, part)
    end
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.filereadable("docker-compose.yml") == 1 or 
             vim.fn.filereadable("docker-compose.yaml") == 1 or
             vim.fn.filereadable("compose.yml") == 1 or
             vim.fn.filereadable("compose.yaml") == 1
    end,
  },
})

-- Terminal Arbitrary Command
overseer.register_template({
  name = "terminal command",
  builder = function()
    local cmd = vim.fn.input("Command to run: ")
    if cmd == "" then
      vim.notify("Command is required", vim.log.levels.ERROR)
      return nil
    end
    
    local parts = {}
    for part in cmd:gmatch("%S+") do
      table.insert(parts, part)
    end
    
    local command = table.remove(parts, 1)
    
    return {
      cmd = { command },
      args = parts,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return true -- Always available
    end,
  },
})

-- Shell Script Runner
overseer.register_template({
  name = "shell script",
  builder = function()
    local script = vim.fn.input("Script to run: ")
    if script == "" then
      vim.notify("Script is required", vim.log.levels.ERROR)
      return nil
    end
    
    local interpreter = "bash"
    local extension = script:match("%.(%w+)$")
    
    if extension == "py" then
      interpreter = "python"
    elseif extension == "js" then
      interpreter = "node"
    elseif extension == "rb" then
      interpreter = "ruby"
    elseif extension == "sh" then
      interpreter = "bash"
    elseif extension == "zsh" then
      interpreter = "zsh"
    end
    
    return {
      cmd = { interpreter },
      args = { script },
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return true -- Always available
    end,
  },
})

-- Docker Logs
overseer.register_template({
  name = "docker logs",
  builder = function()
    local container = vim.fn.input("Container name/ID: ")
    if container == "" then
      vim.notify("Container name/ID is required", vim.log.levels.ERROR)
      return nil
    end
    
    local args = { "logs", "-f", container }
    
    return {
      cmd = { "docker" },
      args = args,
      components = {
        "default",
        "on_exit_set_status",
        "on_complete_notify",
      },
    }
  end,
  condition = {
    callback = function()
      return vim.fn.executable("docker") == 1
    end,
  },
})