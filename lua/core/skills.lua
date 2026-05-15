local M = {}

local function skills_root()
  if vim.g.nvim3_skills_dirs and vim.g.nvim3_skills_dirs[1] then
    return vim.fn.expand(vim.g.nvim3_skills_dirs[1])
  end
  local p = vim.fn.stdpath("config") .. "/skills"
  if vim.fn.isdirectory(p) == 1 then return p end
  return vim.fn.expand("~/.config/nvim/skills")
end

local function run_skills(argv, on_done)
  local cmd = "npx -y skills " .. argv
  vim.system({ vim.o.shell, "-lc", cmd }, { text = true }, function(out)
    vim.schedule(function() on_done(out) end)
  end)
end

local function show_error(name, code, out)
  local stderr = (out.stderr or ""):gsub("%s+$", "")
  local stdout = (out.stdout or ""):gsub("%s+$", "")
  vim.cmd("botright 15split")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "log"
  pcall(vim.api.nvim_buf_set_name, buf, "skills://error/" .. name)
  local lines = { "skills: " .. name .. " failed (exit " .. tostring(code) .. ")", "" }
  if stderr ~= "" then
    table.insert(lines, "── stderr ──")
    vim.list_extend(lines, vim.split(stderr, "\n", { plain = true }))
    table.insert(lines, "")
  end
  if stdout ~= "" then
    table.insert(lines, "── stdout ──")
    vim.list_extend(lines, vim.split(stdout, "\n", { plain = true }))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "q", "<cmd>hide<cr>", { buffer = buf, silent = true })
end

function M.install()
  local root = skills_root()
  if vim.fn.isdirectory(root) == 0 then
    vim.notify("skills: dir not found: " .. root, vim.log.levels.ERROR)
    return
  end
  vim.notify("skills: installing from " .. root, vim.log.levels.INFO)
  run_skills("add " .. vim.fn.shellescape(root) .. " --all", function(out)
    if out.code == 0 then
      vim.notify(
        "skills: installed\n" .. ((out.stdout or ""):gsub("%s+$", "")),
        vim.log.levels.INFO
      )
    else
      vim.notify("skills: install failed (exit " .. out.code .. ")", vim.log.levels.ERROR)
      show_error("install", out.code, out)
    end
  end)
end

function M.uninstall(name)
  if not name or name == "" then
    vim.notify("skills: name required", vim.log.levels.WARN)
    return
  end
  local argv = "remove -s " .. vim.fn.shellescape(name) .. " -a '*' -y"
  run_skills(argv, function(out)
    if out.code == 0 then
      vim.notify(
        "skills: remove " .. name .. "\n" .. ((out.stdout or ""):gsub("%s+$", "")),
        vim.log.levels.INFO
      )
    else
      vim.notify("skills: remove " .. name .. " failed (exit " .. out.code .. ")", vim.log.levels.ERROR)
      show_error("remove-" .. name, out.code, out)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("SkillInstall", function() M.install() end, {
    desc = "Install all nvim.3 skills into agent CLIs",
  })

  vim.api.nvim_create_user_command("SkillUninstall", function(opts)
    M.uninstall(opts.args)
  end, { nargs = 1, desc = "Uninstall a skill from agent CLIs" })
end

return M
