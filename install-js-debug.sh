#!/bin/bash

# Script to install vscode-js-debug for nvim-dap-vscode-js

INSTALL_DIR="$HOME/.local/share/nvim/vscode-js-debug"

echo "Installing vscode-js-debug to $INSTALL_DIR..."

# Create directory if it doesn't exist
mkdir -p "$(dirname "$INSTALL_DIR")"

# Clone the repository
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory exists, updating..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "Cloning vscode-js-debug..."
    git clone https://github.com/microsoft/vscode-js-debug.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Install dependencies and build
echo "Installing dependencies..."
npm install

echo "Building..."
npm run compile

echo "Building vsDebugServerBundle..."
npx gulp vsDebugServerBundle || echo "Warning: vsDebugServerBundle task might not exist"

echo "Installation complete!"
echo ""
echo "vscode-js-debug has been installed to: $INSTALL_DIR"
echo "You can now use DAP debugging in Neovim with:"
echo "  - <leader>dd to start debugging"
echo "  - <leader>db to toggle breakpoint"
echo "  - <leader>do to step over"
echo "  - <leader>di to step into"
echo ""
echo "To debug a Node.js file:"
echo "  1. Open a JavaScript/TypeScript file"
echo "  2. Set breakpoints with <leader>db"
echo "  3. Start debugging with <leader>dd"