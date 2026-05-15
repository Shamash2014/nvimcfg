local M = {}

local function fail(message)
  error(message, 0)
end

local function assert_truthy(value, message)
  if not value then
    fail(message)
  end
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    fail(string.format("%s\nexpected: %s\nactual: %s", message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local function current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function has_line_prefix(lines, prefix)
  for _, line in ipairs(lines) do
    if vim.startswith(line, prefix) then
      return true
    end
  end
  return false
end

local function acp_dir()
  return vim.fn.stdpath("data") .. "/acp"
end

local function reset_acp_dir()
  vim.fn.delete(acp_dir(), "rf")
  package.loaded["acp"] = nil
  package.preload["snacks"] = nil
  package.loaded["snacks"] = nil
end

local function decode_last_message(messages)
  return vim.json.decode(messages[#messages])
end

local function setup_transport_stubs()
  local messages = {}
  local holder = {}
  local old_jobstart = vim.fn.jobstart
  local old_chansend = vim.fn.chansend

  vim.fn.jobstart = function(cmd, opts)
    holder.cmd = cmd
    holder.opts = opts
    return 41
  end

  vim.fn.chansend = function(_job, payload)
    table.insert(messages, payload)
    return 1
  end

  return holder, messages, function()
    vim.fn.jobstart = old_jobstart
    vim.fn.chansend = old_chansend
  end
end

local function open_fixture(id)
  vim.cmd("AcpOpen " .. id)
  return vim.api.nvim_get_current_buf()
end

local function setup_system_stub(stdout)
  local calls = {}
  local old_system = vim.system

  vim.system = function(cmd, opts)
    table.insert(calls, { cmd = cmd, opts = opts })
    return {
      wait = function()
        return {
          code = 0,
          stdout = stdout,
          stderr = "",
        }
      end,
    }
  end

  return calls, function()
    vim.system = old_system
  end
end

local function write_file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end

local function test_zpack_bootstrap_uses_plugins_import()
  package.loaded["core.zpack"] = nil
  local recorded = {}
  local old_packadd = vim.cmd.packadd
  local old_fs_stat = vim.uv.fs_stat
  local old_pack_add = vim.pack.add

  vim.uv.fs_stat = function()
    return true
  end

  vim.cmd.packadd = function(name)
    recorded.packadd = name
  end

  vim.pack.add = function(spec, opts)
    recorded.pack_spec = spec
    recorded.pack_opts = opts
  end

  package.preload["zpack"] = function()
    return {
      setup = function(opts)
        recorded.setup = opts
      end,
    }
  end

  require("core.zpack").setup()

  assert_equal(recorded.packadd, "zpack.nvim", "zpack bootstrap should packadd installed zpack")
  assert_equal(recorded.setup.defaults.confirm, false, "zpack should disable interactive vim.pack confirms")
  assert_equal(recorded.setup.spec[1].import, "plugins", "zpack should import plugins namespace")

  package.preload["zpack"] = nil
  vim.cmd.packadd = old_packadd
  vim.uv.fs_stat = old_fs_stat
  vim.pack.add = old_pack_add
  package.loaded["core.zpack"] = nil
end

local function plugin_source(spec)
  return spec[1] or spec.src
end

local function test_plugin_specs_exist()
  local snacks = require("plugins.snacks")
  local neogit = require("plugins.neogit")
  local which_key = require("plugins.which-key")
  local treesitter = require("plugins.treesitter")
  local editing = require("plugins.editing")
  local ui = require("plugins.ui")
  local quality = require("plugins.quality")
  local quicker_spec
  local conform_spec
  local lint_spec

  assert_equal(plugin_source(snacks[1]), "folke/snacks.nvim", "snacks spec should target snacks repo")
  assert_equal(plugin_source(neogit[1]), "NeogitOrg/neogit", "neogit spec should target neogit repo")
  assert_equal(plugin_source(which_key[1]), "folke/which-key.nvim", "which-key spec should target which-key repo")
  assert_equal(plugin_source(treesitter[1]), "romus204/tree-sitter-manager.nvim", "treesitter spec should target tree-sitter-manager")
  assert_equal(plugin_source(editing[1]), "kylechui/nvim-surround", "editing spec should target nvim-surround")
  for _, spec in ipairs(ui) do
    if plugin_source(spec) == "stevearc/quicker.nvim" then
      quicker_spec = spec
      break
    end
  end
  assert_truthy(quicker_spec ~= nil, "ui spec should include quicker.nvim")

  for _, spec in ipairs(quality) do
    local source = plugin_source(spec)
    if source == "stevearc/conform.nvim" then
      conform_spec = spec
    elseif source == "mfussenegger/nvim-lint" then
      lint_spec = spec
    end
  end
  assert_truthy(conform_spec ~= nil, "quality spec should include conform.nvim")
  assert_truthy(lint_spec ~= nil, "quality spec should include nvim-lint")
end

local function test_lsp_attach_sets_buffer_keymaps()
  package.loaded["core.lsp"] = nil
  require("core.lsp").setup()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_exec_autocmds("LspAttach", {
    buffer = buf,
    modeline = false,
    data = { client_id = 1 },
  })

  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  local definition
  local code_action

  for _, map in ipairs(maps) do
    if map.lhs == "gd" then
      definition = map
    elseif map.lhs == "<leader>ca" or map.lhs == " ca" then
      code_action = map
    end
  end

  assert_truthy(definition ~= nil, "gd should be buffer-local after LspAttach")
  assert_truthy(code_action ~= nil, "code action key should be buffer-local after LspAttach")
end

local function test_theme_apply_sets_expected_highlights()
  package.loaded["config.theme"] = nil
  require("config.theme").apply()

  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local neogit_diff_add = vim.api.nvim_get_hl(0, { name = "NeogitDiffAdd", link = false })
  local snacks_title = vim.api.nvim_get_hl(0, { name = "SnacksNotifierTitleInfo", link = false })

  assert_truthy(normal.fg ~= nil, "theme should set Normal highlight")
  assert_truthy(normal.bg ~= nil, "theme should set Normal background")
  assert_truthy(neogit_diff_add.fg ~= nil, "theme should set Neogit diff add highlight")
  assert_truthy(snacks_title.bold == true, "theme should set Snacks notifier title emphasis")
end

local function test_commands_exist()
  local commands = {
    "AcpOpen",
    "AcpSend",
    "AcpApprove",
    "AcpCancel",
    "AcpHealth",
    "AcpProvider",
    "AcpAgent",
    "AcpModel",
    "AcpMode",
    "AcpCompose",
    "AcpComposeSend",
    "SessionSave",
    "SessionLoad",
  }

  for _, name in ipairs(commands) do
    assert_truthy(command_exists(name), "missing command: " .. name)
  end
end

local function test_acp_open_creates_transcript_file()
  reset_acp_dir()
  open_fixture("sample")
  local defaults = require("acp")._testing.defaults()

  local expected = acp_dir() .. "/sample.md"
  assert_equal(vim.api.nvim_buf_get_name(0), expected, "AcpOpen should edit transcript path")

  local lines = current_lines()
  assert_equal(lines[1], "---", "transcript should start with front matter")
  assert_equal(lines[2], "session_id:", "session_id header should exist")
  assert_truthy(lines[3]:match("^cwd:%s"), "cwd header should exist")
  assert_equal(lines[4], "provider: " .. defaults.provider, "default provider header should exist")
  assert_equal(lines[5], "agent: " .. defaults.agent, "default agent header should exist")
  assert_equal(lines[6], "model:", "default model header should exist")
  assert_equal(lines[7], "mode:", "default mode header should exist")
end

local function test_acp_send_initializes_creates_session_and_prompts()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  open_fixture("send-flow")

  local acp = require("acp")
  local defaults = acp._testing.defaults()
  acp.send("Fix the flaky auth tests.")

  local expected_cmd = vim.split(defaults.agent, " ", { trimempty = true })
  assert_equal(vim.fs.basename(holder.cmd[1]), expected_cmd[1], "default agent command should be used")
  if expected_cmd[2] then
    assert_equal(holder.cmd[2], expected_cmd[2], "default agent ACP arg should be used")
  end
  assert_equal(decode_last_message(messages).method, "initialize", "first message should initialize")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = {
        protocolVersion = 1,
        agentCapabilities = {},
      },
    }),
  })

  assert_equal(decode_last_message(messages).method, "session/new", "second message should create a session")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = {
        sessionId = "sess_123",
      },
    }),
  })

  local prompt = decode_last_message(messages)
  assert_equal(prompt.method, "session/prompt", "third message should send a prompt")
  assert_equal(prompt.params.sessionId, "sess_123", "prompt should use created session id")
  assert_equal(prompt.params.prompt[1].text, "Fix the flaky auth tests.", "prompt should send user text")

  local lines = current_lines()
  assert_equal(lines[11], "## user", "user section should be appended")
  assert_equal(lines[13], "Fix the flaky auth tests.", "user text should be written to transcript")

  restore()
