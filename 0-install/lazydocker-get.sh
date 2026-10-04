#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# Install LazyDocker docker management tool
if command -v lazydocker >/dev/null 2>&1; then
    echo "LazyDocker is already installed. Exiting."
    exit 0
fi
echo "LazyDocker not found. Proceeding with installation..."

pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need brew/apt/zypper/dnf)." >&2; exit 1
    fi
}

# Update package list and install prerequisites
pkg_install wget git unzip

# Start tracking time and disk usage after initial steps
start_time=$(date +%s)
initial_free_space=$(df -Pk / | tail -1 | awk '{print int($4 / 1024)}') # Available space in MB

# Fetch the latest release of LazyDocker
LAZYDOCKER_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$(uname -m)" = "arm64" ]; then LAZYDOCKER_PLATFORM="Darwin_arm64"; else LAZYDOCKER_PLATFORM="Darwin_x86_64"; fi
else
    LAZYDOCKER_PLATFORM="Linux_x86_64"
fi
wget "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_${LAZYDOCKER_PLATFORM}.tar.gz" -O lazydocker.tar.gz

# Extract and install LazyDocker
tar -xzf lazydocker.tar.gz
sudo install lazydocker /usr/local/bin

# Clean up
rm -rf lazydocker lazydocker.tar.gz
rm -f README.md
rm -f LICENSE

# Verify installation
echo "LazyDocker version and build:"
lazydocker --version

# End tracking of time and disk usage
end_time=$(date +%s)
total_time=$((end_time - start_time))
final_free_space=$(df -Pk / | tail -1 | awk '{print int($4 / 1024)}')
used_space=$((initial_free_space - final_free_space))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
echo "Total disk space used by installations: $used_space MB"

echo "More info: https://www.youtube.com/watch?v=IUAk1pjXDWM"

