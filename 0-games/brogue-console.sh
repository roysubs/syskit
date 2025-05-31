#!/bin/bash
# Author: Roy Wiseman 2025-04
set -e # Exit immediately if a command exits with a non-zero status.

REPO="tmewett/BrogueCE"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

echo "BrogueCE Terminal Build and Install Script"
echo "=========================================="
echo "This script will download the latest source code for BrogueCE,"
echo "configure it for terminal play, compile it, and install it"
echo "in your home directory (~/.local/...) with a 'brogue-console' command."
echo

# --- Prerequisites Check ---
echo "Checking for required tools..."
REQUIRED_COMMANDS="curl jq make gcc tar sed tput file" # Added 'file' command
MISSING_COMMANDS=""

for cmd in $REQUIRED_COMMANDS; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "  '$cmd' NOT found."
        MISSING_COMMANDS="$MISSING_COMMANDS $cmd"
    else
        echo "  '$cmd' found."
    fi
done

if [ -n "$MISSING_COMMANDS" ]; then
    echo
    echo "Error: The following required commands were not found:$MISSING_COMMANDS"
    echo "Please install them using your distribution's package manager and try again:"
    echo "  For Debian/Ubuntu: sudo apt update && sudo apt install build-essential curl jq file" # build-essential includes make, gcc. file for 'file' cmd.
    echo "  For Fedora/RHEL:   sudo dnf install curl jq make gcc tar sed ncurses-compat-libs file" # tput in ncurses, file for 'file' cmd.
    echo "  For Arch Linux:    sudo pacman -S base-devel curl jq file" # base-devel includes most, file for 'file' cmd.
    exit 1
fi

# --- Ncurses Development Headers Check ---
echo "Checking for essential build dependencies (like ncurses development headers)..."
NCURSES_FOUND=false
if command -v pkg-config &> /dev/null && pkg-config --exists ncurses 2>/dev/null; then
    NCURSES_FOUND=true
elif [ -f "/usr/include/ncurses.h" ] || [ -f "/usr/include/ncurses/ncurses.h" ] || [ -f "/usr/local/include/ncurses.h" ] || [ -f "/usr/local/include/ncurses/ncurses.h" ]; then
    NCURSES_FOUND=true
fi

if [ "$NCURSES_FOUND" = true ]; then
    echo "  Ncurses development headers (ncurses.h) appear to be installed."
else
    echo; echo "--------------------------------------------------------------------------------"
    echo "Error: Crucial ncurses development headers (e.g., ncurses.h) were NOT found."
    echo "These are REQUIRED to compile the terminal version of BrogueCE."
    echo "Please install the appropriate package for your system and then re-run this script:"; echo
    echo "  For Debian/Ubuntu (and derivatives like Mint, Pop!_OS):"; echo "    sudo apt install libncurses-dev"; echo
    echo "  For Fedora/RHEL (and derivatives like CentOS, AlmaLinux):"; echo "    sudo dnf install ncurses-devel"; echo
    echo "  For Arch Linux (and derivatives like Manjaro):"; echo "    sudo pacman -S ncurses"
    echo "--------------------------------------------------------------------------------"; echo
    echo "Installation aborted due to missing critical dependency."
    exit 1
fi
echo

SCRIPT_CWD="$PWD"
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory for downloads and build: $TEMP_DIR"

cleanup() {
    echo; echo "Cleaning up temporary files from $TEMP_DIR..."
    cd "$SCRIPT_CWD" || cd /tmp || exit_code_cd_fail=$?
    if [ -n "$exit_code_cd_fail" ]; then echo "Warning: Could not cd back to $SCRIPT_CWD or /tmp before cleanup."; fi
    rm -rf "$TEMP_DIR"; echo "Cleanup complete."
}
trap cleanup EXIT
cd "$TEMP_DIR" || { echo "Error: Failed to change to temporary directory '$TEMP_DIR'"; exit 1; }

echo "Finding the latest release for ${REPO}..."
RELEASE_INFO=$(curl -fSsL "$API_URL")
TAG_NAME=$(echo "$RELEASE_INFO" | jq -r '.tag_name')
TARBALL_URL=$(echo "$RELEASE_INFO" | jq -r '.tarball_url')

if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" == "null" ]; then
    echo "Error: Could not retrieve latest release tag name. API Response: $RELEASE_INFO"; exit 1; fi
if [ -z "$TARBALL_URL" ] || [ "$TARBALL_URL" == "null" ]; then
    echo "Error: Could not retrieve tarball URL. API Response: $RELEASE_INFO"; exit 1; fi

