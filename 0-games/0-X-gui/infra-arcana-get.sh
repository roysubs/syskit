#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script to download and install Infra Arcana
# This script will:
# 1. Check for and install dependencies
# 2. Download the latest binary release
# 3. Install with proper directory structure
# 4. Create working launchers

set -e  # Exit on error
echo "=== Infra Arcana Installation Script ==="

# Create a temporary directory for downloads
TEMP_DIR=$(mktemp -d)
INSTALL_DIR="$HOME/.local/games/infra_arcana"
BIN_LINK_DIR="$HOME/.local/bin"

# Make sure the binary link directory exists and is in PATH
mkdir -p "$BIN_LINK_DIR"
if [[ ":$PATH:" != *":$BIN_LINK_DIR:"* ]]; then
    echo "Adding $BIN_LINK_DIR to your PATH in .bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    echo "NOTE: You'll need to restart your terminal or run 'source ~/.bashrc' for the PATH changes to take effect"
fi

# Function to check and install dependencies
install_dependencies() {
    echo "Checking and installing dependencies..."
    
    # Package lists for different distros
    DEBIAN_DEPS="libsdl2-2.0-0 libsdl2-image-2.0-0 libsdl2-ttf-2.0-0 libsdl2-mixer-2.0-0 wget unzip"
    FEDORA_DEPS="SDL2 SDL2_image SDL2_ttf SDL2_mixer wget unzip"
    ARCH_DEPS="sdl2 sdl2_image sdl2_ttf sdl2_mixer wget unzip"
    
    if command -v apt-get &> /dev/null; then
        echo "Debian/Ubuntu detected"
        sudo apt-get update
        sudo apt-get install -y $DEBIAN_DEPS
    elif command -v dnf &> /dev/null; then
        echo "Fedora detected"
        sudo dnf install -y $FEDORA_DEPS
    elif command -v pacman &> /dev/null; then
        echo "Arch Linux detected"
        sudo pacman -Sy --noconfirm $ARCH_DEPS
    else
        echo "Warning: Could not detect package manager. You may need to install dependencies manually:"
        echo "- SDL2"
        echo "- SDL2_image"
        echo "- SDL2_ttf"
        echo "- SDL2_mixer"
        echo "- wget"
        echo "- unzip"
    fi
}

