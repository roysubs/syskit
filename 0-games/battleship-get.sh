#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script name: battleship-get.sh
# Description: Checks for tui-battleship installation, installs if needed,
#              shows rules summary, and prompts to start the game.
# Intended location: Your game setup folder.

BATTLESHIP_CMD="tui-battleship.sh"
REPO_URL="https://gitlab.com/christosangel/tui-battleship.git"
CLONE_DIR_NAME="tui-battleship" # Name of the directory git will create

# Function to display a condensed summary of the rules and controls.
display_summary() {
    echo "==================================="
    echo "  tui-battleship Rules Summary"
    echo "==================================="
    echo "Objective: Destroy the computer's fleet before it destroys yours."
    echo "Grid: 10x10 battlefield."
    echo "Ship Placement: Auto or Manual (ships cannot be adjacent)."
    echo "Configurable: Number of ships, keys, notifications, log, cheatsheet."
    echo ""
    echo "Controls:"
    echo "  Navigate Grid: hjkl or Arrow Keys"
    echo "  Hit Square: f, space, or enter"
    echo ""
    echo "Main Menu Options (access by quitting game):"
    echo "  n: New Game"
    echo "  e: Configure Game Parameters"
    echo "  s: View Statistics"
    echo "  r: View Full Game Rules"
    echo "  q: Quit Game"
    echo ""
    echo "In-Game Options (toggle/action):"
    echo "  i: Toggle Keybinding Cheatsheet"
    echo "  u: Toggle Game Log"
    echo "  r: Restart Current Game"
    echo "  q: Quit to Main Menu"
    echo "==================================="
    echo "" # Add a newline for better spacing
}

# Function to clean up the temporary directory
cleanup_temp_dir() {
    if [ -d "$TMP_DIR" ]; then
        echo "Cleaning up temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
}

# Set a trap to call cleanup_temp_dir on script exit (success or failure)
trap cleanup_temp_dir EXIT

# --- Main Script Logic ---

# 1. Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Error: git command not found." >&2
    echo "Please install git before running this script (e.g., sudo apt-get install git)." >&2
    exit 1
fi

# 2. Check if tui-battleship.sh is already installed in PATH
if command -v "$BATTLESHIP_CMD" &> /dev/null; then
    echo "$BATTLESHIP_CMD found in PATH. Skipping installation."
else
    echo "$BATTLESHIP_CMD not found. Installing..."

    # Create a temporary directory for cloning and installation
    TMP_DIR=$(mktemp -d)
    if [ ! -d "$TMP_DIR" ]; then
        echo "Error: Could not create temporary directory." >&2
        exit 1
    fi
    echo "Using temporary directory: $TMP_DIR"

    # Remember the original directory
    ORIG_DIR=$(pwd)

    # Navigate into the temporary directory
    cd "$TMP_DIR" || { echo "Error: Could not change to temporary directory $TMP_DIR." >&2; exit 1; }

    # Clone the repository
    echo "Cloning repository from $REPO_URL..."
    if ! git clone "$REPO_URL"; then
        echo "Error: Failed to clone repository from $REPO_URL." >&2
        exit 1
    fi

    # Navigate into the cloned directory
    if ! cd "$CLONE_DIR_NAME"; then
        echo "Error: Could not change to cloned directory $CLONE_DIR_NAME." >&2; exit 1;
    fi
    echo "Changed directory to $CLONE_DIR_NAME."

    # Make install.sh executable and run it
    if [ ! -f install.sh ]; then
        echo "Error: install.sh not found in the cloned directory." >&2
        exit 1
    fi

    echo "Making install.sh executable..."
    if ! chmod +x install.sh; then
        echo "Error: Failed to make install.sh executable." >&2
        exit 1
    fi

    echo "Running installation script..."
    # The install script typically installs to ~/.local/bin/
    if ! ./install.sh; then
        echo "Error: Installation script failed." >&2
        exit 1
    fi

    echo "Installation process completed."

    # Navigate back to the original directory
    cd "$ORIG_DIR" || { echo "Error: Could not return to original directory $ORIG_DIR." >&2; exit 1; }

    # Verify installation (optional)
    if command -v "$BATTLESHIP_CMD" &> /dev/null; then
        echo "$BATTLESHIP_CMD successfully installed and found in PATH."
    else
        echo "Warning: Installation finished, but $BATTLESHIP_CMD is still not found in PATH." >&2
        echo "The script is likely installed to ~/.local/bin. Please ensure this directory is in your \$PATH environment variable." >&2
    fi
fi

# 3. Display summary
display_summary

# 4. Wait for user to press a key to start
# read -n 1: Reads exactly one character
# -s: Silent mode (do not echo input character)
# -r: Raw input (do not interpret backslashes)
# -p: Display a prompt
read -n 1 -s -r -p "Press any key to start the game..."

# 5. Execute the game if it's in the PATH
if command -v "$BATTLESHIP_CMD" &> /dev/null; then
    echo "" # Add a newline after the prompt
    echo "Starting $BATTLESHIP_CMD..."
    "$BATTLESHIP_CMD"
else
    echo "" # Add a newline
    echo "Cannot start the game: $BATTLESHIP_CMD is not in your PATH." >&2
    echo "Please ensure the directory where tui-battleship.sh was installed (likely ~/.local/bin) is in your \$PATH." >&2
    exit 1
fi

exit 0