end

local function test_permission_request_renders_and_notifies()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  local notified = {}

  package.preload["snacks"] = function()
    return {
      notify = function(message, opts)
        notified.message = message
        notified.title = opts and opts.title or nil
      end,
    }
  end

  open_fixture("permission-flow")
  local acp = require("acp")
  acp.send("Review this diff.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_perm" },
    }),
  })

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 7,
      method = "session/request_permission",
      params = {
        sessionId = "sess_perm",
        toolCall = {
          toolCallId = "call_001",
          title = "Write transcript file",
          kind = "edit",
          rawInput = { path = "lua/acp.lua" },
        },
        options = {
          { optionId = "allow-once", name = "Allow once", kind = "allow_once" },
          { optionId = "reject-once", name = "Reject", kind = "reject_once" },
        },
      },
    }),
  })

  local lines = current_lines()
  assert_truthy(vim.tbl_contains(lines, "## permission"), "permission section should be appended")
  assert_truthy(vim.tbl_contains(lines, "tool: Write transcript file"), "permission tool title should render")
  assert_truthy(vim.tbl_contains(lines, "call: call_001"), "permission tool call id should render")
  assert_truthy(vim.tbl_contains(lines, "options: allow-once, reject-once"), "permission options should render")
  assert_equal(notified.message, "ACP permission requested: Write transcript file", "snacks notification should fire")
  assert_equal(notified.title, "ACP", "snacks notification title should be ACP")

  local pending = require("acp")._testing.pending_permission(0)
  assert_equal(pending.request_id, 7, "pending permission request id should be tracked")
  assert_equal(#messages, 3, "permission request should not write an outbound response yet")

  restore()
end

local function open_permission_fixture(fixture_id, holder)
  open_fixture(fixture_id)
  local acp = require("acp")
  acp.send("Review changes.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_perm" },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 9,
      method = "session/request_permission",
      params = {
        sessionId = "sess_perm",
        toolCall = {
          toolCallId = "call_009",
          title = "Write file",
        },
        options = {
          { optionId = "allow-once", name = "Allow once", kind = "allow_once" },
          { optionId = "reject-once", name = "Reject", kind = "reject_once" },
        },
      },
    }),
  })

  return acp