echo "Found latest version: $TAG_NAME"; echo "Download URL: $TARBALL_URL"; echo
echo "Downloading source code archive from '$TARBALL_URL'..."
curl -fSLJO "$TARBALL_URL"
DOWNLOADED_FILE=$(ls -t -- *.tar.gz 2>/dev/null | head -n 1)

if [ -z "$DOWNLOADED_FILE" ] || [ ! -f "$DOWNLOADED_FILE" ]; then
    echo "Error: Download failed or no .tar.gz file was found."; exit 1; fi
FILENAME="$DOWNLOADED_FILE"
echo "Downloaded archive: '$FILENAME'."; echo
echo "Extracting source code from '$FILENAME'..."
EXTRACTED_DIR_NAME=$(tar -tf "$FILENAME" | head -n 1 | cut -d'/' -f1)

if [ -z "$EXTRACTED_DIR_NAME" ]; then
    echo "Error: Could not determine the top-level directory name from archive."; tar -tvf "$FILENAME"; exit 1; fi
if [ -d "$EXTRACTED_DIR_NAME" ]; then rm -rf "$EXTRACTED_DIR_NAME"; fi
tar -xzf "$FILENAME"
if [ ! -d "$EXTRACTED_DIR_NAME" ]; then echo "Error: Extraction failed."; exit 1; fi
echo "Extracted to '$EXTRACTED_DIR_NAME'."; echo

echo "Navigating into '$EXTRACTED_DIR_NAME' and configuring for terminal support..."
cd "$EXTRACTED_DIR_NAME" || { echo "Error: Failed to cd to '$EXTRACTED_DIR_NAME'"; exit 1; }
if [ ! -f "config.mk" ]; then echo "Error: config.mk not found."; exit 1; fi

cp config.mk config.mk.bak
echo "Backed up config.mk to config.mk.bak"
echo "Modifying config.mk for a terminal-only (curses) build..."

if grep -q -E '^[[:space:]]*#?[[:space:]]*TERMINAL[[:space:]]*:=' config.mk; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*(TERMINAL[[:space:]]*:=).*$/\1 YES/' config.mk
else echo "TERMINAL := YES" >> config.mk; fi
echo "  Ensured TERMINAL is set to YES."

if grep -q -E '^[[:space:]]*#?[[:space:]]*SDL[[:space:]]*:=' config.mk; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*(SDL[[:space:]]*:=).*$/\1 NO/' config.mk
else echo "SDL := NO" >> config.mk; fi
echo "  Ensured SDL is set to NO."

if grep -q -E '^[[:space:]]*#?[[:space:]]*GRAPHICS[[:space:]]*:=' config.mk; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*(GRAPHICS[[:space:]]*:=).*$/\1 NO/' config.mk
else echo "GRAPHICS := NO" >> config.mk; fi
echo "  Ensured GRAPHICS is set to NO."

sed -i -E '/^[[:space:]]*#?[[:space:]]*DATADIR[[:space:]]*([:=])=/d' config.mk
echo "DATADIR = ." >> config.mk
echo "  Ensured DATADIR is set to '.'"

CONFIG_VALID=true
if ! grep -qE '^[[:space:]]*TERMINAL[[:space:]]*:=[[:space:]]*YES' config.mk; then echo "Error: config.mk: TERMINAL not YES."; CONFIG_VALID=false; fi
if ! grep -qE '^[[:space:]]*SDL[[:space:]]*:=[[:space:]]*NO' config.mk; then echo "Error: config.mk: SDL not NO."; CONFIG_VALID=false; fi
if ! grep -qE '^[[:space:]]*GRAPHICS[[:space:]]*:=[[:space:]]*NO' config.mk; then echo "Error: config.mk: GRAPHICS not NO."; CONFIG_VALID=false; fi
if ! tail -n 5 config.mk | grep -qE '^[[:space:]]*DATADIR[[:space:]]*=[[:space:]]*\.' && ! grep -qE '^[[:space:]]*DATADIR[[:space:]]*=[[:space:]]*\.' config.mk; then
    echo "Error: config.mk: DATADIR not '.'."; CONFIG_VALID=false; fi

if [ "$CONFIG_VALID" = true ]; then echo "Successfully configured config.mk for terminal build."; else
    echo "Critical Error: config.mk invalid."; cat config.mk; exit 1; fi
echo

echo "Compiling BrogueCE..."
if make -B; then echo "Compilation reported success by make."; else
    echo "Error: Compilation failed (make command returned an error)."; exit 1; fi

