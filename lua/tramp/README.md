# TRAMP.nvim - Transparent Remote Access for Neovim

A TRAMP-like (Transparent Remote Access, Multiple Protocol) plugin for Neovim that enables seamless editing of remote files over SSH, inspired by Emacs TRAMP.

## Features

- **Transparent Remote Editing**: Edit remote files as if they were local
- **Async Operations**: All SSH operations are non-blocking using plenary.job
- **Path-based Access**: Use special paths like `/ssh:user@host:/path/to/file`
- **SSH Config Integration**: Automatically reads hosts from `~/.ssh/config`
- **Connection Pooling**: Reuses SSH connections for better performance
- **Oil.nvim Support**: Browse remote directories with oil.nvim file explorer
- **Snacks.nvim Integration**: Navigate with snacks.nvim picker
- **Remote Grep**: Async search for patterns in remote files
- **Progress Notifications**: Visual feedback for long-running operations
- **Agentless**: No need to install anything on the remote server
- **Lazy Loading**: Connects only when needed

## Installation

This plugin is already configured in your Neovim setup at `lua/plugins/tramp.lua`.

## Usage

### Opening Remote Files

#### Method 1: Direct Path
```vim
:edit /ssh:user@host:/path/to/file
:edit /ssh:host:/path/to/file  " Uses current user
```

#### Method 2: Interactive Selection
```vim
<leader>re  " Edit remote file (prompts for path)
<leader>rf  " Find remote files (browse with picker)
```

Or use commands:
```vim
:TrampEdit user@host:/path/to/file
:TrampFind
```

### Path Format

The TRAMP path format is:
```
/ssh:user@host:/absolute/path/to/file
/ssh:host:/path  " Uses default user
```

Examples:
- `/ssh:john@example.com:/home/john/config.lua`
- `/ssh:server:/var/log/nginx/error.log`

### Browsing Remote Directories

#### With Oil.nvim (Recommended)
If you have oil.nvim installed:
```vim
:edit /ssh:user@host:/path/to/directory
```
This opens the remote directory in oil.nvim, allowing you to:
- Navigate with `j`/`k`
- Create files/directories with `-`
- Rename files with `R`
- Delete files with `d`
- All changes sync to remote server

#### With Snacks.nvim Picker
1. Press `<leader>rf` to open the remote file finder
2. Select a host from your SSH config
3. Enter a directory path (default: `/`)
4. Browse files and directories
5. Press Enter on a file to edit it
6. Press Enter on a directory to navigate into it

#### Explore Command
```vim
<leader>rx  " Opens remote explorer (oil if available, else snacks picker)
:TrampExplore /ssh:user@host:/path
```

### Searching Remote Files

```vim
<leader>rg  " Grep in remote files (prompts for pattern)
```

Or use the command:
```vim
:TrampGrep pattern
```

This searches the directory of the current remote file and shows results in a picker.

### Connection Management

#### Connect to a Host
```vim
<leader>rc  " Connect to remote host
:TrampConnect
```

This establishes a connection and keeps it alive for faster subsequent operations.

#### View Active Connections
```vim
<leader>ri  " Show connection info
:TrampInfo
```

#### Disconnect
```vim
<leader>rd  " Disconnect from host
:TrampDisconnect
```

## How It Works

TRAMP.nvim intercepts Neovim's file operations for paths starting with `/ssh:` and translates them into async SSH commands using plenary.job:

1. **Reading**: `ssh user@host 'cat /path/to/file'` (async)
2. **Writing**: `scp /tmp/file user@host:/path/to/file` (async)
3. **Listing**: `ssh user@host 'ls -1Ap /path'` (async)
4. **Searching**: `ssh user@host 'grep -r pattern /path'` (async)

All operations are non-blocking - you can continue working while files load. Connections are cached and reused for 5 minutes of inactivity, reducing connection overhead.

## Configuration

Default configuration in `lua/plugins/tramp.lua`:

```lua
{
  ssh_config = "~/.ssh/config",        -- Path to SSH config
  cache_dir = vim.fn.stdpath("cache") .. "/tramp",  -- Cache directory
  connection_timeout = 10,              -- SSH connection timeout in seconds
  default_user = nil,                   -- Default SSH user (nil = current user)
}
```

## Keybindings

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>re` | Edit Remote | Prompt for remote file path |
| `<leader>rf` | Find Remote | Browse remote files with picker |
| `<leader>rx` | Explore Remote | Open remote directory (oil or snacks) |
| `<leader>rg` | Grep Remote | Search remote files |
| `<leader>rc` | Connect | Connect to remote host |
| `<leader>rd` | Disconnect | Disconnect from host |
| `<leader>ri` | Info | Show active connections |

## Commands

| Command | Description |
|---------|-------------|
| `:TrampEdit [path]` | Edit remote file |
| `:TrampFind` | Browse remote files |
| `:TrampExplore [path]` | Explore remote directory (oil/snacks) |
| `:TrampGrep <pattern>` | Search remote files |
| `:TrampConnect` | Connect to host |
| `:TrampDisconnect` | Disconnect from host |
| `:TrampInfo` | Show connection info |

## SSH Config Integration

TRAMP.nvim reads hosts from your `~/.ssh/config` file. Example:

```ssh-config
Host myserver
  HostName example.com
  User john
  Port 22

Host dev
  HostName dev.company.com
  User developer
```

These hosts will appear in the host picker when you use `<leader>rf` or `:TrampFind`.

## Examples

### Edit a remote configuration file
```vim
:edit /ssh:john@server:/etc/nginx/nginx.conf
```

### Browse and edit remote project files
1. `<leader>rf`
2. Select "myserver"
3. Enter `/var/www/project`
4. Navigate and select files

### Search for errors in remote logs
1. Open `/ssh:server:/var/log/app/error.log`
2. `<leader>rg`
3. Enter search pattern: "ERROR"
4. Jump to matching lines

## Advantages over SSHFS

1. **No mounting required**: Works immediately, no need to mount filesystems
2. **Agentless**: No installation needed on remote server
3. **Async operations**: Non-blocking, responsive UI
4. **Oil.nvim support**: Full-featured directory editing
5. **Transparent**: Feels like editing local files
6. **Efficient**: Connection pooling reduces overhead
7. **Simple**: Just SSH access required, no additional setup

## Troubleshooting

### Connection fails
- Check SSH key is set up: `ssh user@host`
- Verify host in `~/.ssh/config`
- Check `connection_timeout` in config

### File not saving
- Verify write permissions on remote file
- Check SSH connection: `:TrampInfo`

### Directory listing empty
- Ensure remote directory exists
- Check remote shell compatibility (requires POSIX `ls`)

## Related Projects

- [Emacs TRAMP](https://www.gnu.org/software/tramp/) - Original TRAMP implementation
- [distant.nvim](https://github.com/chipsenkbeil/distant.nvim) - Alternative with LSP support

## License

MIT
