local M = {}

local function build_context_initial(question, options)
  if not question or question == "" then return nil end
  local lines = {}
  for _, qline in ipairs(vim.split(question, "\n", { plain = true })) do
    lines[#lines + 1] = "> " .. qline
  end
  if options and #options > 0 then
    lines[#lines + 1] = ">"
    for i, opt in ipairs(options) do
      lines[#lines + 1] = string.format("> [%d] %s", i, opt)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function open_compose_for(droid, title, finish, question, options)
  require("djinni.nowork.compose").open(droid, {
    title = title,
    alt_buf = vim.fn.bufnr("#"),
    initial = build_context_initial(question, options),
    on_submit = function(text)
      if not text then finish(nil); return end
      local cleaned = {}
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if not line:match("^%s*>") then
          cleaned[#cleaned + 1] = line
        end
      end
      local answer = vim.trim(table.concat(cleaned, "\n"))
      finish(answer ~= "" and answer or nil)
    end,
  })
end

function M.ask(droid, question, on_answer, opts)
  opts = opts or {}
  local options = opts.options or {}
  if droid and droid.log_buf and droid.log_buf.append then
    droid.log_buf:append("[ask] " .. question .. " — press `r` in log to reopen")
  end

  local resolved = false
  local trunc = question:sub(1, 80):gsub("\n", " ")
  local title = " " .. (droid and droid.id or "nowork") .. " asks: " .. trunc .. " "

  local function finish(answer)
    if resolved then return end
    if not answer or answer == "" then return end
    resolved = true
    if droid and droid.state then droid.state.pending_prompt = nil end
    on_answer(answer)
  end

  local function show()
    if #options == 0 then
      open_compose_for(droid, title, finish, question, options)
      return
    end

    local lines = { "# " .. question, "" }
    for i, opt in ipairs(options) do
      if i > 9 then break end
      lines[#lines + 1] = ("  [%d] %s"):format(i, opt)
    end
    lines[#lines + 1] = "  [c] … write custom answer"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "# Press 1–9 to pick, c for compose, <C-c>/q to cancel."

    local extra = {}
    for i, opt in ipairs(options) do
      if i > 9 then break end
      extra[tostring(i)] = function(close) close() finish(opt) end
    end
    extra["c"] = function(close) close() open_compose_for(droid, title, finish, question, options) end

    require("djinni.nowork.plan_buffer").open({
      title = title,
      footer = " 1-9 pick · c compose · <C-c>/q cancel ",
      content = table.concat(lines, "\n"),
      filetype = "markdown",
      readonly = true,
      on_submit = function() return true end,
      extra_keys = extra,
    })
  end

  if droid and droid.state then
    droid.state.pending_prompt = { kind = "question", title = question, show = show }
    require("djinni.nowork.status_panel").update()
  end
  show()
end

function M.ask_and_resume(droid, question, options)
  local droid_mod = require("djinni.nowork.droid")
  M.ask(droid, question, function(answer)
    if answer then
      droid.state.next_prompt = answer
      droid_mod._resume(droid, "next")
    else
      droid.log_buf:append("[ask] cancelled")
      droid.status = "cancelled"
      droid_mod._resume(droid, "done")
    end
  end, { options = options })
end

function M.ask_and_send(droid, question, options)
  local droid_mod = require("djinni.nowork.droid")
  M.ask(droid, question, function(answer)
    if answer and answer ~= "" then
      droid_mod.send(droid, answer)
    end
  end, { options = options })
end

return M