end

local function stub_picker_choose(index)
  package.preload["snacks"] = function()
    return {
      picker = {
        select = function(items, _opts, on_choice)
          if on_choice then
            on_choice(items[index])
          end
        end,
      },
    }
  end
  package.loaded["snacks"] = nil
end

local function test_acp_approve_replies_to_request()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  open_permission_fixture("approve-flow", holder)

  stub_picker_choose(1)
  vim.cmd("AcpApprove")

  local response = decode_last_message(messages)
  assert_equal(response.id, 9, "approval should respond to pending request id")
  assert_equal(response.result.outcome.outcome, "selected", "approval should select an option")
  assert_equal(response.result.outcome.optionId, "allow-once", "picker first item should be allow_once")

  package.preload["snacks"] = nil
  package.loaded["snacks"] = nil
  restore()
end

local function test_acp_approve_reject_with_feedback_sends_text()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  local acp = open_permission_fixture("reject-text", holder)

  local old_input = vim.fn.input
  vim.fn.input = function()
    return "do not touch shared config"
  end

  stub_picker_choose(3)
  vim.cmd("AcpApprove")

  vim.fn.input = old_input

  local rejection = vim.json.decode(messages[#messages - 1])
  assert_equal(rejection.id, 9, "rejection should respond to pending permission request")
  assert_equal(rejection.result.outcome.outcome, "selected", "rejection should still send a selected outcome")
  assert_equal(rejection.result.outcome.optionId, "reject-once", "rejection should pick a reject option")

  local feedback = decode_last_message(messages)
  assert_equal(feedback.method, "session/prompt", "feedback text should send as a session prompt")
  assert_equal(
    feedback.params.prompt[1].text,
    "do not touch shared config",
    "feedback prompt should carry user text"
  )

  local lines = current_lines()
  assert_truthy(vim.tbl_contains(lines, "## user"), "transcript should append user feedback section")
  assert_truthy(vim.tbl_contains(lines, "do not touch shared config"), "transcript should include feedback text")

  acp.cancel()
  package.preload["snacks"] = nil
  package.loaded["snacks"] = nil
  restore()
end

local function test_acp_approve_explicit_query_skips_picker()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  open_permission_fixture("approve-explicit", holder)

  local picker_called = false
  package.preload["snacks"] = function()
    return {
      picker = {
        select = function()
          picker_called = true
        end,
      },
    }
  end
  package.loaded["snacks"] = nil

  vim.cmd("AcpApprove reject_once")
  assert_truthy(not picker_called, "explicit option query should bypass the picker")

  local response = decode_last_message(messages)
  assert_equal(response.result.outcome.optionId, "reject-once", "explicit query should resolve to the named option")

  package.preload["snacks"] = nil
  package.loaded["snacks"] = nil
  restore()
end

local function test_bufreadpost_reattaches_and_resumes()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  local path = acp_dir() .. "/resume.md"
  local defaults = require("acp")._testing.defaults()
  vim.fn.mkdir(acp_dir(), "p")
  vim.fn.writefile({
    "---",
    "session_id: sess_existing",
    "cwd: " .. vim.fn.getcwd(),
    "provider: " .. defaults.provider,
    "agent: " .. defaults.agent,
    "model:",
    "mode:",
    "---",
    "",
    "## user",
    "",
    "resume me",
  }, path)

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  assert_equal(decode_last_message(messages).method, "initialize", "opening an old transcript should initialize immediately")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = {
        protocolVersion = 1,
        agentCapabilities = {
          sessionCapabilities = {
            resume = {},
          },
        },
      },
    }),
  })

  local resume = decode_last_message(messages)
  assert_equal(resume.method, "session/resume", "existing transcript should resume when supported")
  assert_equal(resume.params.sessionId, "sess_existing", "resume should use stored session id")

  restore()
