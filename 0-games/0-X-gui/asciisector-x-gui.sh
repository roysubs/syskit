#!/bin/bash
# Author: Roy Wiseman 2025-03

# Auto-elevate script if it was not run with sudo
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Ascii Sector Installation Script

# This script downloads, installs, and sets up Ascii Sector on a Debian-based system.
# It assumes you have a graphical environment available to run the game,
# as Ascii Sector is likely a GUI application requiring graphics rendering.

echo "=================================================="
echo " Ascii Sector Installation Script"
echo "=================================================="
echo ""
echo "IMPORTANT: Due to issues with official download links and temporary links"
echo "on sites like myabandonware, you need to manually obtain the direct download"
echo "URL from the website before proceeding."
echo ""
echo "Please follow these steps:"
echo "1. Go to the Ascii Sector Linux page on myabandonware:"
echo "   https://www.myabandonware.com/game/ascii-sector-blh#Linux"
echo "2. Find and click the download button that generates the temporary download link."
echo "3. Once the download link appears (or the download starts), copy the direct download URL."
echo "   You can often do this by right-clicking the download link and selecting 'Copy Link Address'"
echo "   or by using your browser's developer tools (usually F12, Network tab)."
echo ""

# Prompt the user to paste the download link
read -p "Please paste the temporary download link here and press Enter: " DOWNLOAD_URL

# Define the target system-wide installation directory
# Changed to a more standard location for the game's binaries
INSTALL_DIR="/usr/local/games/asciisec"
# Define the name for the downloaded file (adjust if the file name is different)
# You might want to inspect the downloaded file name after a manual download attempt
DOWNLOAD_FILE="asciisector_linux64.tar.gz" # Adjust if necessary based on the actual downloaded file name
# Define the path for the symbolic link in a common PATH directory
LINK_PATH="/usr/local/bin/asciisec"

echo ""
echo "Proceeding with installation..."
echo "--------------------------------------------------"

# --- IMPORTANT CHECK: Ensure DOWNLOAD_URL has been updated ---
if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: No download URL was provided."
    echo "Please run the script again and paste the temporary download link when prompted."
    exit 1
fi

# The auto-elevation snippet handles the root check now.

# 1. Install required library
echo "Installing required library: libsdl2-mixer-2.0-0..."
apt update
if apt install -y libsdl2-mixer-2.0-0; then
    echo "Required library installed successfully."
else
    echo "Error: Failed to install required library. Please check your internet connection and package sources."
    # Attempt to clean up downloaded file if it exists
    rm -f "$DOWNLOAD_FILE"
    exit 1
fi

# 2. Download the file
echo "Attempting to download Ascii Sector from $DOWNLOAD_URL..."
# Use -O to specify the output filename
wget -O "$DOWNLOAD_FILE" "$DOWNLOAD_URL"

# Check if the download was successful
if [ $? -ne 0 ]; then
    echo "Error: Download failed."
    echo "Reasons could include: The provided URL is incorrect, the temporary link has expired, or the server is unreachable."
    echo "Please re-obtain a fresh temporary link from myabandonware and run the script again."
    # Clean up the potentially bad download file
    rm -f "$DOWNLOAD_FILE"
    exit 1
fi

echo "Download complete."

# 3. Create a temporary directory for extraction
echo "Creating temporary extraction directory..."
TEMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    echo "Error: Failed to create temporary directory."
    rm -f "$DOWNLOAD_FILE"
    exit 1
fi
echo "Temporary directory created: $TEMP_DIR"

# 4. Extract the archive into the temporary directory
echo "Extracting $DOWNLOAD_FILE to $TEMP_DIR..."
# Use -x for extract, -z for gzip (for .tar.gz), -v for verbose, -f for filename, -C for changing directory
# If the downloaded file is a different format (e.g., .zip), you'll need a different extraction command (e.g., unzip)
tar -xzf "$DOWNLOAD_FILE" -C "$TEMP_DIR"

# Check if extraction was successful
if [ $? -ne 0 ]; then
    echo "Error: Extraction failed."
    echo "The downloaded file might be corrupted or not a valid archive."
    echo "Attempting to clean up..."
    rm -f "$DOWNLOAD_FILE"
    rm -rf "$TEMP_DIR" # Remove temporary directory and its contents
    exit 1
