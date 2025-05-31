#!/bin/bash
# Author: Roy Wiseman 2025-01

# --- Configuration ---
DMAGNETIC_URL="https://www.dettus.net/dMagnetic/dMagnetic_0.37.tar.bz2"
DMAGNETIC_ARCHIVE_NAME="dMagnetic_0.37.tar.bz2"
DMAGNETIC_SOURCE_DIR_NAME="dMagnetic_0.37"

# Adventure game configurations: URL, expected output zip filename, target game data subdirectory
declare -A GAMES
GAMES[Pawn,url]="https://archive.org/download/moofaday_The_Pawn/The%20Pawn%20v2.3%20%28moof-a-day%20collection%29.zip"
GAMES[Pawn,zip_name]="pawn.zip"
GAMES[Pawn,data_dir_name]="pawn"
GAMES[Pawn,mag_file]="Pawn.mag" # Expected main game file
GAMES[Pawn,gfx_file]="Pawn.gfx" # Expected graphics file

GAMES[Guild,url]="https://archive.org/download/Guild_of_Thieves_The_1987_Magnetic_Scrolls_Side_A/Guild_of_Thieves_The_1987_Magnetic_Scrolls_Side_A.zip" # This URL failed in the user's run
GAMES[Guild,zip_name]="guild.zip"
GAMES[Guild,data_dir_name]="guild"
GAMES[Guild,mag_file]="Guild.mag"
GAMES[Guild,gfx_file]="Guild.gfx"

GAMES[Jinxter,url]="https://archive.org/download/Jinxter_1987_Magnetic_Scrolls_Side_A/Jinxter_1987_Magnetic_Scrolls_Side_A.zip"
GAMES[Jinxter,zip_name]="jinxter.zip"
GAMES[Jinxter,data_dir_name]="jinxter"
GAMES[Jinxter,mag_file]="Jinxter.mag"
GAMES[Jinxter,gfx_file]="Jinxter.gfx"


# Installation directory for the binary (user-specific)
INSTALL_BIN_DIR="$HOME/.local/bin"

# Directory for game data (relative to where the script is run)
GAME_DATA_DIR="./magnetic_scrolls_games"

# --- Helper Function for Error Handling ---
exit_on_error() {
    local exit_code=$1
    local msg="$2"
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: $msg (Exit Code: $exit_code)" >&2
        # Note: We do *not* exit here for game downloads/unzips, only for dMagnetic install failure
        if [[ "$msg" != "Failed to download"* && "$msg" != "Failed to unzip"* ]]; then
            exit $exit_code
        fi
    fi
    return $exit_code # Return the original exit code
}

# --- Setup Temporary Build Directory ---
# Create a temporary directory and store its path
TEMP_BUILD_DIR=$(mktemp -d -t dmagnetic_build_XXXX)
exit_on_error $? "Failed to create temporary build directory"
echo "Using temporary build directory: $TEMP_BUILD_DIR"

# Ensure the temporary directory is cleaned up on exit
trap "echo 'Cleaning up temporary build directory: $TEMP_BUILD_DIR'; rm -rf '$TEMP_BUILD_DIR'" EXIT

# Keep track of the original directory to return later
ORIGINAL_DIR=$(pwd)

# --- Download and Compile dMagnetic ---
echo "--- Installing dMagnetic ---"
echo "Changing to temporary build directory..."
cd "$TEMP_BUILD_DIR"
exit_on_error $? "Failed to change to temporary directory $TEMP_BUILD_DIR"

echo "Downloading dMagnetic source..."
wget "$DMAGNETIC_URL" -O "$DMAGNETIC_ARCHIVE_NAME"
exit_on_error $? "Failed to download dMagnetic source"

echo "Extracting dMagnetic source..."
tar xvfj "$DMAGNETIC_ARCHIVE_NAME"
exit_on_error $? "Failed to extract dMagnetic source"

echo "Changing to dMagnetic source directory..."
cd "$DMAGNETIC_SOURCE_DIR_NAME"
exit_on_error $? "Failed to change to dMagnetic source directory"

echo "Compiling dMagnetic..."
make
exit_on_error $? "dMagnetic compilation failed. Do you have a C compiler like GCC installed?"

# --- Install dMagnetic Binary ---
echo "Checking for compiled dMagnetic binary..."
if [ ! -f dMagnetic ]; then
    exit_on_error 1 "dMagnetic executable not found after compilation. Check the make output for errors."
fi
echo "dMagnetic compiled successfully."

echo "Creating installation directory for binaries ($INSTALL_BIN_DIR)..."
mkdir -p "$INSTALL_BIN_DIR"
exit_on_error $? "Failed to create installation directory $INSTALL_BIN_DIR. Check permissions."

echo "Installing dMagnetic binary to $INSTALL_BIN_DIR..."
cp dMagnetic "$INSTALL_BIN_DIR/"
exit_on_error $? "Failed to copy dMagnetic binary to $INSTALL_BIN_DIR. Check permissions."

echo "Setting execute permissions on installed binary..."
chmod +x "$INSTALL_BIN_DIR/dMagnetic"
exit_on_error $? "Failed to set execute permissions on $INSTALL_BIN_DIR/dMagnetic. Check permissions."

echo "dMagnetic binary installed to $INSTALL_BIN_DIR"

