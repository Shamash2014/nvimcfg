return {
  "stevearc/oil.nvim",
  cmd = "Oil",
  keys = {
    { "-", function()
        local ssh = require("tramp.ssh")
        local tramp = require("tramp")
        local hosts = ssh.get_ssh_hosts(tramp.config.ssh_config)

        if #hosts == 0 then
          vim.cmd("Oil")
          return
        end

        local items = vim.tbl_map(function(host)
          return {
            text = host.name .. (host.hostname and " (" .. host.hostname .. ")" or ""),
            host = host,
          }
        end, hosts)

        table.insert(items, 1, {
          text = "Local files",
          host = nil,
        })

        local ok, snacks = pcall(require, "snacks")
        if ok and snacks.picker then
          snacks.picker.pick({
            items = items,
            layout = { preset = "vscode" },
            format = function(item)
              return item.text
            end,
            confirm = function(item)
              if not item.host then
                vim.cmd("Oil")
              else
                local host = item.host.hostname or item.host.name
                local user = item.host.user or tramp.config.default_user or vim.fn.getenv("USER")

                vim.ui.input({
                  prompt = "Remote directory [/]: ",
                  default = "/",
                }, function(dir)
                  if dir then
                    local tramp_path = string.format("/ssh:%s@%s:%s", user, host, dir)
                    vim.cmd("edit " .. tramp_path)
                  end
                end)
              end
            end,
          })
        else
          vim.ui.select(items, {
            prompt = "Open directory:",
            format_item = function(item)
              return item.text
            end,
          }, function(selected)
            if not selected then
              return
            end

            if not selected.host then
              vim.cmd("Oil")
            else
              local host = selected.host.hostname or selected.host.name
              local user = selected.host.user or tramp.config.default_user or vim.fn.getenv("USER")

              vim.ui.input({
                prompt = "Remote directory [/]: ",
                default = "/",
              }, function(dir)
                if dir then
                  local tramp_path = string.format("/ssh:%s@%s:%s", user, host, dir)
                  vim.cmd("edit " .. tramp_path)
                end
              end)
            end
          end)
        end
      end, desc = "Open Oil or Remote directory" },
    { "<leader>fj", "<CMD>Oil<CR>", desc = "Jump to Oil file manager" },
  },
  opts = {
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
  },
}