# TRAMP.nvim Quick Start Guide

## 🚀 TL;DR

Edit remote files like local files:
```vim
:edit /ssh:user@host:/path/to/file
```

## 📁 Basic Usage

### 1. Edit a Remote File
```vim
" Direct path
:edit /ssh:john@server:/etc/nginx/nginx.conf

" Or use the prompt
<leader>re
" Then enter: user@host:/path/to/file
```

### 2. Browse Remote Directories

**With Oil.nvim (if installed):**
```vim
:edit /ssh:user@host:/path/to/directory
```

Then use oil.nvim commands:
- `j`/`k` - Navigate files
- `Enter` - Open file/directory
- `-` - Create new file/directory
- `R` - Rename
- `d` - Delete

**With Snacks.nvim Picker:**
```vim
<leader>rf  " Or :TrampFind
```
Then:
1. Select host
2. Enter directory
3. Navigate with fuzzy search

### 3. Search Remote Files
```vim
<leader>rg  " Or :TrampGrep pattern
```

## 🎯 Common Workflows

### Workflow 1: Quick Config Edit
```vim
:e /ssh:prod:/etc/nginx/nginx.conf
" Make changes
:w
```

### Workflow 2: Browse and Edit Project
```vim
<leader>rx  " Explore remote
" Select host: myserver
" Enter path: /var/www/project
" Browse and edit files
```

### Workflow 3: Debug Remote Logs
```vim
:e /ssh:server:/var/log/app/error.log
<leader>rg
" Search for: ERROR
" Jump to errors
```

### Workflow 4: Oil.nvim Power User
```vim
:e /ssh:user@host:/home/user/projects

" In oil.nvim buffer:
" - Create new file: press `-`, type name
" - Rename files: press `R`, edit name
" - Delete files: press `d`
" - Move files: visual select + `d`, navigate, paste
" - All changes sync automatically!
```

## 💡 Pro Tips

### Tip 1: Use SSH Config
Add to `~/.ssh/config`:
```ssh
Host prod
  HostName production.example.com
  User deploy
  Port 22
```

Then simply:
```vim
:e /ssh:prod:/app/config.yml
```

### Tip 2: Async Loading
Files load asynchronously - you'll see "Loading remote file..." briefly.
Keep working while it loads!

### Tip 3: Connection Pooling
First connection to a host takes ~1-2s. Subsequent operations are instant
thanks to connection pooling (5 min timeout).

### Tip 4: Grep is Powerful
```vim
<leader>rg
" Enter pattern: function.*Error
" Get results with line numbers
" Jump directly to matches
```

### Tip 5: Explore vs Find
- `<leader>rx` (Explore) - Opens oil.nvim if available, great for file management
- `<leader>rf` (Find) - Opens picker for quick file browsing

## 🔧 Troubleshooting

### Can't Connect?
```vim
:TrampConnect
" Test connection manually
" Check your SSH keys: ssh user@host
```

### File Won't Save?
```vim
:TrampInfo
" Check if still connected
" Verify permissions on remote
```

### Slow Operations?
```vim
:TrampConnect
" Pre-connect to warm up the connection
```

## ⌨️ Keyboard Reference

| Key | Action |
|-----|--------|
| `<leader>re` | Edit remote file (prompt) |
| `<leader>rf` | Find remote files (picker) |
| `<leader>rx` | Explore remote dir (oil/snacks) |
| `<leader>rg` | Grep remote files |
| `<leader>rc` | Connect to host |
| `<leader>rd` | Disconnect |
| `<leader>ri` | Connection info |

## 📝 Path Format

```
/ssh:user@host:/absolute/path
/ssh:host:/path              " Uses current user
/ssh:user@host:~/relative    " Home directory
```

Examples:
- `/ssh:john@server:/etc/nginx/nginx.conf`
- `/ssh:prod:/var/www/app`
- `/ssh:dev:~/projects/myapp`

## 🎨 Integration Tips

### With Your Workflow
```vim
" Add to your init.lua
vim.keymap.set("n", "<leader>ep", function()
  vim.cmd("edit /ssh:prod:/var/www/app")
end, { desc = "Edit Production" })
```

### With Project-specific Configs
Create `.nvim.lua` in your project:
```lua
vim.keymap.set("n", "<leader>ed", function()
  require("tramp").explore_remote("/ssh:dev:/home/deploy/current")
end, { desc = "Explore Deploy Server" })
```

## 🚦 Status Indicators

Watch for notifications:
- "Loading remote file..." - File is being fetched
- "Saving remote file..." - File is being written
- "Connected to user@host" - Connection established
- "Remote file saved: /path" - Save successful

Happy remote editing! 🎉
