local M = {}

M.role = {
  user = "@You",
  agent = "@Djinni",
  system = "@System",
  separator = "---",
}

M.event = {
  plan = "plan",
  tool_call = "tool_call",
  tool_call_update = "tool_call_update",
  agent_message = "agent_message",
  agent_message_chunk = "agent_message_chunk",
  agent_thought_chunk = "agent_thought_chunk",
  user_message = "user_message",
  usage_update = "usage_update",
  result = "result",
  modes = "modes",
  current_mode_update = "current_mode_update",
  available_commands_update = "available_commands_update",
  config_option_update = "config_option_update",
}

M.plan_status = {
  pending = "pending",
  in_progress = "in_progress",
  completed = "completed",
  failed = "failed",
}

M.session_status = {
  idle = "idle",
  running = "running",
  ready = "ready",
  awaiting = "awaiting",
  review = "review",
}

return M
