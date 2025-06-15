#!/bin/bash
# Author: Roy Wiseman 2025-05

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
INSTALL_DIR="/usr/local/bin"
API_URL="https://api.github.com/repos/sharkdp/fd/releases/latest"
REQUIRED_CMDS=("curl" "tar" "gzip" "find" "sudo" "jq")

# --- Trap for Cleanup ---
TEMP_DIR=$(mktemp -d)
trap 'echo "Cleaning up temporary directory: $TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT

echo "Starting fd installation script..."

# --- Function to check if a command exists ---
command_exists() {
    command -v "$1" &> /dev/null
}

# --- Function to get the latest release info from GitHub ---
get_latest_release_info() {
    echo "Fetching latest release information from GitHub..."
    local release_info
    local curl_headers=()

    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Found GITHUB_TOKEN. Using authenticated API request."
        curl_headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    else
        echo "No GITHUB_TOKEN found. Using unauthenticated API request."
    fi

    # *** FINAL FIX: Set User-Agent to the standard curl version to pass network filters ***
    if ! release_info=$(curl -L --fail -s -A "curl/8.5.0" "${curl_headers[@]}" "$API_URL"); then
        echo "Error: Failed to fetch release information from $API_URL."
        echo "This may be due to a network issue, a firewall, or API rate limiting."
        return 1
    fi

    LATEST_VERSION=$(echo "$release_info" | jq -r '.tag_name')
    LATEST_DATE=$(echo "$release_info" | jq -r '.published_at' | cut -d'T' -f1)
    DOWNLOAD_URL=$(echo "$release_info" | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-gnu\\.tar\\.gz$")) | .browser_download_url')

    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ] || [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not parse latest release information or find a suitable download URL."
        echo "Received Data: $release_info"
        return 1
    fi
    return 0
}

# --- Function to get the currently installed fd version ---
get_current_fd_version() {
    if command_exists fd; then
        CURRENT_VERSION=$(fd --version 2>&1 | awk '{print $2}')
        CURRENT_VERSION=${CURRENT_VERSION#v}
        echo "Currently installed fd version: $CURRENT_VERSION"
        return 0
    else
        echo "fd is not currently installed."
        CURRENT_VERSION=""
        return 1
    fi
}

# --- Function to compare versions ---
compare_versions() {
    local current="$1"
    local latest="$2"

    if [ -z "$current" ] || [ -z "$latest" ]; then return 3; fi
    if ! sort --help 2>&1 | grep -q "\-V"; then
        echo "Warning: Your sort command does not support version sorting (-V). Assuming upgrade is needed."
        return 1
    fi
    if [ "$current" = "$latest" ]; then return 0;
    elif [[ "$(echo -e "$current\n$latest" | sort -V | tail -n 1)" == "$latest" ]]; then return 1;
    else return 2; fi
}

# --- Main Script Logic ---
if ! get_latest_release_info; then exit 1; fi

LATEST_VERSION_CLEAN=${LATEST_VERSION#v}
echo "Latest available fd version is $LATEST_VERSION_CLEAN released on $LATEST_DATE."

if get_current_fd_version; then CURRENT_FD_INSTALLED=0; else CURRENT_FD_INSTALLED=1; fi

NEEDS_INSTALL=false
if [ $CURRENT_FD_INSTALLED -eq 0 ]; then
    compare_versions "$CURRENT_VERSION" "$LATEST_VERSION_CLEAN"
    case $? in
        0) echo "Your currently installed version ($CURRENT_VERSION) is the latest." ;;
        1) echo "An upgrade is available from $CURRENT_VERSION to $LATEST_VERSION_CLEAN."; NEEDS_INSTALL=true ;;
        2) echo "Warning: Your version ($CURRENT_VERSION) is newer than the latest release ($LATEST_VERSION_CLEAN)." ;;
        *) echo "Warning: Could not compare versions. Assuming upgrade is needed."; NEEDS_INSTALL=true ;;
    esac
else
    echo "A fresh installation is required."
    NEEDS_INSTALL=true
fi

if [ "$NEEDS_INSTALL" = true ]; then
    echo ""
    echo "----------------------------------------------------"
    echo "fd: A simple, fast and user-friendly alternative to 'find'."
    echo "You are about to install version $LATEST_VERSION_CLEAN ($LATEST_DATE)."
    echo "----------------------------------------------------"
    echo ""

    if ! command -v "jq" &> /dev/null || ! command -v "tar" &> /dev/null; then
        echo "Error: 'jq' and 'tar' are required. Please install them."
        exit 1
    fi

    read -r -p "Do you want to continue with the installation? (y/N) " response
    if [[ ! "${response,,}" =~ ^(yes|y)$ ]]; then
        echo "Installation cancelled by user."
        exit 0
    fi

    echo "Proceeding with installation..."
    ARCHIVE_NAME=$(basename "$DOWNLOAD_URL")
    echo "Downloading $ARCHIVE_NAME to $TEMP_DIR..."
    if ! curl -L -o "$TEMP_DIR/$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
        echo "Error: Download failed."
        exit 1
    fi

    echo "Extracting $ARCHIVE_NAME..."
    if ! tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR"; then
        echo "Error: Extraction failed."
        exit 1
    fi

    echo "Finding the 'fd' executable..."
    FD_EXECUTABLE=$(find "$TEMP_DIR" -name fd -type f -print -quit)
    if [ -z "$FD_EXECUTABLE" ]; then
        echo "Error: Could not find 'fd' executable after extraction."
        exit 1
    fi
    echo "Found executable at: $FD_EXECUTABLE"

    echo "Installing 'fd' to $INSTALL_DIR (requires sudo)..."
    if ! sudo cp "$FD_EXECUTABLE" "$INSTALL_DIR/"; then
        echo "Error: Failed to copy executable to $INSTALL_DIR."
        exit 1
    fi
    if ! sudo chmod +x "$INSTALL_DIR/fd"; then
        echo "Warning: Failed to set execute permissions for $INSTALL_DIR/fd."
    fi

    echo "'fd' installed successfully to $INSTALL_DIR."
    if command_exists fd; then
        echo "'fd' is now found in your PATH."
        fd --version
    else
        echo "'fd' was installed to $INSTALL_DIR, but this directory is not in your PATH."
        echo "Please add it to your shell's config file (e.g., ~/.bashrc, ~/.zshrc)."
    fi
else
    echo "Skipping installation/upgrade as it's not needed."
fi

echo ""
echo "Script finished."
