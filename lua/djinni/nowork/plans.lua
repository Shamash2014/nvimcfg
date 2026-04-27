local M = {}

local function plans_dir(cwd)
  return (cwd or vim.fn.getcwd()) .. "/.nowork/plans"
end

function M.dir(cwd)
  return plans_dir(cwd)
end

function M.list(cwd)
  local dir = plans_dir(cwd)
  if vim.fn.isdirectory(dir) == 0 then return {} end
  local files = vim.fn.glob(dir .. "/*.md", false, true)
  table.sort(files, function(a, b) return a > b end)
  return files
end

function M.is_plan(path, cwd)
  local dir = plans_dir(cwd)
  if not path or path == "" then return false end
  return path:sub(1, #dir) == dir and path:sub(#dir + 1, #dir + 1) == "/"
end

function M.read(path)
  if vim.fn.filereadable(path) == 0 then return nil end
  return table.concat(vim.fn.readfile(path), "\n")
end

function M.new_empty(cwd)
  cwd = cwd or vim.fn.getcwd()
  vim.fn.mkdir(plans_dir(cwd), "p")
  local stamp = os.date("%Y%m%d-%H%M%S")
  local path = plans_dir(cwd) .. "/" .. stamp .. ".md"
  vim.fn.writefile({}, path)
  return path
end

local function build_planner_prompt(plan_path, user_text)
  return table.concat({
    "You are a plan author. The plan file is:",
    "  " .. plan_path,
    "",
    "On every turn, write/update the plan at that file using your file edit tools.",
    "Use this markdown shape:",
    "",
    "  # Plan",
    "  ## Goal",
    "  <one paragraph stating intent>",
    "  ## Tasks",
    "  - [ ] task 1",
    "  - [ ] task 2",
    "",
    "Refine across turns based on user feedback. Keep the file authoritative.",
    "",
    "User request:",
    "",
    user_text,
  }, "\n")
end

function M.start_flow(cwd, opts)
  opts = opts or {}
  cwd = cwd or vim.fn.getcwd()
  local title = opts.header and (" " .. opts.header .. " ") or " new plan "
  require("djinni.nowork.compose").open(nil, {
    title = title,
    on_submit = function(text)
      if not text or vim.trim(text) == "" then return end
      local path = M.new_empty(cwd)
      local prompt = build_planner_prompt(path, text)
      local droid = require("djinni.nowork").planner(prompt, {
        cwd = cwd,
        plan_path = path,
      })
      if opts.on_done then opts.on_done(path) end
    end,
  })
end

function M.pick(cwd, on_select)
  cwd = cwd or vim.fn.getcwd()
  local files = M.list(cwd)
  if #files == 0 then
    return M.start_flow(cwd, { on_done = on_select })
  end
  local labels = { "[+ new plan]" }
  for _, f in ipairs(files) do
    labels[#labels + 1] = vim.fn.fnamemodify(f, ":t")
  end
  require("djinni.integrations.snacks_ui").select(labels, { prompt = "plans" }, function(_, idx)
    if not idx then return end
    if idx == 1 then
      M.start_flow(cwd, { on_done = on_select })
    else
      local p = files[idx - 1]
      vim.cmd("edit " .. vim.fn.fnameescape(p))
      if on_select then on_select(p) end
    end
  end)
end

function M.current_plan_path(cwd)
  cwd = cwd or vim.fn.getcwd()
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == "" then return nil end
  local abs = vim.fn.fnamemodify(buf_name, ":p")
  if M.is_plan(abs, cwd) then return abs end
  return nil
end

return M