end

local function test_acp_send_range_sends_selected_text()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "alpha",
    "beta",
    "gamma",
    "delta",
  })

  vim.cmd("2,3AcpSend")
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_range" },
    }),
  })

  local prompt = decode_last_message(messages)
  assert_equal(prompt.params.prompt[1].text, "beta\ngamma", "range send should join selected lines with newlines")

  restore()
end

local function test_acp_send_bang_uses_git_diff()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  local calls, restore_system = setup_system_stub("diff --git a/lua/acp.lua b/lua/acp.lua")
  open_fixture("diff-flow")

  vim.cmd("AcpSend! staged")
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_diff" },
    }),
  })

  local git_diff_call
  for _, call in ipairs(calls) do
    if table.concat(call.cmd, " ") == "git diff --cached --no-ext-diff" then
      git_diff_call = call
      break
    end
  end
  assert_truthy(git_diff_call ~= nil, "bang send should capture staged diff")
  local prompt = decode_last_message(messages)
  assert_equal(prompt.params.prompt[1].text, "diff --git a/lua/acp.lua b/lua/acp.lua", "bang send should forward diff text")

  restore_system()
  restore()
end

local function test_acp_provider_switch_updates_header()
  reset_acp_dir()
  open_fixture("provider-switch")

  require("acp").set_provider("codex")

  local lines = current_lines()
  assert_equal(lines[4], "provider: codex", "provider should update in header")
  assert_equal(lines[5], "agent: codex-acp", "provider should update agent command")
  assert_equal(lines[2], "session_id:", "provider switch should clear persisted session id")
end

local function test_acp_health_lists_provider_status()
  reset_acp_dir()
  local defaults = require("acp")._testing.defaults()
  vim.cmd("AcpHealth")

  local lines = current_lines()
  assert_equal(lines[1], "ACP health", "health buffer should have title")
  assert_truthy(
    vim.tbl_contains(lines, "default provider: " .. defaults.provider),
    "health should show resolved default provider"
  )
  assert_truthy(
    vim.tbl_contains(lines, "default agent: " .. defaults.agent),
    "health should show resolved default agent"
  )
  assert_truthy(has_line_prefix(lines, "- claude: claude-code-acp "), "health should list claude provider")
  assert_truthy(has_line_prefix(lines, "- codex: codex-acp "), "health should list codex provider")
  assert_truthy(has_line_prefix(lines, "- opencode: opencode acp "), "health should list opencode provider")
end

