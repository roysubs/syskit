#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05


pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

(return 0 2>/dev/null) || { echo "This script should be run sourced (e.g., '. ${0##*/}' to change the default vi alias)"; exit 1; }
# Check if Vim is installed
if ! command -v vim &>/dev/null; then
    echo "Vim is not installed. Attempting to install Vim..."
    if pkg_install vim; then
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
