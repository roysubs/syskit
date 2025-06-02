#!/bin/bash

# Define terminal applications with their descriptions
declare -A terminals
terminals=(
    ["tilix"]="Tilix: Excellent tiling capabilities (split your terminal into multiple panes horizontally and vertically), drag-and-drop support, session saving, input synchronization across multiple terminals, and a \"Quake-mode\" drop-down. It's GTK-based, so it integrates well with GNOME and other GTK-based desktops."
    ["terminator"]="Terminator: Allows you to arrange multiple GNOME terminals in one window, split them into a grid, and easily group/re-group them. Highly customizable with profiles, color schemes, and fonts. Great for power users who need to manage many terminal sessions simultaneously."
    ["konsole"]="Konsole: The default terminal for KDE, Konsole is highly customizable and feature-rich. It supports tabs, multiple profiles, split views, and has strong scripting capabilities. It's very performant and well-integrated into the KDE ecosystem."
    ["gnome-terminal"]="GNOME Terminal: The default terminal for the GNOME desktop environment, it's stable, reliable, and integrates seamlessly with GNOME. It offers tabs, profiles, customizable colors, and basic splitting (though not as advanced as Tilix or Terminator)."
    ["guake"]="Guake: Inspired by the Quake console, it slides down from the top of your screen with a single keystroke (default F12) and hides away just as easily. It's fast, highly configurable (transparency, theming, shortcuts), and GNOME-friendly."
    ["yakuake"]="Yakuake: KDE's equivalent of Guake. It offers a slick drop-down animation and deep integration with the KDE desktop."
    ["tilda"]="Tilda: A lightweight GTK-based drop-down terminal. Highly configurable, similar to Guake but often preferred by those seeking a more minimalist drop-down."
    ["alacritty"]="Alacritty: Written in Rust, it's known for being incredibly fast and GPU-accelerated. It prioritizes performance and simplicity, often being favored by minimalists who don't need advanced features directly within the terminal (they might use \`tmux\` for multiplexing). (Availability may vary by Ubuntu version/release, might be a slightly older version in default repos.)"
    ["kitty"]="Kitty: Another GPU-powered terminal emulator, Kitty is also very fast. It offers a good balance of performance and features, including tabs, splits, image support, and scriptability. (Availability may vary by Ubuntu version/release, might be a slightly older version in default repos.)"
)

# --- Initial Summary and Recommendations ---
echo "--------------------------------------------------------"
echo "           Recommended GUI Terminals in APT             "
echo "--------------------------------------------------------"
echo ""
echo "Here's a list of excellent GUI terminal emulators available in your APT repositories:"
echo ""

for pkg in "${!terminals[@]}"; do
    echo "  - $pkg"
done
echo ""

echo "Recommendations:"
echo "  - For a well-rounded experience with powerful tiling: Tilix or Terminator."
echo "  - For quick, on-demand access: Guake or Yakuake (if you're on KDE)."
echo "  - For blazing fast performance (especially if you use tmux or similar multiplexers): Alacritty or Kitty."
echo "  - If you stick to your desktop environment's default and want something reliable: GNOME Terminal (for GNOME) or Konsole (for KDE)."
echo ""
echo "--------------------------------------------------------"
echo ""

# --- Installation Process ---

# Check for apt and sudo
if ! command -v apt &> /dev/null; then
    echo "Error: 'apt' command not found. This script is intended for Debian/Ubuntu-based systems."
    exit 1
fi

if ! command -v sudo &> /dev/null; then
    echo "Error: 'sudo' command not found. Please install sudo or run this script as root (not recommended)."
    exit 1
fi

echo "Starting the installation process for GUI terminals..."
echo "You will be prompted to confirm each installation."
echo ""

# Update package list first
read -p "Would you like to run 'sudo apt update' now? (y/N): " update_choice
if [[ "$update_choice" =~ ^[Yy]$ ]]; then
    echo "Running sudo apt update..."
    sudo apt update || { echo "Failed to update apt packages. Exiting."; exit 1; }
    echo "apt update completed."
else
    echo "Skipping apt update."
fi

echo ""

for pkg in "${!terminals[@]}"; do
    echo "--------------------------------------------------------"
    echo "Package: $pkg"
    echo "Description: ${terminals[$pkg]}"
    echo "--------------------------------------------------------"
    
    # Check if already installed
    if dpkg -s "$pkg" &> /dev/null; then
        echo "--> $pkg is already installed. Skipping."
        echo ""
        continue
    fi

    read -p "Do you want to install $pkg? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Installing $pkg..."
        sudo apt install -y "$pkg"
        if [ $? -eq 0 ]; then
            echo "Successfully installed $pkg."
        else
            echo "Failed to install $pkg. Please check the error messages above."
        fi
    else
        echo "Skipping installation of $pkg."
    fi
    echo ""
done

echo "--------------------------------------------------------"
echo "Installation process complete."
echo "You can now find your installed terminal emulators in your applications menu."
echo "--------------------------------------------------------"