local function test_acp_provider_picker_filters_missing_providers()
  reset_acp_dir()

  local old_providers = vim.g.nvim3_acp_providers
  vim.g.nvim3_acp_providers = {
    claude = "claude-code-acp",
    codex = "codex-acp",
    opencode = "opencode acp",
    broken = "definitely-not-installed-xyz-123",
  }

  local picked
  local old_snacks = package.loaded["snacks"]
  package.preload["snacks"] = function()
    return {
      picker = {
        select = function(items, _opts, on_choice)
          picked = items
          if on_choice then
            on_choice(items[1])
          end
        end,
      },
    }
  end
  package.loaded["snacks"] = nil

  vim.cmd("AcpProvider")

  local names = {}
  for _, item in ipairs(picked or {}) do
    table.insert(names, item.name)
  end
  assert_truthy(not vim.tbl_contains(names, "broken"), "provider picker should exclude missing 'broken' provider")
  assert_truthy(#names > 0, "provider picker should include at least one installed provider")

  vim.g.nvim3_acp_providers = old_providers
  package.preload["snacks"] = nil
  package.loaded["snacks"] = old_snacks
end

local function test_acp_model_switch_uses_session_config_option()
  reset_acp_dir()
  local _, messages, restore = setup_transport_stubs()
  local bufnr = open_fixture("model-switch")
  local acp = require("acp")
  local state = acp._testing.state(bufnr)

  state.job = 41
  state.ready = true
  state.session_id = "sess_model"
  state.config_options = {
    {
      id = "model",
      category = "model",
      currentValue = "sonnet",
      options = {
        { value = "sonnet", name = "Sonnet" },
        { value = "opus", name = "Opus" },
      },
    },
  }

  acp.set_model("opus", bufnr)

  local payload = decode_last_message(messages)
  assert_equal(payload.method, "session/set_config_option", "model switch should use session/set_config_option")
  assert_equal(payload.params.configId, "model", "model config option id should be used")
  assert_equal(payload.params.value, "opus", "requested model should be sent")

  restore()
end

local function test_acp_mode_switch_uses_legacy_session_set_mode()
  reset_acp_dir()
  local _, messages, restore = setup_transport_stubs()
  local bufnr = open_fixture("mode-switch")
  local acp = require("acp")
  local state = acp._testing.state(bufnr)

  state.job = 41
  state.ready = true
  state.session_id = "sess_mode"
  state.modes = {
    currentModeId = "ask",
    availableModes = {
      { id = "ask", name = "Ask" },
      { id = "code", name = "Code" },
    },
  }

  acp.set_mode("code", bufnr)

  local payload = decode_last_message(messages)
  assert_equal(payload.method, "session/set_mode", "mode switch should use legacy session/set_mode when config options are absent")
  assert_equal(payload.params.modeId, "code", "requested mode should be sent")

  restore()
end

local function test_acp_compose_sends_full_buffer()
  reset_acp_dir()
  local holder, messages, restore = setup_transport_stubs()
  local transcript_buf = open_fixture("compose-send")

  local acp = require("acp")
  acp.open_compose()
  assert_equal(vim.api.nvim_get_current_buf(), transcript_buf, "open_compose on transcript should not split")

  vim.api.nvim_buf_set_lines(transcript_buf, -1, -1, false, {
    "first line",
    "",
    "second line",
  })

  acp.send_compose(transcript_buf)

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_compose" },
    }),
  })

  local prompt = decode_last_message(messages)
  assert_equal(prompt.params.prompt[1].text, "first line\n\nsecond line", "compose region should send typed lines")

  local lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
  assert_truthy(vim.tbl_contains(lines, "## user"), "transcript should gain a ## user header after send")
  assert_truthy(vim.tbl_contains(lines, "first line"), "transcript should keep typed content under header")
  assert_truthy(vim.tbl_contains(lines, "second line"), "transcript should keep multi-line typed content")

  restore()
end

local function test_compose_buffer_has_insert_send_mapping()
  reset_acp_dir()
  local _, _, restore = setup_transport_stubs()
  local transcript_buf = open_fixture("compose-insert-map")

  require("acp").open_compose()
  assert_equal(vim.api.nvim_get_current_buf(), transcript_buf, "open_compose should stay on transcript")

  local insert_map
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(transcript_buf, "i")) do
    if map.lhs == "<C-CR>" then
      insert_map = map
      break
    end
  end

  assert_truthy(insert_map ~= nil, "transcript buffer should bind <C-CR> in insert mode after open_compose")

  restore()
end

local function test_neogit_filetype_gets_send_mapping()
  reset_acp_dir()
  vim.cmd("enew")
  vim.bo.filetype = "NeogitStatus"
  vim.api.nvim_exec_autocmds("FileType", { pattern = "NeogitStatus", modeline = false })

  local review_map = vim.fn.maparg("a", "n", false, true)
  local visual_review_map = vim.fn.maparg("a", "x", false, true)
  assert_equal(review_map.buffer, 1, "neogit status buffer should get native normal-mode review mapping")
  assert_equal(visual_review_map.buffer, 1, "neogit status buffer should get native visual-mode review mapping")
end

