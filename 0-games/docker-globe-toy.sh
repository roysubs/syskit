#!/bin/bash
# Author: Roy Wiseman 2025-02

set -e

echo "Installing globe-cli..."

function install_with_yay() {
    if command -v yay &>/dev/null; then
        echo "Using yay to install globe-cli from AUR..."
        yay -S --noconfirm globe-cli
        return 0
    fi
    return 1
}

function install_with_docker() {
    if command -v docker &>/dev/null; then
        echo "Using Docker to install and run globe-cli..."
        TMP_DIR=$(mktemp -d)
        cd "$TMP_DIR"
        
        echo "Downloading globe source from GitHub..."
        wget https://github.com/adamsky/globe/archive/refs/heads/master.zip -O globe.zip
        
        echo "Extracting globe source..."
        unzip globe.zip
        cd globe-master

        echo "Building Docker image..."
        docker build -t globe .

        echo "You can now run globe like this:"
        echo "    docker run -it --rm globe -s"
        return 0
    fi
    return 1
}

function install_with_cargo() {
    if ! command -v cargo &>/dev/null; then
        echo "Rust is not installed. Installing Rust first..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    echo "Installing globe-cli with cargo..."
    cargo install globe-cli
    return 0
}

if install_with_yay; then
    echo "Installed using yay (AUR)."
elif install_with_docker; then
    echo "Installed using Docker."
else
    install_with_cargo
    echo "Installed using cargo."
fi

echo
cat <<EOF
Usage Examples
==============

Run with Docker:      docker run -it --rm globe -snc2 -g10
Create an alias:      alias globe='docker run -it --rm globe'
Then, .e.g,           globe -snc2 -g10

Basic Help:           globe -h
Screensaver Mode:     globe -s
With camera rotation: globe -sc2
Add night side and axis rotation: globe -snc2 -g10
Interactive Mode:     globe -i
    (Use arrows/mouse to pan, + and - to adjust speed, PgUp/PgDown to zoom)
Combined interactive features:    globe -inc2 -g10
Listing Mode (highlight coordinates):   echo "0,0.5;0.1,0.5;0.3,0.5" | globe -p
Custom Textures:      globe -in --texture ./your_texture --texture-night ./your_night_texture

Or any of the more complex commands in the same way:
    docker run -it --rm echo "0,0.5;0.1,0.5;0.3,0.5" | globe -p

Enjoy your terminal globe!
EOF

