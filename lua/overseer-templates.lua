local overseer = require("overseer")

-- Flutter Run
overseer.register_template({
  name = "flutter run",
  builder = function()
    return {
      cmd = { "flutter" },
      args = { "run" },
      components = { "default" },
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
      components = { "default" },
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
      components = { "default" },
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
      components = { "default" },
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
      components = { "default" },
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
      components = { "default" },
    }
  end,
  condition = {
    filetype = { "dart" },
    callback = function()
      return vim.fn.filereadable("pubspec.yaml") == 1
    end,
  },
})