local function test_tool_call_and_diff_are_rendered()
  reset_acp_dir()
  local holder, _, restore = setup_transport_stubs()
  open_fixture("tool-call-flow")
  local acp = require("acp")
  acp.send("Show me the patch.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_tool" },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        update = {
          sessionUpdate = "tool_call",
          toolCallId = "call_diff",
          title = "write_file",
          status = "pending",
          rawInput = {
            path = "lua/acp.lua",
            diff = "@@ -1,2 +1,2 @@\n-old\n+new",
          },
        },
      },
    }),
  })

  local lines = current_lines()
  assert_truthy(vim.tbl_contains(lines, "### tool"), "tool section should render as level-3 heading")
  assert_truthy(vim.tbl_contains(lines, "title: write_file"), "tool title should render")
  assert_truthy(vim.tbl_contains(lines, "path: lua/acp.lua"), "tool path should render")
  assert_truthy(vim.tbl_contains(lines, "diff:"), "tool diff header should render")
  assert_truthy(vim.tbl_contains(lines, "@@ -1,2 +1,2 @@"), "tool diff body should render")

  restore()
end

local function test_streaming_chunks_append_to_single_section()
  reset_acp_dir()
  local holder, _, restore = setup_transport_stubs()
  open_fixture("stream-flow")
  local acp = require("acp")
  acp.send("Stream please.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_stream" },
    }),
  })

  local function chunk(text)
    holder.opts.on_stdout(41, {
      vim.json.encode({
        jsonrpc = "2.0",
        method = "session/update",
        params = {
          update = {
            sessionUpdate = "agent_message_chunk",
            content = { text = text },
          },
        },
      }),
    })
  end

  chunk("Hello")
  chunk(", ")
  chunk("world!")
  chunk("\nNext line.")

  local lines = current_lines()
  local count = 0
  for _, l in ipairs(lines) do
    if l == "## assistant" then
      count = count + 1
    end
  end
  assert_equal(count, 1, "streaming chunks should share one assistant section")
  assert_truthy(vim.tbl_contains(lines, "Hello, world!"), "chunks should concatenate into one line")
  assert_truthy(vim.tbl_contains(lines, "Next line."), "newline inside chunk should start a new buffer line")

  restore()
end

local function test_tool_call_command_array_renders()
  reset_acp_dir()
  local holder, _, restore = setup_transport_stubs()
  open_fixture("cmd-array-flow")
  local acp = require("acp")
  acp.send("Run it.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_cmd" },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        update = {
          sessionUpdate = "tool_call",
          toolCallId = "call_run",
          title = "execute",
          rawInput = {
            command = { "git", "status", "--short" },
          },
        },
      },
    }),
  })

  local lines = current_lines()
  assert_truthy(vim.tbl_contains(lines, "### tool"), "tool call should use a level-3 heading")
  assert_truthy(vim.tbl_contains(lines, "command: git status --short"), "array command should join with spaces")

  restore()
end

local function test_tool_call_update_uses_level_three_heading()
  reset_acp_dir()
  local holder, _, restore = setup_transport_stubs()
  open_fixture("tool-update-flow")
  local acp = require("acp")
  acp.send("Show tool progress.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_tool_update" },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        update = {
          sessionUpdate = "tool_call_update",
          toolCallId = "call_progress",
          title = "execute",
          status = "running",
          content = {
            {
              type = "content",
              content = { text = "step 1/2" },
            },
          },
        },
      },
    }),
  })

  local lines = current_lines()
  assert_truthy(vim.tbl_contains(lines, "### tool update"), "tool updates should use a level-3 heading")
  assert_truthy(vim.tbl_contains(lines, "status: running"), "tool updates should render status")
  assert_truthy(vim.tbl_contains(lines, "step 1/2"), "tool updates should append streamed content")

  restore()
end

local function test_statusline_reports_active_sessions_and_mode()
  reset_acp_dir()
  package.loaded["core.statusline"] = nil
  package.loaded["acp"] = nil

  local acp = require("acp")
  local statusline = require("core.statusline")

  assert_equal(acp.active_session_count(), 0, "no buffers should mean no active sessions")

  local bufnr = open_fixture("statusline-flow")
  local state = acp._testing.state(bufnr)
  state.session_id = "sess_alive"
  state.modes = { currentModeId = "plan", availableModes = {} }

  assert_equal(acp.active_session_count(), 1, "tracked transcript with session_id should count")
  assert_equal(acp.current_mode(bufnr), "plan", "current_mode should return active modeId")

  local rendered = statusline.render()
  assert_truthy(rendered:find("acp:plan", 1, true) ~= nil, "statusline should include acp mode")
  assert_truthy(rendered:find("sess:1", 1, true) ~= nil, "statusline should include active session count")
end

