#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
set -euo pipefail

# --- Configuration ---
DF_BASE_INSTALL_DIR="/opt/dwarf_fortress_legacy"
DF_SYMLINK="${DF_BASE_INSTALL_DIR}/current"
DF_LAUNCHER="/usr/local/bin/dwarf-fortress-legacy-console"

# --- Hardcoded Target ---
# This is the specific version the user wants to install.
# The URL will not change according to the user.
DOWNLOAD_URL="https://www.bay12games.com/dwarves/df_47_05_linux.tar.bz2"
# Derive version from the download URL (e.g., "0.47.05")
# df_47_05_linux.tar.bz2 -> 47_05. If it were df_0_47_05_linux.tar.bz2, it would be 0_47_05
# We will try to make it 0.47.05
# First, get the filename
TARBALL_FILENAME=$(basename "$DOWNLOAD_URL")
# Extract version parts: df_XX_YY_... or df_0_XX_YY_...
if [[ "$TARBALL_FILENAME" =~ df_0_([0-9]+)_([0-9]+)_linux\.tar\.bz2 ]]; then
    LATEST_VERSION="0.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
elif [[ "$TARBALL_FILENAME" =~ df_([0-9]+)_([0-9]+)_linux\.tar\.bz2 ]]; then
    LATEST_VERSION="0.${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
else
    # Fallback if the pattern is unexpected, though it should match df_47_05_linux.tar.bz2
    log_error "Could not derive version from filename: $TARBALL_FILENAME. Please check the URL pattern."
    # As a last resort, hardcode, but derivation is preferred for slight flexibility.
    # For df_47_05_linux.tar.bz2, the above regex should yield "0.47.05"
    # If you are SURE it's always 0.47.05 from this specific link, you can uncomment next line:
    # LATEST_VERSION="0.47.05"
    # However, if the regex fails, the script will exit due to set -e if LATEST_VERSION is not set.
    # For safety, if regexes fail for the provided link:
    if [ "$TARBALL_FILENAME" == "df_47_05_linux.tar.bz2" ]; then
        LATEST_VERSION="0.47.05"
    else
        echo "[ERROR] Cannot determine LATEST_VERSION from $TARBALL_FILENAME and it's not the expected df_47_05_linux.tar.bz2"
        exit 1
    fi
fi


# --- Helper Functions ---
log() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_warn() {
    echo "[WARN] $1" >&2
}

check_dependencies() {
    log "Checking for required dependencies..."
    local missing_deps=0
    # Reduced dependency list as HTML parsing is removed
    for cmd in curl tar stat mktemp tee chmod ln mkdir rm rmdir basename; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed."
            missing_deps=1
        fi
    done
    if [ "$missing_deps" -eq 1 ]; then
        log_error "Please install missing dependencies and try again."
        exit 1
    fi
    log "All dependencies are satisfied."
}

# --- Main Logic ---
log "Starting Dwarf Fortress Hardcoded Legacy Installer..."
log "Target URL: $DOWNLOAD_URL"
log "Target Version: $LATEST_VERSION"

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    log "This script needs to create directories/files in $DF_BASE_INSTALL_DIR and /usr/local/bin."
    log "It will use 'sudo' for those operations and may prompt for your password."
    if command -v sudo &> /dev/null; then
        SUDO_CMD="sudo"
    else
        log_error "'sudo' command not found, but root privileges are required. Please run as root or install sudo."
        exit 1
    fi
else
    log "Running with root privileges."
fi

check_dependencies

INSTALL_PATH="${DF_BASE_INSTALL_DIR}/${LATEST_VERSION}"

log "Installation path: $INSTALL_PATH"
log "Tarball filename: $TARBALL_FILENAME"

if [ -d "$INSTALL_PATH" ] && ([ -f "$INSTALL_PATH/df" ] || [ -f "$INSTALL_PATH/df_linux/df" ]); then
    log "Dwarf Fortress Legacy version $LATEST_VERSION appears to be already installed at $INSTALL_PATH."
    log "Ensuring symlink $DF_SYMLINK points to $INSTALL_PATH..."
    $SUDO_CMD mkdir -p "$(dirname "$DF_SYMLINK")"
    $SUDO_CMD ln -sfn "$INSTALL_PATH" "$DF_SYMLINK"
    log "Symlink updated."

    LAUNCHER_CONTENT="#!/bin/bash
# Launcher for Dwarf Fortress Legacy Console (Hardcoded Version $LATEST_VERSION)
cd \"${DF_SYMLINK}\" # This should now be ${DF_BASE_INSTALL_DIR}/${LATEST_VERSION}
if [ -f ./df ]; then
    exec ./df
elif [ -d ./df_linux ] && [ -f ./df_linux/df ]; then # Common case if strip-components failed/was not applicable or default structure
    # log_warn \"'df' not in main directory, trying ./df_linux/df\" # User may not want this log during gameplay
    cd ./df_linux
    exec ./df
else
    echo \"ERROR: Could not find the 'df' executable in ${DF_SYMLINK} or ${DF_SYMLINK}/df_linux\" >&2
    exit 1
