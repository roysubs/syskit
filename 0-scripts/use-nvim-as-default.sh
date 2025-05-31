#!/bin/bash
# Author: Roy Wiseman 2025-02

# Check if the script is being sourced
(return 0 2>/dev/null) || { echo "This script should be run sourced (e.g., '. ${0##*/}' to change the default vi alias)"; exit 1; }

# Check if Neovim (nvim) is installed
if ! command -v nvim &> /dev/null
then
    echo "Neovim is not installed. Installing Neovim..."
    
    # Install prerequisites for Neovim
    sudo apt update
    sudo apt install -y software-properties-common
    sudo add-apt-repository ppa:neovim-ppa/stable
    sudo apt update
    sudo apt install -y neovim

    # Verify installation
    if command -v nvim &> /dev/null
    then
        echo "Neovim has been successfully installed."
    else
        echo "Error: Neovim installation failed."
    fi
fi

# Set Neovim as the default editor
sudo update-alternatives --set editor /usr/bin/nvim

# Replace any existing alias for vi in ~/.bashrc with the new one
if grep -q "^alias vi=" ~/.bashrc; then
    echo "Replacing existing alias for vi in ~/.bashrc"
    sed -i "s#^alias vi=.*#alias vi='nvim'#" ~/.bashrc
else
    echo "alias vi='nvim'" >> ~/.bashrc
    echo "Added alias to ~/.bashrc: alias vi='nvim'"
fi

alias vi='nvim'

echo "
Notes:
- nvim does not use ~/.vimrc, and instead uses ~/.config/nvim/init.vim
- nvim takes over the mouse-select-right-click function, instead of that it will
  offer the nvim menu. If this is not wanted, use ':set mouse=' to turn it off.
  Add that to the ~/.config/nvim/init.vim to make this the default behaviour.
"

# nvim Common Installation Locations
#   /usr/bin/nvim
#   /usr/local/bin/nvim
# User-specific Installations:
# User-specific install via a package manager or manually:
#   $HOME/.local/bin/nvim (common for curl-based or appimage installations).
# If using Homebrew (macOS/Linux):
#   /usr/local/bin/nvim (on macOS or older Linux Homebrew installations).
#   /home/linuxbrew/.linuxbrew/bin/nvim (on Linux Homebrew installations).

# TinyVim is at:
#   /usr/bin/vi
#   /bin/vi
#   /usr/bin/vim.tiny (specific to Debian-based systems)
