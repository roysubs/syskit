#!/bin/bash
# Author: Roy Wiseman 2025-05

# Define the download URL
DOWNLOAD_URL="https://www.adom.de/home/download/current/adom_linux_debian_64_3.3.3.tar.gz"
# Define the target installation directory
INSTALL_DIR="/usr/local/adom"
# Define the link location
LINK_DIR="/usr/local/bin"
# Define the name of the executable (common for ADOM)
EXECUTABLE_NAME="adom"
# Define the name of the downloaded file
TAR_FILE=$(basename "$DOWNLOAD_URL")
# Define a temporary directory for download and extraction
TEMP_DIR=$(mktemp -d)

echo "Starting ADOM installation..."

# --- Step 1: Download the game archive ---
echo "Downloading $TAR_FILE..."
wget "$DOWNLOAD_URL" -O "$TEMP_DIR/$TAR_FILE"
# Check if download was successful
if [ $? -ne 0 ]; then
    echo "Error: Download failed. Exiting."
    rm -rf "$TEMP_DIR" # Clean up temporary directory
    exit 1
fi
echo "Download complete."

# --- Step 2: Create installation directory ---
echo "Creating installation directory $INSTALL_DIR..."
# Use sudo as /usr/local typically requires root permissions
sudo mkdir -p "$INSTALL_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create installation directory. Exiting."
    rm -rf "$TEMP_DIR" # Clean up temporary directory
    exit 1
fi
echo "Installation directory created."

# --- Step 3: Extract the archive ---
echo "Extracting $TAR_FILE to $INSTALL_DIR..."
# Extract the contents of the tar.gz file into the installation directory
# The --strip-components 1 is used assuming the tarball has a single top-level directory
sudo tar -xzf "$TEMP_DIR/$TAR_FILE" -C "$INSTALL_DIR" --strip-components 1
# Check if extraction was successful
if [ $? -ne 0 ]; then
    echo "Error: Extraction failed. Exiting."
    # Clean up partially extracted files and temporary directory
    sudo rm -rf "$INSTALL_DIR"/* # Be careful with this! Only if extraction failed.
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Extraction complete."

# --- Step 4: Install missing dependencies (libncurses5) ---
echo "Checking for and installing missing dependencies (libncurses5)..."
# Update package list and install libncurses5
sudo apt update
if [ $? -ne 0 ]; then
    echo "Warning: Failed to update package list. Dependency installation might fail."
fi
sudo apt install libncurses5 -y
if [ $? -ne 0 ]; then
    echo "Error: Failed to install libncurses5. ADOM may not run. Exiting."
    # Clean up installation directory and temporary directory
    sudo rm -rf "$INSTALL_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "libncurses5 installed successfully."


# --- Step 5: Find the executable and create symbolic link ---
echo "Creating symbolic link for the executable..."

# Find the actual executable path within the installation directory
# This assumes the executable is directly under INSTALL_DIR after extraction
EXECUTABLE_PATH="$INSTALL_DIR/$EXECUTABLE_NAME"

# Check if the executable exists
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: ADOM executable not found at $EXECUTABLE_PATH. Exiting."
    # Clean up installation directory and temporary directory
    sudo rm -rf "$INSTALL_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Create the symbolic link in /usr/local/bin
# Use sudo for creating the link in /usr/local/bin
sudo ln -sf "$EXECUTABLE_PATH" "$LINK_DIR/$EXECUTABLE_NAME"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create symbolic link. Exiting."
    # Clean up installation directory and temporary directory
    sudo rm -rf "$INSTALL_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Symbolic link created: $LINK_DIR/$EXECUTABLE_NAME -> $EXECUTABLE_PATH"

# --- Step 6: Clean up temporary files ---
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
echo "Temporary files removed."

echo "ADOM installation finished successfully!"
echo "You can now run ADOM by typing 'adom' in your terminal."

# --- Step 7: Display basic game controls ---
echo ""
echo "--- Basic ADOM Controls ---"
echo "Movement: Arrow keys or numeric keypad"
echo "s: Search"
echo "i: Inventory"
echo "d: Drop item"
echo "g / ,: Get item"
echo "e: Eat food"
echo "q: Quaff potion"
echo "r: Read scroll/book"
echo "a: Apply item"
echo "> : Descend stairs"
echo "< : Ascend stairs"
echo "c: Chat with NPC"
echo "o: Open door/chest"
echo "C: Close door"
echo "k: Kick"
echo "z: Zap wand"
echo "t: Throw item"
echo "f: Fire missile weapon"
echo "?: In-game help"
echo "Ctrl+S: Save game"
echo "Q: Quit game"
echo ".: Wait one turn"
echo ";: Look around"
echo "---------------------------"

# Ensure the script is executable: chmod +x your_script_name.sh
# Run the script with root privileges: sudo ./your_script_name.sh