fi
"
    log "Ensuring launcher script $DF_LAUNCHER is up to date..."
    echo "$LAUNCHER_CONTENT" | $SUDO_CMD tee "$DF_LAUNCHER" > /dev/null
    $SUDO_CMD chmod +x "$DF_LAUNCHER"
    log "Launcher script $DF_LAUNCHER created/updated."
    log "To play, type: $DF_LAUNCHER"
    exit 0
fi

log "Dwarf Fortress Legacy version $LATEST_VERSION not found or installation incomplete. Proceeding..."

TMP_DIR=$(mktemp -d -t df_legacy_install-XXXXXX)
trap 'log "Cleaning up temporary directory $TMP_DIR..."; rm -rf "$TMP_DIR"' EXIT SIGINT SIGTERM

log "Downloading $TARBALL_FILENAME to $TMP_DIR..."
# Target output file for curl is $TMP_DIR/$TARBALL_FILENAME
if $SUDO_CMD curl --fail -Lso "$TMP_DIR/$TARBALL_FILENAME" "$DOWNLOAD_URL"; then
    log "Download successful."
else
    CURL_EXIT_CODE=$?
    log_error "Download failed. Curl exit code: $CURL_EXIT_CODE. URL: $DOWNLOAD_URL"
    # Check if file was partially downloaded or is an error page
    if [ -f "$TMP_DIR/$TARBALL_FILENAME" ]; then
        FILE_SIZE=$($SUDO_CMD stat -c%s "$TMP_DIR/$TARBALL_FILENAME")
        if [ "$FILE_SIZE" -lt 10240 ]; then # Check if it's a tiny file (likely an error page)
            log_error "Downloaded file is very small ($FILE_SIZE bytes). It might be an error page from Bay12 or a redirect."
        fi
    fi
    exit 1
fi

log "Creating installation directory $INSTALL_PATH..."
$SUDO_CMD mkdir -p "$INSTALL_PATH"

log "Extracting $TARBALL_FILENAME to $INSTALL_PATH..."
# Legacy tarballs (like 47.05) usually contain a 'df_linux' folder, so --strip-components=1 is usually needed.
# For df_47_05_linux.tar.bz2, it extracts to a `df_linux` directory.
# So, we want the contents of `df_linux` to be directly in $INSTALL_PATH.
if $SUDO_CMD tar -xjf "$TMP_DIR/$TARBALL_FILENAME" -C "$INSTALL_PATH" --strip-components=1; then
    log "Extraction successful (with --strip-components=1)."
else
    log_error "Extraction with --strip-components=1 failed. The archive structure might be different than expected or the file corrupted."
    log_warn "Attempting extraction without --strip-components=1..."
    if $SUDO_CMD tar -xjf "$TMP_DIR/$TARBALL_FILENAME" -C "$INSTALL_PATH"; then
        log "Extraction successful without --strip-components=1. Game files might be in a subdirectory (e.g., 'df_linux') inside $INSTALL_PATH."
    else
        log_error "Secondary extraction attempt also failed."
        log_error "File is at $TMP_DIR/$TARBALL_FILENAME (will be kept if this error occurs)."
        trap - EXIT SIGINT SIGTERM # Disable auto-cleanup for inspection
        exit 1
    fi
fi

log "Updating symlink $DF_SYMLINK to point to $INSTALL_PATH..."
$SUDO_CMD mkdir -p "$(dirname "$DF_SYMLINK")"
$SUDO_CMD ln -sfn "$INSTALL_PATH" "$DF_SYMLINK"
log "Symlink $DF_SYMLINK created/updated."

LAUNCHER_CONTENT="#!/bin/bash
# Launcher for Dwarf Fortress Legacy Console (Hardcoded Version $LATEST_VERSION)
cd \"${DF_SYMLINK}\" # This should now be ${DF_BASE_INSTALL_DIR}/${LATEST_VERSION}
if [ -f ./df ]; then # Check if 'df' is directly in $INSTALL_PATH
    exec ./df
elif [ -d ./df_linux ] && [ -f ./df_linux/df ]; then # Check if it's in $INSTALL_PATH/df_linux (if strip-components failed or wasn't used)
    # log_warn \"'df' not in main directory, trying ./df_linux/df\"
    cd ./df_linux
    exec ./df
else
    echo \"ERROR: Could not find the 'df' executable in ${DF_SYMLINK} or ${DF_SYMLINK}/df_linux\" >&2
    exit 1
fi
"

log "Creating launcher script $DF_LAUNCHER..."
echo "$LAUNCHER_CONTENT" | $SUDO_CMD tee "$DF_LAUNCHER" > /dev/null
$SUDO_CMD chmod +x "$DF_LAUNCHER"
log "Launcher script created at $DF_LAUNCHER."

# Cleanup is handled by the trap
# rm -rf "$TMP_DIR"
# trap - EXIT SIGINT SIGTERM # Not needed here if trap is EXIT SIGINT SIGTERM

log "Dwarf Fortress Legacy version $LATEST_VERSION installed successfully!"
log "You can run the game by typing: $DF_LAUNCHER"
log "Or by navigating to $DF_SYMLINK (which is $INSTALL_PATH) and running ./df (or ./df_linux/df if the structure is nested)"
exit 0