# --- Locate and Verify Actual Compiled Binary ---
# The Makefile might create a wrapper script in the root and the binary in ./bin/
COMPILED_EXECUTABLE_NAME="brogue" # Standard name
CANDIDATE_PATH_ROOT="./${COMPILED_EXECUTABLE_NAME}"
CANDIDATE_PATH_BIN="./bin/${COMPILED_EXECUTABLE_NAME}"
ACTUAL_EXECUTABLE_PATH=""

echo "Locating actual compiled binary..."
if [ -f "$CANDIDATE_PATH_BIN" ] && ! (file "$CANDIDATE_PATH_BIN" | grep -q -E "script|text executable"); then
    echo "  Found binary executable at '$CANDIDATE_PATH_BIN'."
    ACTUAL_EXECUTABLE_PATH="$CANDIDATE_PATH_BIN"
elif [ -f "$CANDIDATE_PATH_ROOT" ] && ! (file "$CANDIDATE_PATH_ROOT" | grep -q -E "script|text executable"); then
    echo "  Found binary executable at '$CANDIDATE_PATH_ROOT'."
    ACTUAL_EXECUTABLE_PATH="$CANDIDATE_PATH_ROOT"
else
    echo "Error: Could not find a compiled binary executable named '$COMPILED_EXECUTABLE_NAME'."
    echo "Checked paths: '$CANDIDATE_PATH_ROOT' and '$CANDIDATE_PATH_BIN'."
    if [ -f "$CANDIDATE_PATH_ROOT" ]; then echo "  Info for '$CANDIDATE_PATH_ROOT': $(file "$CANDIDATE_PATH_ROOT")"; fi
    if [ -f "$CANDIDATE_PATH_BIN" ]; then echo "  Info for '$CANDIDATE_PATH_BIN': $(file "$CANDIDATE_PATH_BIN")"; fi
    exit 1
fi
echo "Using '$ACTUAL_EXECUTABLE_PATH' as the BrogueCE binary."

echo "Verifying '$ACTUAL_EXECUTABLE_PATH'..."
if [ ! -x "$ACTUAL_EXECUTABLE_PATH" ]; then
    echo "Error: The file '$ACTUAL_EXECUTABLE_PATH' is not executable."
    ls -l "$ACTUAL_EXECUTABLE_PATH"
    exit 1
fi
echo "Verification successful: '$ACTUAL_EXECUTABLE_PATH' is a valid executable binary."
echo

# --- Installation ---
INSTALL_BASE="$HOME/.local"
GAME_INSTALL_DIR_NAME="brogue-ce-terminal" # Name of the directory within $INSTALL_BASE/share/games
INSTALL_DIR="$INSTALL_BASE/share/games/$GAME_INSTALL_DIR_NAME"
BIN_DIR="$INSTALL_BASE/bin"
LAUNCHER_NAME="brogue-console"
WRAPPER_SCRIPT_PATH="$BIN_DIR/$LAUNCHER_NAME"

echo "Installing BrogueCE to '$INSTALL_DIR'..."
echo "Launcher script will be created at '$WRAPPER_SCRIPT_PATH'."

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
echo "Created installation directory '$INSTALL_DIR' and binary directory '$BIN_DIR'."

# Copy the actual compiled binary, renaming it to 'brogue' in the install dir
echo "  Copying binary '$ACTUAL_EXECUTABLE_PATH' to '$INSTALL_DIR/brogue'..."
cp "$ACTUAL_EXECUTABLE_PATH" "$INSTALL_DIR/brogue" # Ensure it's named 'brogue' for the wrapper

# Define other files and directories to copy from the build directory root
# (relative to $EXTRACTED_DIR_NAME where 'make' was run)
FILES_TO_COPY_DATA=("unicode_maps.txt" "scores.txt")
DIRECTORIES_TO_COPY_DATA=("scores" "licenses") # scores/ often holds high scores

echo "Copying data files and directories to '$INSTALL_DIR'..."
for item in "${FILES_TO_COPY_DATA[@]}"; do
    if [ -f "./$item" ]; then echo "  Copying file './$item'..."; cp "./$item" "$INSTALL_DIR/";
    else echo "  Warning: Data file './$item' not found in build directory root. It might be optional."; fi
done
for dir_item in "${DIRECTORIES_TO_COPY_DATA[@]}"; do
    if [ -d "./$dir_item" ]; then echo "  Copying directory './$dir_item'..."; rsync -a --exclude='.gitkeep' "./$dir_item/" "$INSTALL_DIR/$dir_item/";
    elif [[ "$dir_item" == "scores" ]]; then echo "  Note: Optional directory './$dir_item/' not found. Game might create it.";
    else echo "  Warning: Data directory './$dir_item/' not found."; fi
done
if [ -f "./README.md" ]; then echo "  Copying file './README.md'..."; cp "./README.md" "$INSTALL_DIR/"; fi
echo "Finished copying files."

