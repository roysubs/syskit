#!/bin/bash
# Author: Roy Wiseman 2025-05

(return 0 2>/dev/null) || { echo "This script should be run sourced (e.g., '. ${0##*/}' to change the default vi alias)"; exit 1; }
# Check if Vim is installed
if ! command -v vim &>/dev/null; then
    echo "Vim is not installed. Attempting to install Vim..."
    if sudo apt update && sudo apt install -y vim; then
        echo "Vim has been successfully installed."
    else
        echo "Error: Vim installation failed."
    fi
fi

# Set as the default editor for environment (visudo etc will use)
sudo update-alternatives --set editor /usr/bin/vim.basic

# Replace any existing alias for vi in ~/.bashrc with the new one
if grep -q "^alias vi=" ~/.bashrc; then
    echo "Replacing existing alias for vi in ~/.bashrc"
    sed -i "s#^alias vi=.*#alias vi='vim'#" ~/.bashrc
else
    echo "alias vi='vim'" >> ~/.bashrc
    echo "Added alias to ~/.bashrc: alias vi='vim'"
fi

alias vi='vim'

# nvim (neovim) is at:
#   /usr/bin/nvim

# TinyVim is at:
#   /usr/bin/vi
#   /bin/vi
#   /usr/bin/vim.tiny (specific to Debian-based systems)