# --- Download and Extract Adventure Games ---
echo ""
echo "--- Downloading and Installing Games ---"
# Change back to the original directory before installing games
echo "Changing back to original directory: $ORIGINAL_DIR"
cd "$ORIGINAL_DIR"
exit_on_error $? "Failed to change back to original directory"

echo "Creating directory for game data ($GAME_DATA_DIR)..."
mkdir -p "$GAME_DATA_DIR"
exit_on_error $? "Failed to create game data directory $GAME_DATA_DIR. Check permissions."

declare -a installed_games # Array to store names of successfully installed games
declare -a failed_downloads # Array to store names of games that failed download

# Loop through games, download and unzip individually
for game_name in "${!GAMES[@]}"; do
    # Extract details for the current game
    game_url=${GAMES[${game_name},url]}
    game_zip_name=${GAMES[${game_name},zip_name]}
    game_data_subdir=${GAMES[${game_name},data_dir_name]}
    game_mag_file=${GAMES[${game_name},mag_file]}
    game_gfx_file=${GAMES[${game_name},gfx_file]}

    echo ""
    echo "Attempting to download $game_name from $game_url..."
    # Download zip to the temporary directory
    wget "$game_url" -O "$TEMP_BUILD_DIR/$game_zip_name"
    download_exit_code=$?

    if exit_on_error $download_exit_code "Failed to download $game_name"; then
        # Download successful, now attempt unzip
        echo "Download successful. Attempting to unzip $game_name..."
        unzip "$TEMP_BUILD_DIR/$game_zip_name" -d "$GAME_DATA_DIR/$game_data_subdir"
        unzip_exit_code=$?

        if exit_on_error $unzip_exit_code "Failed to unzip $game_name"; then
            echo "$game_name successfully installed to $GAME_DATA_DIR/$game_data_subdir."
            installed_games+=("$game_name") # Add to list of installed games
        else
             echo "Unzipping $game_name failed. Game data may be incomplete or missing."
             # Not added to installed_games list
        fi
    else
        # Download failed
        failed_downloads+=("$game_name") # Add to list of failed downloads
    fi
done

# Note: The temporary directory and its contents (including downloaded zips and source) will be cleaned up automatically on script exit by the trap.

echo ""
echo "Installation script finished attempting all steps."
echo ""
echo "--- Installation Summary ---"
echo ""

# --- Report Installed Games ---
if [ ${#installed_games[@]} -gt 0 ]; then
    echo "Successfully installed games:"
    for game_name in "${installed_games[@]}"; do
        game_data_subdir=${GAMES[${game_name},data_dir_name]}
        game_mag_file=${GAMES[${game_name},mag_file]}
        game_gfx_file=${GAMES[${game_name},gfx_file]}
        echo "- $game_name (data in $GAME_DATA_DIR/$game_data_subdir)"
    done
else
    echo "No games were successfully installed."
fi

# --- Report Failed Downloads ---
if [ ${#failed_downloads[@]} -gt 0 ]; then
    echo ""
    echo "Failed to download the following games:"
    for game_name in "${failed_downloads[@]}"; do
        game_url=${GAMES[${game_name},url]}
        echo "- $game_name (from $game_url)"
    done
    echo ""
    echo "Please check the URLs and your network connection."
    echo "You may need to find alternative sources for these games (e.g., search Archive.org)."
fi


echo ""
echo "--- How to Use dMagnetic ---"
echo ""
echo "1. Ensure $INSTALL_BIN_DIR is in your system's PATH."
echo "   Most modern Linux distributions add ~/.local/bin to the PATH automatically for desktop sessions."
echo "   If the 'dMagnetic' command is not found after restarting your terminal or logging in again, you may need to add it manually."
echo "   For bash or zsh, add the following line to your ~/.bashrc or ~/.zshrc file:"
echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "   Then run 'source ~/.bashrc' or 'source ~/.zshrc' or restart your terminal."
echo ""
echo "2. Running the games:"
echo "   Once 'dMagnetic' is in your PATH, you can run it from any directory."
echo "   Use the '-mag' flag for the main game file (often ending in .mag) and '-gfx' for the graphics file (often ending in .gfx)."
echo "   The game data for successfully installed games is located in the '$GAME_DATA_DIR' directory (relative to where you ran the script)."
echo ""

# Provide usage examples only for successfully installed games
if [ ${#installed_games[@]} -gt 0 ]; then
    echo "   Examples for installed games:"
    for game_name in "${installed_games[@]}"; do
        game_data_subdir=${GAMES[${game_name},data_dir_name]}
        game_mag_file=${GAMES[${game_name},mag_file]}
        game_gfx_file=${GAMES[${game_name},gfx_file]}
        echo ""
        echo "   To play $game_name:"
        # Use absolute paths for clarity in the examples
        echo "   dMagnetic -mag \"$ORIGINAL_DIR/$GAME_DATA_DIR/$game_data_subdir/$game_mag_file\" -gfx \"$ORIGINAL_DIR/$GAME_DATA_DIR/$game_data_subdir/$game_gfx_file\""
    done
fi

echo ""
echo "For more information about dMagnetic, visit: https://www.dettus.net/dMagnetic/"
echo "To find more Magnetic Scrolls games, search archive.org or other online repositories."
echo ""
