#!/bin/bash
# Author: Roy Wiseman 2025-05

# --- Game Information ---
GAME_NAME="Ambassador of Pain"
GAME_DESCRIPTION="Ambassador of Pain (aop) is a curses based arcade game for Linux/UNIX,\nknown for its incredibly small size (only 64 lines of source code)."
GAME_VERSION="0.6"
# Updated: Using an archive link from the official GitHub repository
# The previous URL (ibiblio) returned a 404 Not Found error.
DOWNLOAD_URL="https://github.com/hit-sys/Ambassador-Of-Pain/archive/c3f00fd32935bc463221db8433d29becb83ec749.tar.gz"
DOWNLOAD_FILE="aop_github_source.tar.gz" # Give the downloaded file a consistent local name
INSTALL_DIR="/usr/local/share/games/aop"
BIN_DIR="/usr/local/bin"
EXEC_NAME="aop" # Expected name of the compiled executable
LINK_NAME="aop" # The name of the symlink in /usr/local/bin

# --- Installation Script ---

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.

clear # Clear the terminal for a clean output

echo "--- ${GAME_NAME} Installation Script ---"
echo ""
echo "About:"
echo -e "$GAME_DESCRIPTION"
echo ""

echo "This script will attempt to download, compile, and install ${GAME_NAME}."
echo ""

# --- Check for necessary commands ---
echo "Checking for required tools..."
REQUIRED_CMDS=("wget" "tar" "gcc")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        echo "Please install it using your distribution's package manager (e.g., sudo apt install $cmd or sudo yum install $cmd)."
        exit 1
    fi
done
# Also need curses development headers, but checking for those packages is distro-specific.
echo "Please ensure you have curses development headers installed (e.g., libncurses-dev or ncurses-devel)."
echo ""

# --- Confirmation ---
read -p "Proceed with installation? (y/n): " confirm
if [[ $confirm != [yY]* ]]; then
    echo "Installation cancelled by user."
    exit 1
fi
echo ""

# --- Define Installation Paths ---
echo "Game source and executable will be installed to: ${INSTALL_DIR}"
echo "A symbolic link will be created in: ${BIN_DIR}"
echo ""

# --- Create Installation Directories ---
echo "Creating installation directories (requires sudo)..."
# Use || exit 1 for clarity with set -e
sudo mkdir -p "${INSTALL_DIR}" || { echo "Error: Failed to create directory ${INSTALL_DIR}."; exit 1; }
sudo mkdir -p "${BIN_DIR}" || { echo "Error: Failed to create directory ${BIN_DIR}."; exit 1; }
echo "Directories created."
echo ""

# --- Create Temporary Directory ---
TEMP_DIR=$(mktemp -d)
if [[ ! -d "${TEMP_DIR}" ]]; then
    echo "Error: Failed to create temporary directory."
    exit 1
fi
echo "Using temporary directory: ${TEMP_DIR}"

# Ensure the temporary directory is removed on script exit (success or failure)
trap 'echo "Cleaning up temporary directory: ${TEMP_DIR}..." && rm -rf "$TEMP_DIR"' EXIT

cd "${TEMP_DIR}" || { echo "Error: Failed to change to temporary directory."; exit 1; }

# --- Download Source Code ---
echo "Downloading source code from ${DOWNLOAD_URL}..."
# Use the defined DOWNLOAD_FILE name for the local copy
if ! wget "${DOWNLOAD_URL}" -O "${DOWNLOAD_FILE}"; then
    echo "Error: Failed to download ${DOWNLOAD_FILE}."
    echo "The download URL might have changed again. Please check the official source or mirrors."
    exit 1
fi
echo "Download complete."
echo ""

# --- Extract Source Code ---
echo "Extracting source code..."
if ! tar -xzf "${DOWNLOAD_FILE}"; then
    echo "Error: Failed to extract ${DOWNLOAD_FILE}."
    exit 1
fi
echo "Extraction complete."
echo ""

# --- Navigate to Source Directory ---
# Find the extracted directory name (assuming it's the first entry in the tarball and a directory)
EXTRACTED_DIR=$(tar -tf "${DOWNLOAD_FILE}" | head -n 1 | cut -d '/' -f 1)
if [[ -z "${EXTRACTED_DIR}" || ! -d "${EXTRACTED_DIR}" ]]; then
    echo "Error: Could not determine or find the extracted directory from the archive."
    exit 1
fi

echo "Changing to source directory: ${EXTRACTED_DIR}"
cd "${EXTRACTED_DIR}" || { echo "Error: Failed to change to extracted directory ${EXTRACTED_DIR}."; exit 1; }

# --- Compile Game ---
echo "Compiling the game..."
# The source is usually a single file named aop.c
if ! gcc -Wall -Wextra aop.c -o "${EXEC_NAME}" -lcurses; then
    echo "Error: Compilation failed."
    echo "Please ensure 'gcc' and 'curses' development headers are installed."
    exit 1
fi
echo "Compilation successful."
echo ""

# --- Install Compiled Executable ---
if [[ ! -f "${EXEC_NAME}" ]]; then
    echo "Error: Compiled executable '${EXEC_NAME}' not found after compilation."
    exit 1
fi

echo "Installing executable to ${INSTALL_DIR} (requires sudo)..."
if ! sudo cp "${EXEC_NAME}" "${INSTALL_DIR}/"; then
    echo "Error: Failed to copy executable to ${INSTALL_DIR}."
    exit 1
fi
echo "Executable installed."
echo ""

# --- Install Level Files ---
echo "Installing level files to ${INSTALL_DIR} (requires sudo)..."
# Copy all .txt files from the extracted source directory to the install directory
if ! sudo cp "${TEMP_DIR}/${EXTRACTED_DIR}"/*.txt "${INSTALL_DIR}/"; then
    echo "Warning: Failed to copy level files to ${INSTALL_DIR}."
    echo "The game might not work correctly without level files."
    # Do not exit here, as the executable itself was installed, maybe levels are optional?
    # But it's better to warn the user.
fi
echo "Level files installed (if found)."
echo ""

# --- Create Symbolic Link ---
echo "Creating symbolic link ${BIN_DIR}/${LINK_NAME} pointing to ${INSTALL_DIR}/${EXEC_NAME} (requires sudo)..."
# Use -f to force overwrite if the link already exists
if ! sudo ln -sf "${INSTALL_DIR}/${EXEC_NAME}" "${BIN_DIR}/${LINK_NAME}"; then
    echo "Error: Failed to create symbolic link ${BIN_DIR}/${LINK_NAME}."
    exit 1
fi
echo "Symbolic link created."
echo ""

# --- Installation Complete ---
echo "--- Installation Complete ---"
echo "${GAME_NAME} has been successfully installed!"
echo ""
echo "You should now be able to run the game by simply typing '${LINK_NAME}' in your terminal."
echo "(You might need to open a new terminal session or run 'exec \$SHELL' for the new command to be found immediately.)"
echo ""

# --- Game Rules and Keybindings ---
echo "--- ${GAME_NAME} Rules and Keybindings ---"
echo ""
echo "Rules:"
echo "- The goal is to survive as long as possible and score points."
echo "- You are represented by the character '@'."
echo "- Avoid collision with other characters on the screen (the 'pain')."
echo "- Points accumulate over time simply by surviving."
echo ""
echo "Keybindings:"
echo "- Movement: Use the Arrow Keys (Up, Down, Left, Right)."
echo "- Movement (Alternatives): You might also be able to use h(left), j(down), k(up), l(right) (common in curses games)."
echo "- Quit: Press 'q' to exit the game."
echo ""

exit 0 # Script finished successfully
