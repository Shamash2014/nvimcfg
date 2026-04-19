local s = require("neowork.schema")

---@type flemma.schema.ObjectNode
return s.object({
  neowork_dir = s.string(".neowork"),
  max_visible_turns = s.integer(2),
  flush_interval_ms = s.integer(500),
  auto_scroll = s.boolean(true),
  auto_compact = s.boolean(true),
  auto_save = s.boolean(true),
  max_tool_output_lines = s.integer(200),
  schedule_poll_ms = s.integer(30000),
  provider = s.string("claude-code"),
  model = s.string(""),

  index = s.object({
    sort = s.string("status"),
    project_scope = s.string("current"),
  }),

  folds = s.object({
    frontmatter = s.boolean(true),
    thinking = s.boolean(true),
    tool_output = s.boolean(true),
    plan = s.boolean(true),
  }),

  -- Per-.chat runtime fields written by the bridge/scheduler — defaults are empty/sentinel.
  -- Listed here so the L40 frontmatter layer can write them without schema rejection.
  root = s.string(""),
  session = s.string(""),
  status = s.string(""),
  project = s.string(""),
  schedule_enabled = s.boolean(false),
  schedule_interval = s.string(""),
  schedule_command = s.string(""),
  schedule_run_count = s.integer(0),
  cost = s.string(""),
  elapsed = s.string(""),
  tokens = s.string(""),
  mode = s.string(""),
  idle = s.string(""),
})
