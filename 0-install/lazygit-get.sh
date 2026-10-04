#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# Install lazygit git management tool


pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need brew/apt/zypper/dnf)." >&2; exit 1
    fi
}

if command -v lazygit >/dev/null 2>&1; then
    echo "Lazygit is already installed. Exiting."
    exit 0
fi
echo "Lazygit not found. Proceeding with installation..."

# Update package list and install prerequisites
pkg_install wget git unzip

# Start tracking time and disk usage after initial steps
start_time=$(date +%s)
initial_free_space=$(df -Pk / | tail -1 | awk '{print int($4 / 1024)}') # Available space in MB

# Fetch the latest release of LazyGit
LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$(uname -m)" = "arm64" ]; then LAZYGIT_PLATFORM="Darwin_arm64"; else LAZYGIT_PLATFORM="Darwin_x86_64"; fi
else
    LAZYGIT_PLATFORM="Linux_x86_64"
fi
wget "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_${LAZYGIT_PLATFORM}.tar.gz" -O lazygit.tar.gz

# Extract and install LazyGit
tar -xzf lazygit.tar.gz
sudo install lazygit /usr/local/bin

# Clean up
rm -rf lazygit lazygit.tar.gz
rm -f README.md
rm -f LICENSE

# Verify installation
echo "LazyGit version and build:"
lazygit --version

# End tracking of time and disk usage
end_time=$(date +%s)
total_time=$((end_time - start_time))
final_free_space=$(df -Pk / | tail -1 | awk '{print int($4 / 1024)}')
used_space=$((initial_free_space - final_free_space))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
echo "Total disk space used by installations: $used_space MB"