local function test_env_setup_registers_envsync_command()
  package.loaded["core.env"] = nil
  local old_executable = vim.fn.executable
  local old_system = vim.system
  vim.fn.executable = function()
    return 0
  end
  vim.system = function()
    return {
      wait = function()
        return { code = 1, stdout = "", stderr = "" }
      end,
    }
  end

  require("core.env").setup()

  vim.fn.executable = old_executable
  vim.system = old_system

  assert_truthy(command_exists("EnvSync"), "env.setup should register :EnvSync command")
end

local function test_env_sync_applies_direnv_and_mise_values()
  package.loaded["core.env"] = nil
  local env_mod = require("core.env")

  local old_executable = vim.fn.executable
  local old_system = vim.system
  local seen_commands = {}

  vim.fn.executable = function(bin)
    if bin == "mise" or bin == "direnv" then
      return 1
    end
    return 0
  end

  vim.system = function(cmd, _opts)
    table.insert(seen_commands, cmd[1])
    local payload = "{}"
    if cmd[1] == "mise" then
      payload = '{"MISE_VAR":"42"}'
    elseif cmd[1] == "direnv" then
      payload = '{"DIRENV_VAR":"hello"}'
    end
    return {
      wait = function()
        return { code = 0, stdout = payload, stderr = "" }
      end,
    }
  end

  vim.env.MISE_VAR = nil
  vim.env.DIRENV_VAR = nil

  env_mod.sync()

  assert_equal(vim.env.MISE_VAR, "42", "env.sync should apply mise vars")
  assert_equal(vim.env.DIRENV_VAR, "hello", "env.sync should apply direnv vars")
  assert_truthy(vim.tbl_contains(seen_commands, "mise"), "env.sync should invoke mise")
  assert_truthy(vim.tbl_contains(seen_commands, "direnv"), "env.sync should invoke direnv")

  vim.env.MISE_VAR = nil
  vim.env.DIRENV_VAR = nil
  vim.fn.executable = old_executable
  vim.system = old_system
end

local function test_leader_ot_opens_terminal()
  local maps = vim.api.nvim_get_keymap("n")
  local terminal_map
  for _, map in ipairs(maps) do
    if map.lhs == " ot" then
      terminal_map = map
      break
    end
  end
  assert_truthy(terminal_map ~= nil, "<leader>ot should be bound in normal mode")
  assert_truthy(
    (terminal_map.desc or ""):lower():find("terminal", 1, true) ~= nil,
    "<leader>ot mapping should describe terminal"
  )
end

local function test_tool_call_status_updates_in_place()
  reset_acp_dir()
  local holder, _, restore = setup_transport_stubs()
  open_fixture("tool-status-flow")
  local acp = require("acp")
  acp.send("Run it.")

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 1,
      result = { protocolVersion = 1, agentCapabilities = {} },
    }),
  })
  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      id = 2,
      result = { sessionId = "sess_inplace" },
    }),
  })

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        update = {
          sessionUpdate = "tool_call",
          toolCallId = "call_inplace",
          title = "execute",
          status = "pending",
          rawInput = { command = { "git", "status" } },
        },
      },
    }),
  })

  holder.opts.on_stdout(41, {
    vim.json.encode({
      jsonrpc = "2.0",
      method = "session/update",
      params = {
        update = {
          sessionUpdate = "tool_call_update",
          toolCallId = "call_inplace",
          status = "completed",
          content = {
            { type = "content", content = { text = "ok" } },
          },
        },
      },
    }),
  })

  local lines = current_lines()
  local heading_count = 0
  for _, l in ipairs(lines) do
    if l == "### tool" or l == "### tool update" then
      heading_count = heading_count + 1
    end
  end
  assert_equal(heading_count, 1, "tool call should not duplicate its heading after an update")
  assert_truthy(vim.tbl_contains(lines, "status: completed"), "tool status should advance to completed")
  assert_truthy(not vim.tbl_contains(lines, "status: pending"), "pending status should be replaced in place")
  assert_truthy(
    vim.tbl_contains(lines, "### tool output (call_inplace)"),
    "tool output should be appended in a labelled section"
  )
  assert_truthy(vim.tbl_contains(lines, "ok"), "tool output content should be rendered")

  restore()
end

