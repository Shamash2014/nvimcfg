local function parse_ssh_config_async(callback)
  local SKIP_HOSTNAMES = { ["github.com"] = true, ["gitlab.com"] = true, ["bitbucket.org"] = true }
  local all_hosts = {}
  local pending = 2

  local function try_done()
    pending = pending - 1
    if pending > 0 then return end
    local merged = {}
    for i = 1, 2 do
      for _, h in ipairs(all_hosts[i] or {}) do
        table.insert(merged, h)
      end
    end
    local seen = {}
    local result = {}
    for i = #merged, 1, -1 do
      local h = merged[i]
      local hn = h.hostname or h.alias
      if not seen[h.alias] and not SKIP_HOSTNAMES[hn] then
        seen[h.alias] = true
        table.insert(result, 1, h)
      end
    end
    callback(result)
  end

  local function parse_content(content)
    local hosts = {}
    local current
    for line in content:gmatch("[^\n\r]+") do
      local include = line:match("^%s*[Ii]nclude%s+(.+)$")
      if include then
        for _, p in ipairs(vim.fn.glob(vim.fn.expand(vim.trim(include)), false, true)) do
          local f = io.open(p, "r")
          if f then
            local sub = parse_content(f:read("*a"))
            f:close()
            for _, h in ipairs(sub) do
              table.insert(hosts, h)
            end
          end
        end
      end
      local host = line:match("^%s*[Hh]ost%s+(.+)$")
      if host then
        host = vim.trim(host)
        if host ~= "*" and not host:match("%s") then
          current = { alias = host }
          table.insert(hosts, current)
        else
          current = nil
        end
      end
      if current then
        local hostname = line:match("^%s*[Hh]ost[Nn]ame%s+(.+)$")
        if hostname then current.hostname = vim.trim(hostname) end
        local user = line:match("^%s*[Uu]ser%s+(.+)$")
        if user then current.user = vim.trim(user) end
        local port = line:match("^%s*[Pp]ort%s+(%d+)$")
        if port then current.port = tonumber(port) end
      end
    end
    return hosts
  end

  local function read_file(path, slot, local_only)
    vim.uv.fs_open(path, "r", 438, function(err, fd)
      if err or not fd then
        vim.schedule(function() all_hosts[slot] = {}; try_done() end)
        return
      end
      vim.uv.fs_fstat(fd, function(_, stat)
        if not stat then
          vim.uv.fs_close(fd, function() end)
          vim.schedule(function() all_hosts[slot] = {}; try_done() end)
          return
        end
        vim.uv.fs_read(fd, stat.size, 0, function(_, data)
          vim.uv.fs_close(fd, function() end)
          vim.schedule(function()
            local hosts = data and parse_content(data) or {}
            if local_only then
              for _, h in ipairs(hosts) do h.local_only = true end
            end
            all_hosts[slot] = hosts
            try_done()
          end)
        end)
      end)
    end)
  end

  read_file(vim.fn.expand("~/.ssh/config"), 1, false)
  read_file(vim.fn.getcwd() .. "/.ssh-config", 2, true)
end

return {
  "barrettruth/canola.nvim",
  cmd = "Oil",
  keys = {
    { "-", "<CMD>Oil<CR>", desc = "Open Oil file manager" },
    { "<leader>fj", "<CMD>Oil<CR>", desc = "Jump to Oil file manager" },
    {
      "<leader>fs",
      function()
        parse_ssh_config_async(function(hosts)
          if #hosts == 0 then
            vim.notify("No SSH hosts found in ~/.ssh/config", vim.log.levels.WARN)
            return
          end
          Snacks.picker({
            title = "SSH Hosts",
            items = vim.tbl_map(function(h)
              local detail = h.hostname and ("  " .. h.hostname) or ""
              return {
                text = (h.user and h.user .. "@" or "") .. h.alias .. detail,
                alias = h.alias,
                hostname = h.hostname,
                local_only = h.local_only,
                port = h.port,
                user = h.user,
              }
            end, hosts),
            format = function(item)
              return {
                { item.user and (item.user .. "@") or "", "Comment" },
                { item.alias, "Normal" },
                { item.text:match("  .+") or "", "Comment" },
              }
            end,
            confirm = function(picker, item)
              picker:close()
              if not item then return end
              local host = item.local_only and (item.hostname or item.alias) or item.alias
              local port_suffix = item.local_only and item.port and (":" .. item.port) or ""
              local url = "oil-ssh://" .. (item.user and item.user .. "@" or "") .. host .. port_suffix .. "/"
              require("oil").open(url)
            end,
          })
        end)
      end,
      desc = "Open Oil SSH",
    },
  },
  config = function()
    require("oil").setup({
      default_file_explorer = true,
      delete_to_trash = true,
      skip_confirm_for_simple_edits = true,
      view_options = {
        show_hidden = true,
        is_always_hidden = function(name, _)
          return name == ".." or name == ".git"
        end,
      },
      float = {
        padding = 2,
        max_width = 90,
        max_height = 0,
      },
      win_options = {
        wrap = true,
        winblend = 0,
      },
      keymaps = {
        ["<C-h>"] = false,
        ["<C-l>"] = false,
        ["<C-k>"] = false,
        ["<C-j>"] = false,
      },
    })
  end,
}
