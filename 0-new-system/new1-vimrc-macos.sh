#!/bin/bash
# Author: Roy Wiseman 2025-02
# macOS Adapter for Vim/Neovim Setup

echo "Starting Vim/Neovim configuration update (macOS)..."

install_package() {
    local pkg_name="$1"
    local exec_name="$2"

    if [ -z "$pkg_name" ] || [ -z "$exec_name" ]; then
        echo "Error: install_package requires both package name and executable name."
        return 1
    fi

    echo "Ensuring package '$pkg_name' (providing '$exec_name') is installed..."

    if command -v "$exec_name" &> /dev/null; then
        echo "'$exec_name' is already available."
        return 0
    fi

    echo "'$exec_name' not found."

    # macOS Homebrew Support
    if command -v brew &> /dev/null; then
        echo "Using Homebrew to install '$pkg_name'..."
        # Brew should NOT be run as sudo
        if ! brew install "$pkg_name"; then
            echo "Error: brew installation of '$pkg_name' failed."
            return 1
        fi
    else
        echo "Error: Homebrew 'brew' not found. Cannot install packages automatically on macOS without it."
        echo "Please install Homebrew (https://brew.sh/) or install '$pkg_name' manually."
        return 1
    fi

    if command -v "$exec_name" &> /dev/null; then
        echo "'$pkg_name' installed successfully."
        return 0
    else
        echo "Error: Failed to find '$exec_name' after installation."
        return 1
    fi
}

# Install vim and neovim
install_package "vim" "vim" || echo "Warning: Vim installation failed."
install_package "neovim" "nvim" || echo "Warning: Neovim installation failed."

# --- Ensure configuration files and directories exist ---
vimrc_file="$HOME/.vimrc"
if [ ! -f "$vimrc_file" ]; then touch "$vimrc_file"; echo "Created $vimrc_file"; fi

mkdir -p "$HOME/.config/nvim"
nvim_init_file="$HOME/.config/nvim/init.vim"
if [ ! -f "$nvim_init_file" ]; then touch "$nvim_init_file"; echo "Created $nvim_init_file"; fi

# Execute the original script to start applying config calls IF we could just reuse its logic.
# But since we can't easily import the function from the other script without running its install logic (which fails),
# we essentially need the Config Block logic from the original file.
# To adhere to "Seamless setup" without duplicating 400 lines of config, we can:
# 1. Provide the environment (packages installed).
# 2. Run the original script. It will check for packages, find them installed, and proceed to config.
#    Wait, the original script FAILED because it couldn't detect package manager to INSTALL.
#    But if we install them FIRST (here), the original script will see `command -v nvim` returns true,
#    and SKIP the install logic, proceeding to config!

# So this script only needs to pre-install packages using Brew, then call the original.

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ORIGINAL_SCRIPT="$SCRIPT_DIR/new1-vimrc.sh"

if [ -x "$ORIGINAL_SCRIPT" ]; then
    echo "Handing over to original configuration script..."
    "$ORIGINAL_SCRIPT"
else
    echo "Error: Could not find original $ORIGINAL_SCRIPT"
fi