fi

echo "Extraction complete."

# 5. Find the actual extracted game directory within the temporary directory
# This assumes the archive extracts into a single top-level directory
EXTRACTED_GAME_SUBDIR=$(find "$TEMP_DIR" -maxdepth 1 -mindepth 1 -type d -print -quit)

if [ -z "$EXTRACTED_GAME_SUBDIR" ] || [ ! -d "$EXTRACTED_GAME_SUBDIR" ]; then
     echo "Error: Could not find a single extracted subdirectory within the temporary directory."
     echo "The archive structure might be unexpected. Please inspect the contents of the downloaded archive manually."
     echo "Attempting to clean up..."
     rm -f "$DOWNLOAD_FILE"
     rm -rf "$TEMP_DIR"
     exit 1
fi
echo "Identified extracted game directory: $(basename "$EXTRACTED_GAME_SUBDIR")"

# 6. Create the final installation directory
echo "Creating final installation directory: $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Check if the directory creation was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to create installation directory: $INSTALL_DIR"
    echo "Attempting to clean up..."
    rm -f "$DOWNLOAD_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Installation directory created."

# 7. Move the *contents* of the extracted game directory to the final installation location
echo "Moving game files from $EXTRACTED_GAME_SUBDIR/* to $INSTALL_DIR/..."
# Use mv to move the contents
if mv "$EXTRACTED_GAME_SUBDIR"/* "$INSTALL_DIR/"; then
    echo "Game files moved successfully."
else
    echo "Error: Failed to move game files to $INSTALL_DIR."
    echo "Attempting to clean up..."
    rm -f "$DOWNLOAD_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 8. Clean up the downloaded archive and temporary directory
echo "Cleaning up downloaded archive $DOWNLOAD_FILE and temporary directory $TEMP_DIR..."
rm -f "$DOWNLOAD_FILE"
rm -rf "$TEMP_DIR"

echo "Cleanup complete."

# 9. Make the main executable file runnable
# The executable should now be directly inside the INSTALL_DIR
EXECUTABLE_PATH="$INSTALL_DIR/asciisec" # Assuming the executable is named 'asciisec'

if [ -f "$EXECUTABLE_PATH" ]; then
    echo "Making executable file runnable: $EXECUTABLE_PATH..."
    chmod +x "$EXECUTABLE_PATH"
    echo "Executable is now runnable."
else
    echo "Warning: Could not find the expected executable file at $EXECUTABLE_PATH after moving."
    echo "You may need to manually navigate to $INSTALL_DIR and find the correct executable,"
    echo "then make it runnable using 'chmod +x <executable_name>'."
    echo "The contents of the installation directory are in $INSTALL_DIR."
fi

# 10. Create a symbolic link in /usr/local/bin for easy execution
echo "Creating symbolic link for easy execution: $LINK_PATH -> $EXECUTABLE_PATH..."
# Remove existing link if it exists
if [ -L "$LINK_PATH" ]; then
    echo "Existing symbolic link found at $LINK_PATH. Removing it."
    rm "$LINK_PATH"
fi

if ln -s "$EXECUTABLE_PATH" "$LINK_PATH"; then
    echo "Symbolic link created successfully."
else
    echo "Warning: Failed to create symbolic link at $LINK_PATH."
    echo "You may need to manually create it or run the game directly from $EXECUTABLE_PATH."
fi

echo ""
echo "=================================================="
echo " Ascii Sector installation script finished."
echo "=================================================="
echo "Ascii Sector is likely a GUI application. If you are running in a console-only"
echo "environment, attempting to run it may result in graphics-related errors like:"
echo "  'libEGL warning: failed to open /dev/dri/renderD128: Permission denied'"
echo "To run the game, you will need a graphical environment (like X or Wayland)"
echo "and potentially X forwarding if connecting via SSH."
echo ""
echo "To make the 'asciisec' command available in your current terminal session,"
echo "you need to refresh your shell's configuration. You can do this by:"
echo "  Running: source ~/.bashrc"
echo "  OR logging out of your SSH session and logging back in."
echo ""
echo "You should now be able to run the game by simply typing 'asciisec' in your terminal."
echo "If the symbolic link wasn't created or doesn't work, you can run it directly from:"
echo "  $EXECUTABLE_PATH"
echo ""


