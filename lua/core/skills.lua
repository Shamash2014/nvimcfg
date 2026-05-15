local M = {}

local function skills_root()
  return (vim.g.nvim3_skills_dirs and vim.g.nvim3_skills_dirs[1])
    or vim.fn.expand("~/.config/nvim.3/skills")
end

function M.install()
  local args = { "npx", "-y", "skills", "add", skills_root(), "--all", "--yes" }
  vim.notify("skills: installing…", vim.log.levels.INFO)
  vim.system(args, { text = true }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        vim.notify(
          "skills: installed\n" .. ((out.stdout or ""):gsub("%s+$", "")),
          vim.log.levels.INFO
        )
      else
        vim.notify(
          "skills: install failed ("
            .. out.code
            .. ")\n"
            .. ((out.stderr or out.stdout or ""):gsub("%s+$", "")),
          vim.log.levels.ERROR
        )
      end
    end)
  end)
end

function M.uninstall(name)
  if not name or name == "" then
    vim.notify("skills: name required", vim.log.levels.WARN)
    return
  end
  vim.system({ "npx", "-y", "skills", "remove", name, "--yes" }, { text = true }, function(out)
    vim.schedule(function()
      local kind = out.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
      vim.notify(
        "skills: remove "
          .. name
          .. " -> "
          .. ((out.stdout or out.stderr or ""):gsub("%s+$", "")),
        kind
      )
    end)
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
