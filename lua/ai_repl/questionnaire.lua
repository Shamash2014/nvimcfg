local M = {}

local render = require("ai_repl.render")

local function get_output_buf(proc)
  if proc and proc.ui and proc.ui.chat_buf then
    local buf = proc.ui.chat_buf
    if vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
  end
  return nil
end

local state = {
  active = false,
  questions = {},
  current_index = 1,
  answers = {},
  proc = nil,
  buf = nil,
  awaiting_text_input = false,
  keymaps_set = false,
  on_complete = nil,
}

local function clear_state()
  state.active = false
  state.questions = {}
  state.current_index = 1
  state.answers = {}
  state.proc = nil
  state.buf = nil
  state.awaiting_text_input = false
  state.on_complete = nil
end

local function get_current_question()
  return state.questions[state.current_index]
end

local function is_last_question()
  return state.current_index >= #state.questions
end

local function has_options(question)
  return question.options and #question.options > 0
end

local function format_answers_for_response()
  local lines = {}
  for i, _ in ipairs(state.questions) do
    local answer = state.answers[i]
    if answer then
      table.insert(lines, string.format("Q%d: %s", i, answer))
    else
      table.insert(lines, string.format("Q%d: [skipped]", i))
    end
  end
  return table.concat(lines, "\n")
end

function M.render_current()
  if not state.active or not state.buf then return end
  if not vim.api.nvim_buf_is_valid(state.buf) then
    clear_state()
    return
  end

  local q = get_current_question()
  if not q then
    M.finish()
    return
  end

  local total = #state.questions
  local current = state.current_index
  local is_optional = q.optional == true

  local lines = {
    "",
    string.format("┌─ ❓ Questions [%d/%d] ─────────────────────────", current, total),
    "│",
    "│ " .. (q.question or "Question"),
    "│",
  }

  if has_options(q) then
    for i, opt in ipairs(q.options) do
      local label = type(opt) == "table" and opt.label or opt
      table.insert(lines, string.format("│   %d. %s", i, label))
    end
    table.insert(lines, "│")
  else
    table.insert(lines, "│ (Type your answer at the prompt below)")
    table.insert(lines, "│")
  end

  local nav = "│ [B]ack"
  if is_optional then
    nav = nav .. "  [S]kip"
  end
  nav = nav .. "  [C]ancel"
  table.insert(lines, nav)
  table.insert(lines, "└──────────────────────────────────────────────")
  table.insert(lines, "")

  render.append_content(state.buf, lines)

  if has_options(q) then
    state.awaiting_text_input = false
    vim.schedule(function()
      M.show_select_ui(q)
    end)
  else
    state.awaiting_text_input = true
    vim.schedule(function()
      local win = vim.fn.bufwinid(state.buf)
      if win ~= -1 then
        render.goto_prompt(state.buf, win)
      end
    end)
  end
end

function M.show_select_ui(question)
  local labels = {}
  for _, opt in ipairs(question.options) do
    local label = type(opt) == "table" and opt.label or opt
    table.insert(labels, label)
  end

  vim.ui.select(labels, {
    prompt = question.question or "Select:",
    format_item = function(item) return item end,
  }, function(choice)
    if choice then
      M.handle_select(choice)
    end
  end)
end

function M.start(proc, questions, on_complete)
  if not questions or #questions == 0 then return end

  clear_state()
  state.active = true
  state.questions = questions
  state.current_index = 1
  state.answers = {}
  state.proc = proc
  state.buf = get_output_buf(proc)
  state.on_complete = on_complete

  M.setup_keymaps()
  M.render_current()
end

function M.setup_keymaps()
  if not state.buf or state.keymaps_set then return end

  local opts = { buffer = state.buf, silent = true, nowait = true }

  for _, binding in ipairs({
    { "b", M.back },
    { "s", M.skip },
    { "c", M.cancel },
  }) do
    local key, fn = binding[1], binding[2]
    for _, k in ipairs({ key, key:upper() }) do
      vim.keymap.set("n", k, function()
        if state.active then fn() end
      end, opts)
    end
  end

  state.keymaps_set = true
end

function M.handle_select(choice)
  if not state.active then return end

  state.answers[state.current_index] = choice
  render.append_content(state.buf, { "[✓] Selected: " .. choice })
  M.next()
end

function M.handle_text_input(text)
  if not state.active or not state.awaiting_text_input then return false end

  if not text or text == "" then
    local q = get_current_question()
    if q and q.optional then
      M.skip()
    end
    return true
  end

  state.answers[state.current_index] = text
  state.awaiting_text_input = false
  render.append_content(state.buf, { "[✓] Answer: " .. text })
  M.next()
  return true
end

function M.next()
  if not state.active then return end

  if is_last_question() then
    M.finish()
    return
  end

  state.current_index = state.current_index + 1
  M.render_current()
end

function M.back()
  if not state.active then return end

  if state.current_index <= 1 then
    render.append_content(state.buf, { "[!] Already at first question" })
    return
  end

  state.current_index = state.current_index - 1
  state.awaiting_text_input = false
  M.render_current()
end

function M.skip()
  if not state.active then return end

  local q = get_current_question()
  if not q then return end

  if not q.optional then
    render.append_content(state.buf, { "[!] This question cannot be skipped" })
    return
  end

  state.answers[state.current_index] = nil
  render.append_content(state.buf, { "[→] Skipped" })
  M.next()
end

function M.cancel()
  if not state.active then return end

  render.append_content(state.buf, {
    "",
    "[✗] Questionnaire cancelled",
    "",
  })

  local on_complete = state.on_complete
  clear_state()

  if on_complete then
    on_complete("[User cancelled the questionnaire]")
  end
end

function M.finish()
  if not state.active then return end

  local response = format_answers_for_response()

  render.append_content(state.buf, {
    "",
    "┌─ ✓ Questionnaire Complete ─────────────────",
    "│",
  })

  for i, q in ipairs(state.questions) do
    local answer = state.answers[i] or "[skipped]"
    local short_q = (q.question or ("Q" .. i)):sub(1, 30)
    if #(q.question or "") > 30 then short_q = short_q .. "..." end
    render.append_content(state.buf, {
      string.format("│ %d. %s", i, short_q),
      string.format("│    → %s", answer),
    })
  end

  render.append_content(state.buf, {
    "│",
    "└─────────────────────────────────────────────",
    "",
  })

  local on_complete = state.on_complete
  clear_state()

  if on_complete then
    on_complete(response)
  end
end

function M.is_active()
  return state.active
end

function M.is_awaiting_input()
  return state.active and state.awaiting_text_input
end

function M.get_state()
  return state
end

return M
