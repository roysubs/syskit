#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# Set Zsh as default shell

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

echo "Setting Zsh as default shell..."
chsh -s $(which zsh)

# Clone Powerlevel10k repository
echo "Cloning Powerlevel10k repository..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.powerlevel10k

# Configure Zsh to use Powerlevel10k
echo "Configuring Zsh to use Powerlevel10k..."
echo 'source ~/.powerlevel10k/powerlevel10k.zsh-theme' >> ~/.zshrc

# Install necessary fonts (Nerd Fonts)
echo "Installing necessary fonts (Nerd Fonts)..."
sudo apt update
pkg_install fonts-font-awesome fonts-powerline

# Install Nerd Fonts (additional fonts if required)
echo "Installing Nerd Fonts..."
cd ~
if [ ! -d "nerd-fonts" ]; then
    git clone --depth=1 https://github.com/ryanoasis/nerd-fonts.git
    cd nerd-fonts
    ./install.sh
else
    echo "Nerd Fonts already installed."
fi

# Apply changes to Zsh by sourcing the .zshrc file
echo "Applying changes to Zsh..."
source ~/.zshrc

# Ensure the Zsh is running with the correct configuration and Powerlevel10k theme
echo "Running Powerlevel10k configuration wizard..."
p10k configure

echo "Powerlevel10k installation complete. Please restart your terminal or run 'zsh' to start Zsh with Powerlevel10k."

