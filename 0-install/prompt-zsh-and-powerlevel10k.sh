#!/bin/bash
# Author: Roy Wiseman 2025-03

# Set Zsh as default shell
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
sudo apt install -y fonts-font-awesome fonts-powerline

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

