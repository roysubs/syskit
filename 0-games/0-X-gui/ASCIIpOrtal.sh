#!/bin/bash
# Author: Roy Wiseman 2025-04
# https://asciisector.fandom.com/wiki/Ascii_Sector_Wiki

set -e

echo "=== ASCIIpOrtal Build Script ==="

# Config
REPO_URL="https://github.com/cymonsgames/ASCIIpOrtal.git"
TARGET_DIR="$HOME/asciiportal-build"
GAME_DIR="$TARGET_DIR/ASCIIpOrtal"
BIN_PATH="$GAME_DIR/asciiportal"

echo
echo "--- Step 1: Installing build dependencies ---"
sudo apt update
sudo apt install -y \
  build-essential \
  g++ \
  libsdl1.2-dev \
  libsdl-mixer1.2-dev \
  git \
  cmake \
  unzip \
  libyaml-cpp-dev \
  wget

echo
echo "--- Step 2: Cloning ASCIIpOrtal source code ---"
if [ -d "$GAME_DIR" ]; then
    echo "Directory already exists: $GAME_DIR"
else
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    git clone "$REPO_URL"
fi

echo
echo "--- Step 3: Building using system yaml-cpp (make linux) ---"
cd "$GAME_DIR"

# Clean old builds just in case
make clean || true

# Use system yaml-cpp instead of broken bundled version
make linux

echo
echo "=== ✅ BUILD COMPLETE ==="
echo
echo "Game built in:       $GAME_DIR"
echo "Executable binary:   $BIN_PATH"
echo
if [ -f "$BIN_PATH" ]; then
    echo "To play ASCIIpOrtal, run:"
    echo "    cd \"$GAME_DIR\""
    echo "    ./asciiportal"
    echo
    echo "Or you can copy it to /usr/local/bin to run it from anywhere:"
    echo "    sudo cp \"$BIN_PATH\" /usr/local/bin/asciiportal"
    echo
    echo "Then just run:"
    echo "    asciiportal"
    echo
    echo "To create a desktop shortcut (optional):"
    echo "    echo -e \"[Desktop Entry]\\nName=ASCIIpOrtal\\nExec=$BIN_PATH\\nIcon=utilities-terminal\\nType=Application\\nTerminal=true\\nCategories=Game;\" > ~/.local/share/applications/asciiportal.desktop"
    echo "    chmod +x ~/.local/share/applications/asciiportal.desktop"
    echo
else
    echo "❌ Something went wrong. The binary was not found at $BIN_PATH"
    exit 1
fi