local function test_sessions_load_picks_from_saved_files()
  package.loaded["core.sessions"] = nil
  local sessions = require("core.sessions")

  local dir = vim.fn.stdpath("state") .. "/sessions"
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")

  local newer = dir .. "/" .. ("%home%alice%proj-a"):gsub("/", "%%") .. ".vim"
  local older = dir .. "/" .. ("%home%alice%proj-b"):gsub("/", "%%") .. ".vim"
  vim.fn.writefile({ "\" session a" }, newer)
  vim.fn.writefile({ "\" session b" }, older)
  vim.uv.fs_utime(older, 1000, 1000)
  vim.uv.fs_utime(newer, 2000, 2000)

  local sourced
  local old_cmd = vim.cmd
  vim.cmd = setmetatable({}, {
    __call = function(_, c)
      if type(c) == "string" and c:match("^source ") then
        sourced = c:match("^source%s+(.+)$")
        return
      end
      return old_cmd(c)
    end,
  })

  local picked
  package.preload["snacks"] = function()
    return {
      picker = {
        select = function(items, _opts, on_choice)
          picked = items
          if on_choice then
            on_choice(items[1])
          end
        end,
      },
    }
  end
  package.loaded["snacks"] = nil

  sessions.load()

  vim.cmd = old_cmd
  package.preload["snacks"] = nil
  package.loaded["snacks"] = nil

  assert_truthy(picked and #picked == 2, "picker should receive both sessions")
  assert_equal(picked[1].path, newer, "newer session should be first")
  assert_truthy(sourced ~= nil and sourced:match("proj%-a"), "selected session should be sourced")
end

local function test_project_sync_sets_tab_cwd_from_repo_directory()
  package.loaded["core.project"] = nil
  local project = require("core.project")
  local repo = vim.fn.tempname()
  local nested = repo .. "/apps/mobile"
  local original = vim.fn.getcwd()

  vim.fn.mkdir(repo .. "/.git", "p")
  vim.fn.mkdir(nested, "p")
  repo = vim.uv.fs_realpath(repo) or repo
  nested = vim.uv.fs_realpath(nested) or nested

  project.sync(nested)

  assert_equal(vim.fn.getcwd(), repo, "sync should move tab cwd to the repo root for directory paths")

  vim.cmd.tcd(original)
  vim.fn.delete(repo, "rf")
end

local function test_project_setup_updates_tab_cwd_on_bufenter()
  package.loaded["core.project"] = nil
  local project = require("core.project")
  local repo = vim.fn.tempname()
  local file = repo .. "/lua/demo.lua"
  local original = vim.fn.getcwd()

  vim.fn.mkdir(repo .. "/.git", "p")
  write_file(file, { "return true" })
  repo = vim.uv.fs_realpath(repo) or repo
  file = vim.uv.fs_realpath(file) or file

  project.setup()
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  assert_equal(vim.fn.getcwd(), repo, "opening a file inside a repo should set tab cwd to the repo root")

  vim.cmd.tcd(original)
  vim.cmd("enew")
  vim.fn.delete(repo, "rf")
end

function M.run()
  local tests = {
    test_zpack_bootstrap_uses_plugins_import,
    test_plugin_specs_exist,
    test_lsp_attach_sets_buffer_keymaps,
    test_theme_apply_sets_expected_highlights,
    test_commands_exist,
    test_acp_open_creates_transcript_file,
    test_acp_send_initializes_creates_session_and_prompts,
    test_permission_request_renders_and_notifies,
    test_acp_approve_replies_to_request,
    test_acp_approve_reject_with_feedback_sends_text,
    test_acp_approve_explicit_query_skips_picker,
    test_bufreadpost_reattaches_and_resumes,
    test_acp_send_range_sends_selected_text,
    test_acp_send_bang_uses_git_diff,
    test_acp_provider_switch_updates_header,
    test_acp_health_lists_provider_status,
    test_acp_provider_picker_filters_missing_providers,
    test_acp_model_switch_uses_session_config_option,
    test_acp_mode_switch_uses_legacy_session_set_mode,
    test_acp_compose_sends_full_buffer,
    test_compose_buffer_has_insert_send_mapping,
    test_neogit_filetype_gets_send_mapping,
    test_tool_call_and_diff_are_rendered,
    test_streaming_chunks_append_to_single_section,
    test_tool_call_command_array_renders,
    test_tool_call_update_uses_level_three_heading,
    test_tool_call_status_updates_in_place,
    test_statusline_reports_active_sessions_and_mode,
    test_env_setup_registers_envsync_command,
    test_env_sync_applies_direnv_and_mise_values,
    test_leader_ot_opens_terminal,
    test_sessions_load_picks_from_saved_files,
    test_project_sync_sets_tab_cwd_from_repo_directory,
    test_project_setup_updates_tab_cwd_on_bufenter,
  }

  for _, test in ipairs(tests) do
    test()
  end

  print("OK")
end

return M
