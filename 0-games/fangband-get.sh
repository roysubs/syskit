#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05

# Install dependencies

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

sudo apt update
pkg_install build-essential ncurses-dev git cmake

# Clone the FAangband repository into your home directory
git clone https://github.com/NickMcConnell/FAangband.git ~/FAangband

# Navigate into the FAangband directory
cd ~/FAangband

# Run CMake to configure the build
cmake .

# Compile the source code
make

# Optional: Install the game system-wide
sudo make install

# Output success message
echo "FAangband has been successfully installed in ~/FAangband!"

