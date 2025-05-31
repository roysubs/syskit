#!/bin/bash
# Author: Roy Wiseman 2025-05

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
INSTALL_DIR="/usr/local/bin" # Standard location for system-wide executables
API_URL="https://api.github.com/repos/sharkdp/fd/releases/latest"
REQUIRED_CMDS=("curl" "tar" "gzip" "find" "sudo" "jq") # List of required commands

# --- Trap for Cleanup ---
# Use a temporary directory for download and extraction
TEMP_DIR=$(mktemp -d)
# Ensure temporary directory is removed on exit, even if errors occur
trap 'echo "Cleaning up temporary directory: $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT

echo "Starting fd installation script..."

# --- Function to check if a command exists ---
command_exists() {
    command -v "$1" &> /dev/null
}

# --- Function to check prerequisites ---
check_prerequisites() {
    echo "Checking for required commands: ${REQUIRED_CMDS[*]}..."
    local missing_cmds=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command_exists "$cmd"; then
            missing_cmds+=("$cmd")
        fi
    done

    if [ ${#missing_cmds[@]} -ne 0 ]; then
        echo "Error: The following required commands are not installed: ${missing_cmds[*]}"
        echo "Please install them using your distribution's package manager (e.g., apt, yum, dnf, pacman) and run the script again."
        echo "For example, on Debian/Ubuntu:"
        echo "  sudo apt-get update && sudo apt-get install ${missing_cmds[*]}"
        return 1 # Indicate failure
    else
        echo "All required commands are installed."
        return 0 # Indicate success
    fi
}

# --- Function to get the latest release info from GitHub ---
get_latest_release_info() {
    echo "Fetching latest release information from GitHub..."
    local release_info
    if ! release_info=$(curl -s "$API_URL"); then
        echo "Error: Failed to fetch release information from $API_URL."
        return 1
    fi

    LATEST_VERSION=$(echo "$release_info" | jq -r '.tag_name')
    LATEST_DATE=$(echo "$release_info" | jq -r '.published_at' | cut -d'T' -f1) # Get only the date part
    DOWNLOAD_URL=$(echo "$release_info" | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-gnu\\.tar\\.gz$")) | .browser_download_url') # Target 64-bit Linux tar.gz

    if [ -z "$LATEST_VERSION" ] || [ -z "$LATEST_DATE" ] || [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not parse latest release information or find a suitable download URL from GitHub API."
        echo "Please check the releases page manually: https://github.com/sharkdp/fd/releases/latest"
        return 1
    fi
    return 0
}

# --- Function to get the currently installed fd version ---
get_current_fd_version() {
    if command_exists fd; then
        CURRENT_VERSION=$(fd --version 2>&1 | awk '{print $2}')
        # Remove potential 'v' prefix if present in the output
        CURRENT_VERSION=${CURRENT_VERSION#v}
        echo "Currently installed fd version: $CURRENT_VERSION"
        return 0 # fd is installed
    else
        echo "fd is not currently installed."
        CURRENT_VERSION="" # Set to empty if not installed
        return 1 # fd is not installed
    fi
}

# --- Function to compare versions ---
# Returns: 0 if versions are the same
#          1 if latest is newer
#          2 if current is newer (shouldn't happen with official releases)
#          3 if one version is empty/invalid
compare_versions() {
    local current="$1"
    local latest="$2"

    if [ -z "$current" ] || [ -z "$latest" ]; then
        return 3 # Invalid versions
    fi

    # Use sort -V for version-aware comparison
    # Check if sort supports -V
    if ! sort --help 2>&1 | grep -q "\-V"; then
        echo "Warning: Your sort command does not support version sorting (-V)."
        echo "Cannot reliably compare versions. Assuming upgrade is needed."
        return 1 # Assume latest is newer if sort -V is not available
    fi


    if [ "$current" = "$latest" ]; then
        return 0 # Same version
    elif [[ "$(echo -e "$current\n$latest" | sort -V | tail -n 1)" == "$latest" ]]; then
        return 1 # Latest is newer
    else
        return 2 # Current is newer (unexpected)
    fi
}

# --- Main Script Logic ---

# 1. Get latest release info
if ! get_latest_release_info; then
    exit 1 # Exit if failed to get release info
fi

# Remove 'v' prefix from latest version if present
LATEST_VERSION_CLEAN=${LATEST_VERSION#v}

echo "Latest available fd version is $LATEST_VERSION_CLEAN released on $LATEST_DATE."

# 2. Check installed version
# CORRECTED CALL: Put the function call inside an if to handle the return status with set -e
if get_current_fd_version; then
    CURRENT_FD_INSTALLED=0 # Function returned 0 (installed)
else
    CURRENT_FD_INSTALLED=1 # Function returned non-zero (not installed or error)
fi
# Now CURRENT_FD_INSTALLED is correctly set (0 or 1), and set -e didn't trigger an exit here.


# 3. Determine if installation/upgrade is needed
NEEDS_INSTALL=false
if [ $CURRENT_FD_INSTALLED -eq 0 ]; then
    compare_versions "$CURRENT_VERSION" "$LATEST_VERSION_CLEAN"
    VERSION_COMPARISON_RESULT=$?

    if [ $VERSION_COMPARISON_RESULT -eq 0 ]; then
        echo "Your currently installed version ($CURRENT_VERSION) is the latest ($LATEST_VERSION_CLEAN)."
        # NEEDS_INSTALL remains false
    elif [ $VERSION_COMPARISON_RESULT -eq 1 ]; then
        echo "Your currently installed version ($CURRENT_VERSION) is older than the latest ($LATEST_VERSION_CLEAN)."
        echo "An upgrade is available."
        NEEDS_INSTALL=true
    elif [ $VERSION_COMPARISON_RESULT -eq 2 ]; then
         echo "Warning: Your currently installed version ($CURRENT_VERSION) appears to be newer than the latest GitHub release ($LATEST_VERSION_CLEAN)."
         echo "This is unexpected. Skipping installation/upgrade."
         # NEEDS_INSTALL remains false
    else # $VERSION_COMPARISON_RESULT is 3 (invalid versions)
         echo "Warning: Could not reliably compare versions ($CURRENT_VERSION vs $LATEST_VERSION_CLEAN)."
         echo "Assuming upgrade is needed. Proceeding with potential installation."
         NEEDS_INSTALL=true
    fi
else # Not currently installed (CURRENT_FD_INSTALLED is 1)
    # The "fd is not currently installed." message was already printed by the function.
    echo "A fresh installation is required."
    NEEDS_INSTALL=true
fi

# --- Handle Installation/Upgrade if needed ---
if [ "$NEEDS_INSTALL" = true ]; then

    # Describe the tool
    echo ""
    echo "----------------------------------------------------"
    echo "fd: A simple, fast and user-friendly alternative to 'find'."
    echo "It features a more intuitive syntax, colorized output,"
    echo "and is often faster than find. It ignores hidden files"
    echo "and directories by default and respects .gitignore."
    echo "You are about to install version $LATEST_VERSION_CLEAN ($LATEST_DATE)."
    echo "----------------------------------------------------"
    echo ""

    # Check prerequisites again before prompting
    if ! check_prerequisites; then
        exit 1 # Exit if prerequisites are missing
    fi

    # Prompt user to continue
    read -r -p "Do you want to continue with the installation? (y/N) " response
    response=${response,,} # Convert to lowercase

    if [[ "$response" =~ ^(yes|y)$ ]]; then
        echo "Proceeding with installation..."

        # --- Download the archive ---
        ARCHIVE_NAME=$(basename "$DOWNLOAD_URL")
        echo "Downloading $ARCHIVE_NAME to $TEMP_DIR..."
        if ! curl -L -o "$TEMP_DIR/$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
            echo "Error: Download failed."
            exit 1
        fi

        # --- Extract the archive ---
        echo "Extracting $ARCHIVE_NAME..."
        if ! tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR"; then
             echo "Error: Extraction failed."
             exit 1
        fi

        # --- Find the executable ---
        echo "Finding the 'fd' executable..."
        # Find the extracted directory (usually starts with fd-)
        EXTRACTED_CONTENTS=$(find "$TEMP_DIR" -maxdepth 1 -mindepth 1 -type d -name "fd-*" -print -quit)

        FD_EXECUTABLE=""
        if [ -z "$EXTRACTED_CONTENTS" ]; then
             echo "Warning: Could not find typical extracted directory in $TEMP_DIR. Searching for executable directly."
             FD_EXECUTABLE=$(find "$TEMP_DIR" -maxdepth 1 -type f -name "fd" -print -quit)
        else
            # Find the fd executable within the extracted directory/contents
            FD_EXECUTABLE=$(find "$EXTRACTED_CONTENTS" -name fd -type f -print -quit)
        fi

        if [ -z "$FD_EXECUTABLE" ]; then
            echo "Error: Could not find 'fd' executable after extraction."
            exit 1
        fi

        echo "Found executable at: $FD_EXECUTABLE"

        # --- Install the executable ---
        echo "Installing 'fd' to $INSTALL_DIR (requires sudo)..."
        if ! sudo cp "$FD_EXECUTABLE" "$INSTALL_DIR/"; then
            echo "Error: Failed to copy executable to $INSTALL_DIR. Check permissions or use sudo."
            exit 1
        fi

        # Ensure the executable has execute permissions
        echo "Setting execute permissions..."
        if ! sudo chmod +x "$INSTALL_DIR/fd"; then
            echo "Error: Failed to set execute permissions for $INSTALL_DIR/fd."
            # Continue as installation might still work, but warn the user
        fi

        echo "'fd' installed successfully to $INSTALL_DIR."

        # Check if INSTALL_DIR is in PATH after potential installation/upgrade
        if command_exists fd; then
             echo "'fd' is now found in your PATH."
             fd --version
        else
            echo "'fd' was installed to $INSTALL_DIR, but this directory is not currently in your PATH."
            echo "To use 'fd', you may need to add $INSTALL_DIR to your PATH."
            echo "You can do this by adding the following line to your shell configuration file (e.g., ~/.bashrc, ~/.zshrc):"
            echo 'export PATH="$PATH:'"$INSTALL_DIR"'"'
            echo "After adding, you might need to run 'source ~/.bashrc' (or your file) or open a new terminal session."
        fi

    else
        echo "Installation cancelled by user."
        # The script will continue to the usage examples section below
    fi
else
    # If NEEDS_INSTALL was false (already latest version or newer)
    echo "Skipping installation/upgrade as it's not needed."
fi


# --- Usage Examples (Printed regardless of installation outcome) ---
echo ""
echo "----------------------------------------------------"
echo "fd: Useful Examples (A faster, friendlier 'find')"
echo "----------------------------------------------------"
echo "Note: By default, fd ignores hidden files/directories and .gitignore patterns."
echo ""

echo "1. Find files containing 'config' in the current directory and subdirectories:"
echo "   fd config"
echo ""

echo "2. Find files ending with '.log':"
echo "   fd -e log"
echo ""

echo "3. Find files ending with '.conf' or '.cfg':"
echo "   fd -e conf -e cfg"
echo ""

echo "4. Find files case-insensitively (default, but -i is explicit):"
echo "   fd -i README"
echo ""

echo "5. Find files case-sensitively (-s):"
echo "   fd -s README"
echo ""

echo "6. Find directories only (-t d) named 'src':"
echo "   fd -t d src"
echo ""

echo "7. Find files only (-t f) named 'main':"
echo "   fd -t f main"
echo ""

echo "8. Find files/directories named 'temp' including hidden ones (-H):"
echo "   fd -H temp"
echo ""

echo "9. Find files matching 'report' limiting search depth to 2 levels (-d 2):"
echo "   fd -d 2 report"
echo ""

echo "10. Find files matching a regular expression (e.g., files starting with 'data-'):"
echo "    fd '^data-.*'"
echo ""

echo "11. Find files and print their full path (-p):"
echo "    fd config -p"
echo ""

echo "12. Find files and execute a command on each result (-x), e.g., list details:"
echo "    fd '.txt' -x ls -l"
echo ""

echo "13. Find files and execute a command, passing multiple results at once (+):"
echo "    fd '.jpg' -x jpegoptim {} +"
echo ""

# Corrected example for -E to show excluding file patterns from results
echo "14. Find '.txt' files but exclude any ending with '.old.txt' (-E):"
echo "    fd '.txt' -E '.old.txt$'"
echo ""


echo "15. Find files and print only their names relative to the search path (-n):"
echo "    fd config -n"
# Added a potentially more common use case for -n
echo "    # Or find files and execute a command, but only show the relative path in output:"
echo "    # fd .gitignore -x echo {} -n # Note: -n usually affects fd's output, not the command output"
# Let's stick to the simpler example.

echo "16. Search in a specific directory (e.g., /var/log) for files ending in .log:"
echo "    fd .log /var/log"
echo ""

echo "17. Search using the full path for matching (e.g., path contains 'backup'):"
echo "    fd -P backup"
echo ""

echo "18. Search for empty files (-s 0):"
echo "    fd -s 0"
echo ""

echo "19. Search for files smaller than 1MB (-s -1M):"
echo "    fd -s -1M"
echo ""

echo "20. Search for files larger than 1GB (-s +1G):"
echo "    fd -s +1G"
echo ""
# Added a useful one related to file permissions/modes
echo "21. Find executable files (-t x):"
echo "    fd -t x"

# Added a couple more common/useful ones
echo ""
echo "22. Search interactively using fzf (if installed):"
echo "    fd . | fzf"
echo ""
echo "23. Find files modified within a specific time range (requires 'find', fd doesn't have this):"
echo "    # To find files modified in the last 5 minutes (using find):"
echo "    # find . -mmin -5"


echo "For more options and details, see the man page: man fd"
echo "Or visit the official documentation: https://github.com/sharkdp/fd"

echo ""
echo "Script finished."