echo "Creating launcher script '$WRAPPER_SCRIPT_PATH'..."
cat << EOF > "$WRAPPER_SCRIPT_PATH"
#!/bin/bash
# Launcher for BrogueCE (Terminal)
# Installed by brogue-console.sh script

GAME_DIR="${INSTALL_DIR}"      # Fixed path to game files
GAME_EXEC_NAME="brogue"        # Name of the executable within GAME_DIR
REQUIRED_WIDTH=100
REQUIRED_HEIGHT=34

if ! command -v tput &> /dev/null; then
    echo "Error: 'tput' command not found. Cannot check terminal size." >&2
    echo "Please install it (e.g., on Debian/Ubuntu: sudo apt install ncurses-bin)." >&2
    exit 1
fi

CURRENT_WIDTH=\$(tput cols)
CURRENT_HEIGHT=\$(tput lines)

if [ "\$CURRENT_WIDTH" -lt "\$REQUIRED_WIDTH" ] || [ "\$CURRENT_HEIGHT" -lt "\$REQUIRED_HEIGHT" ]; then
    echo "BrogueCE requires a terminal window of at least \${REQUIRED_WIDTH}x\${REQUIRED_HEIGHT} characters."
    echo "Your current terminal size is \${CURRENT_WIDTH}x\${CURRENT_HEIGHT}."
    echo "Please resize your terminal and try again."
    exit 1
fi

echo "Terminal size OK. Launching BrogueCE from \${GAME_DIR}..."
cd "\$GAME_DIR" || { echo "Error: Could not change directory to \$GAME_DIR" >&2; exit 1; }

# Ensure the game executable exists and is executable
if [ ! -f "./\$GAME_EXEC_NAME" ]; then
    echo "Error: Game executable './\$GAME_EXEC_NAME' not found in '\$GAME_DIR'." >&2
    ls -l . # List directory contents for debugging
    exit 1
elif [ ! -x "./\$GAME_EXEC_NAME" ]; then
    echo "Error: Game executable './\$GAME_EXEC_NAME' is not executable in '\$GAME_DIR'." >&2
    ls -l "./\$GAME_EXEC_NAME" # Show permissions for debugging
    exit 1
fi

# Execute the game, replacing the current shell process.
# The -t flag is typically for terminal mode in BrogueCE.
exec "./\$GAME_EXEC_NAME" -t

# If exec fails, the script will continue here.
echo "Critical Error: Failed to execute BrogueCE binary at \$GAME_DIR/\$GAME_EXEC_NAME." >&2
echo "This should not happen if the file exists and is executable." >&2
exit 1
EOF
chmod +x "$WRAPPER_SCRIPT_PATH"
echo "Created and made executable: '$WRAPPER_SCRIPT_PATH'."; echo

echo "------------------------------------------------------------------"
echo "BrogueCE Terminal version has been successfully built and installed!"
echo "------------------------------------------------------------------"
echo
echo "Installation Details:"
echo "  Game files:         '$INSTALL_DIR'"
echo "  Launcher script:    '$WRAPPER_SCRIPT_PATH' (named '$LAUNCHER_NAME')"
echo
echo "How to Run:"
echo "1. Ensure '$BIN_DIR' (i.e., '$HOME/.local/bin') is in your system's PATH."
echo "   This is standard on many Linux systems. If it's your first time using this"
echo "   directory, you might need to log out and log back in, or open a new terminal,"
echo "   or manually refresh your shell environment (e.g., by running 'source ~/.bashrc',"
echo "   'source ~/.zshrc', or 'source ~/.profile', depending on your shell)."
echo
echo "2. Once '$BIN_DIR' is in your PATH, you can run the game by typing:"
echo "   $LAUNCHER_NAME"
echo
echo "Customization:"
echo "  If you prefer to launch it from a different location (e.g., a '~/games' directory),"
echo "  you can create a symbolic link to the launcher:"
echo "    mkdir -p \"\$HOME/games\"  # If it doesn't exist"
echo "    ln -s \"$WRAPPER_SCRIPT_PATH\" \"\$HOME/games/$LAUNCHER_NAME\""
echo "  Then you could run it via '~/games/$LAUNCHER_NAME'."
echo
echo "Troubleshooting:"
echo "  If '$LAUNCHER_NAME' command is not found: verify '$BIN_DIR' is in your PATH ('echo \$PATH')."
echo "  If game fails to start: try running it directly from its installation directory to see"
echo "  more specific errors:   cd \"$INSTALL_DIR\" && ./brogue -t"
echo
echo "Script finished."