# Function to download and install the latest release
download_and_install() {
    echo "Downloading the latest Infra Arcana release..."
    
    # Go to temp directory
    cd "$TEMP_DIR"
    
    # Get the latest release from GitHub
    GITHUB_REPO="https://github.com/InfraArcana/ia"
    LATEST_RELEASE_URL=$(wget -qO- "https://api.github.com/repos/InfraArcana/ia/releases/latest" | 
                         grep '"browser_download_url"' | 
                         grep -i "linux" | 
                         grep -v ".asc" | 
                         head -n 1 | 
                         cut -d '"' -f 4)
    
    if [ -z "$LATEST_RELEASE_URL" ]; then
        echo "Could not find the latest release. Attempting to use the releases page directly..."
        LATEST_RELEASE_URL=$(wget -qO- "https://github.com/InfraArcana/ia/releases" | 
                            grep -o 'href="[^"]*linux[^"]*\.zip"' | 
                            head -n 1 | 
                            sed 's/href="/https:\/\/github.com/g' | 
                            sed 's/"//g')
    fi
    
    if [ -z "$LATEST_RELEASE_URL" ]; then
        echo "Failed to find a Linux release. Trying alternative repository..."
        # Try Martin's fork which is actively maintained
        GITHUB_REPO="https://github.com/martin-tornqvist/ia"
        LATEST_RELEASE_URL=$(wget -qO- "https://api.github.com/repos/martin-tornqvist/ia/releases/latest" | 
                             grep '"browser_download_url"' | 
                             grep -i "linux" | 
                             grep -v ".asc" | 
                             head -n 1 | 
                             cut -d '"' -f 4)
    fi
    
    if [ -z "$LATEST_RELEASE_URL" ]; then
        echo "Error: Could not determine the download URL for Infra Arcana"
        exit 1
    fi
    
    echo "Downloading from: $LATEST_RELEASE_URL"
    ARCHIVE_NAME=$(basename "$LATEST_RELEASE_URL")
    wget -O "$ARCHIVE_NAME" "$LATEST_RELEASE_URL"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Extract the archive
    echo "Extracting files..."
    if [[ "$ARCHIVE_NAME" == *.zip ]]; then
        unzip "$ARCHIVE_NAME" -d "$TEMP_DIR/extracted"
    elif [[ "$ARCHIVE_NAME" == *.tar.gz ]]; then
        mkdir -p "$TEMP_DIR/extracted"
        tar -xzf "$ARCHIVE_NAME" -C "$TEMP_DIR/extracted"
    else
        echo "Error: Unknown archive format. Supported formats: .zip, .tar.gz"
        exit 1
    fi
    
    # Find the extracted directory
    EXTRACTED_DIR="$TEMP_DIR/extracted"
    if [ ! -d "$EXTRACTED_DIR" ]; then
        echo "Error: Extraction failed or directory structure unexpected"
        exit 1
    fi
    
    # Check for nested directory structure (common with archives)
    NESTED_DIR=$(find "$EXTRACTED_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ -n "$NESTED_DIR" ] && [ "$(ls -A "$NESTED_DIR" | wc -l)" -gt 0 ]; then
        echo "Found nested directory: $(basename "$NESTED_DIR")"
        EXTRACTED_DIR="$NESTED_DIR"
    fi
    
    # Move all files to the installation directory
    echo "Installing to $INSTALL_DIR..."
    cp -r "$EXTRACTED_DIR"/* "$INSTALL_DIR"/ 2>/dev/null || cp -r "$EXTRACTED_DIR"/.* "$INSTALL_DIR"/ 2>/dev/null || true
    
    # Make binaries executable
    chmod +x "$INSTALL_DIR"/ia "$INSTALL_DIR"/*.sh 2>/dev/null || true
    
    # Find the actual game executable
    echo "Looking for game executables..."
    GAME_EXEC=$(find "$INSTALL_DIR" -name "ia" -type f -perm /u+x -print | head -n 1)
    
    if [ -z "$GAME_EXEC" ]; then
        echo "Warning: Could not find main game executable 'ia'"
        # Look for any executable file as fallback
        GAME_EXEC=$(find "$INSTALL_DIR" -type f -perm /u+x -print | grep -v ".sh" | head -n 1)
        if [ -z "$GAME_EXEC" ]; then
            echo "Error: No executable found in the installation directory"
            exit 1
        fi
    fi
    
    echo "Found game executable: $GAME_EXEC"
    
    # Create the main launcher script that works properly
    echo "Creating launcher scripts..."
    cat > "$INSTALL_DIR/ia_launcher.sh" << EOF
#!/bin/bash
# Change to the game directory (critical for resource loading)
cd "\$(dirname "\$(readlink -f "\$0")")"

# Environment variables to help with SDL compatibility
export SDL_VIDEO_X11_VISUALID=""
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=pulseaudio
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0

# Run the game from the correct directory
./ia "\$@"
EOF
    chmod +x "$INSTALL_DIR/ia_launcher.sh"
    ln -sf "$INSTALL_DIR/ia_launcher.sh" "$BIN_LINK_DIR/ia"
    ln -sf "$INSTALL_DIR/ia_launcher.sh" "$BIN_LINK_DIR/infra-arcana"
    
    # Create a safe mode launcher with more compatibility options
    cat > "$INSTALL_DIR/ia_safe_launcher.sh" << EOF
#!/bin/bash
# Change to the game directory
cd "\$(dirname "\$(readlink -f "\$0")")"

# More aggressive compatibility settings
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_VIDEODRIVER=x11
export SDL_AUDIODRIVER=pulseaudio
export SDL_VIDEO_X11_VISUALID=""
export SDL_RENDER_DRIVER=software
export MESA_GL_VERSION_OVERRIDE=3.0
export __GL_SYNC_TO_VBLANK=0

# Run the game
./ia "\$@"
EOF
    chmod +x "$INSTALL_DIR/ia_safe_launcher.sh"
    ln -sf "$INSTALL_DIR/ia_safe_launcher.sh" "$BIN_LINK_DIR/ia_safe"
    
    echo "Main game launcher created: ia and infra-arcana"
    echo "Safe mode launcher created: ia_safe"
}

# Run the installation
install_dependencies
download_and_install

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "=== Installation Complete ==="
echo ""
echo "To play Infra Arcana:"
echo "  Standard mode: ia or infra-arcana"
echo "  Safe mode (if you encounter issues): ia_safe"
echo ""
echo "NOTE: If you get 'command not found', you need to either:"
echo "  1. Run the command: source ~/.bashrc"
echo "  2. Start a new terminal session"
echo ""
echo "The game runs in graphical mode with X11 forwarding support."
echo "Make sure you have X11 forwarding enabled if using SSH."
echo ""
echo "Infra Arcana - Game Controls Summary:"
echo "------------------------------------"
echo "Movement: Arrow keys or numpad (8/2/4/6 for cardinal directions, 7/9/1/3 for diagonals)"
echo "Wait: Space or 5 on numpad"
echo "Pick up item: g or comma (,)"
echo "Inventory: i"
echo "Equipment: e"
echo "Look around: l or x"
echo "Open/close door: o/c"
echo "Go up/down stairs: < / >"
echo "Cast spell: z"
echo "Reload weapon: r"
echo "Fire ranged weapon: f"
echo "Throw item: t"
echo "Apply/use item: a"
echo "Help: ? (shows all commands)"
echo "Save and quit: S"
echo "Quit without saving: Q"
echo ""
echo "Enjoy your journey into cosmic horror!"
