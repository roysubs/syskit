#!/bin/bash
# Author: Roy Wiseman 2025-01

# --- Configuration ---
SOURCE_URL="https://raw.githubusercontent.com/mevdschee/2048.c/master/2048.c"
SOURCE_FILE="2048.c"
EXECUTABLE_NAME="2048"
GAME_DIR="$HOME/games/2048.c"
BIN_DIR="$HOME/.local/bin/"
LINK_PATH="$BIN_DIR/$EXECUTABLE_NAME"

# --- Helper function to check and install dependencies ---
check_and_install_dependency() {
    local command_name="$1"
    local package_name="$2"

    if ! command -v "$command_name" &> /dev/null; then
        echo "Dependency '$command_name' not found. Attempting to install '$package_name'..."

        if command -v apt &> /dev/null; then
            # Debian/Ubuntu based
            sudo apt update && sudo apt install -y "$package_name"
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS based
            sudo yum install -y "$package_name"
        elif command -v dnf &> /dev/null; then
            # Fedora based
            sudo dnf install -y "$package_name"
        elif command -v pacman &> /dev/null; then
            # Arch Linux based
            sudo pacman -Sy --noconfirm "$package_name"
        elif command -v brew &> /dev/null; then
            # macOS using Homebrew
            brew install "$package_name"
        else
            echo "Could not detect a supported package manager (apt, yum, dnf, pacman, brew)."
            echo "Please install '$package_name' manually and run the script again."
            exit 1
        fi

        if [ $? -ne 0 ]; then
            echo "Failed to install '$package_name'. Please install it manually."
            exit 1
        fi
        echo "'$package_name' installed successfully."
    else
        echo "'$command_name' is already installed."
    fi
}

# --- Main Script ---

echo "Starting 2048.c installation..."

# 1. Create game directory
if [ -d "$GAME_DIR" ]; then
    echo "Directory '$GAME_DIR' already exists. Skipping creation."
else
    echo "Creating directory '$GAME_DIR'..."
    mkdir -p "$GAME_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create directory '$GAME_DIR'."
        exit 1
    fi
fi

# 2. Navigate to the directory
echo "Changing directory to '$GAME_DIR'..."
cd "$GAME_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to change directory to '$GAME_DIR'."
    exit 1
fi

# 3. Check and install dependencies
check_and_install_dependency "wget" "wget"
check_and_install_dependency "gcc" "gcc"

# 4. Download the source code
echo "Downloading source code from '$SOURCE_URL'..."
wget "$SOURCE_URL" -O "$SOURCE_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download source code."
    exit 1
fi
echo "Source code downloaded successfully."

# 5. Compile the code
echo "Compiling source code..."
gcc -o "$EXECUTABLE_NAME" "$SOURCE_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to compile source code."
    exit 1
fi
echo "Compilation successful."

# 6. Make the executable runnable
echo "Making the executable runnable..."
chmod +x "$EXECUTABLE_NAME"
if [ $? -ne 0 ]; then
    echo "Error: Failed to make executable runnable."
    exit 1
fi

# 7. Create ~/.local/bin if it doesn't exist
if [ ! -d "$BIN_DIR" ]; then
    echo "Creating directory '$BIN_DIR'..."
    mkdir -p "$BIN_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create directory '$BIN_DIR'."
        exit 1
    fi
fi

# 8. Create symbolic link in ~/bin
echo "Creating symbolic link '$LINK_PATH' -> '$GAME_DIR/$EXECUTABLE_NAME'..."
# Remove existing link if it points elsewhere or is broken
if [ -L "$LINK_PATH" ] || [ -e "$LINK_PATH" ]; then
    echo "Existing link or file at '$LINK_PATH' found. Removing..."
    rm "$LINK_PATH"
fi
ln -s "$GAME_DIR/$EXECUTABLE_NAME" "$LINK_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create symbolic link."
    exit 1
fi
echo "Symbolic link created successfully."

# --- Completion and Game Info ---
echo ""
echo "--------------------------------------------------"
echo "2048.c installation complete!"
echo "The executable is located at: $GAME_DIR/$EXECUTABLE_NAME"
echo "A symbolic link has been created at: $LINK_PATH"
echo ""
echo "--------------------------------------------------"
echo "If the command '$EXECUTABLE_NAME' is not found, you may need to add '$BIN_DIR' to your system's PATH."
echo "You can typically do this by adding the following line to your ~/.bashrc, or ~/.zshrc:"
echo 'export PATH="$HOME/.local/bin:$PATH"'
echo "After adding the line, restart your terminal or run: source ~/.bashrc (or your file)"
echo "--------------------------------------------------"
echo
echo "To run the game, simply type: $EXECUTABLE_NAME"
echo ""
echo "--------------------------------------------------"
echo "About the Game: 2048"
echo "--------------------------------------------------"
echo "2048 is a single-player sliding tile puzzle game."
echo "The objective is to slide numbered tiles on a grid to combine them to create a tile with the number 2048."
echo "Tiles with the same number merge into a single tile with the sum of their numbers (e.g., two 2s merge into a 4, two 4s merge into an 8, and so on)."
echo "A new tile (either 2 or 4) appears on the grid after each move."
echo "The game ends when the grid is full and no more moves are possible (no adjacent tiles with the same value and no empty spaces)."
echo ""
echo "How to Play:"
echo "Use the arrow keys on your keyboard to move the tiles."
echo "When you press an arrow key, all tiles slide in that direction as far as possible."
echo "Tiles with the same number that collide during a slide merge into a new tile."
echo ""
echo "Controls:"
echo "  Up Arrow: Move tiles up"
echo "  Down Arrow: Move tiles down"
echo "  Left Arrow: Move tiles left"
echo "  Right Arrow: Move tiles right"
echo "  'r' key: Restart the game"
echo "  'q' key: Quit the game"
echo ""

exit 0

