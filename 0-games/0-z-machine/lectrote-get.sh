#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to download and install Lectrote Interactive Fiction player
# Fetches precompiled Linux binaries from GitHub.

# --- Configuration ---
APP_NAME="Lectrote"
LECTROTE_VERSION="1.5.3" # Latest known stable as of May 2025 (based on provided info)
INSTALL_DIR_BASE="/opt" # Base directory for application bundle
INSTALL_APP_DIR_NAME="Lectrote" # App will be in /opt/Lectrote
APP_EXECUTABLE_NAME_IN_BUNDLE="Lectrote" # Actual name of the executable file inside the app bundle
SYMLINK_NAME="lectrote" # Desired command name (lowercase)
SYMLINK_PATH="/usr/local/bin/${SYMLINK_NAME}"

# Variables to be determined by architecture
ARCH=""
DOWNLOAD_FILE=""
DOWNLOAD_URL=""
EXTRACTED_TOP_LEVEL_DIR_PATTERN="Lectrote-linux-"

# --- Colors ---
COL_RESET='\033[0m'
COL_RED='\033[0;31m'
COL_GREEN='\033[0;32m'
COL_YELLOW='\033[0;33m'
COL_BLUE='\033[0;34m'
COL_MAGENTA='\033[0;35m'
COL_CYAN='\033[0;36m'
COL_WHITE='\033[1;37m'

# --- Helper Functions ---
print_header() {
    echo -e "${COL_MAGENTA}=======================================================================${COL_RESET}"
    echo -e "${COL_WHITE}$1${COL_RESET}"
    echo -e "${COL_MAGENTA}=======================================================================${COL_RESET}"
}

print_subheader() {
    echo -e "\n${COL_CYAN}>>> $1${COL_RESET}"
}

print_info() {
    echo -e "${COL_BLUE}INFO: $1${COL_RESET}"
}

print_success() {
    echo -e "${COL_GREEN}SUCCESS: $1${COL_RESET}"
}

print_warning() {
    echo -e "${COL_YELLOW}WARNING: $1${COL_RESET}"
}

print_error() {
    echo -e "${COL_RED}ERROR: $1${COL_RESET}" >&2
}

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Brief Introduction and Confirmation ---
print_header "${APP_NAME} - IF Interpreter Setup"
echo ""
print_info "${APP_NAME} is an Interactive Fiction interpreter based on the Electron shell."
print_info "This script will download the precompiled binary for Linux and install it."
echo ""
read -p "Do you want to continue with the installation of ${APP_NAME} ${LECTROTE_VERSION}? (Y/n): " initial_confirmation
if [[ "$initial_confirmation" == [nN] || "$initial_confirmation" == [nN][oO] ]]; then
    print_info "Installation aborted by user."
    exit 0
fi

# --- Determine Architecture and Set Download URL ---
MACHINE_ARCH=$(uname -m)
if [[ "$MACHINE_ARCH" == "x86_64" ]]; then
    ARCH="x64"
elif [[ "$MACHINE_ARCH" == "aarch64" ]] || [[ "$MACHINE_ARCH" == "arm64" ]]; then
    ARCH="arm64"
else
    print_error "Unsupported architecture: $MACHINE_ARCH. This script currently supports x64 (x86_64) and arm64 (aarch64)."
    exit 1
fi
print_info "Detected architecture: $ARCH"

DOWNLOAD_FILE="Lectrote-${LECTROTE_VERSION}-linux-${ARCH}.zip"
DOWNLOAD_URL="https://github.com/erkyrath/lectrote/releases/download/lectrote-${LECTROTE_VERSION}/${DOWNLOAD_FILE}"
EXTRACTED_CONTENT_DIR_NAME="${EXTRACTED_TOP_LEVEL_DIR_PATTERN}${ARCH}" # e.g., Lectrote-linux-x64
FINAL_INSTALL_PATH="${INSTALL_DIR_BASE}/${INSTALL_APP_DIR_NAME}"

# --- Check if Lectrote is Already Installed ---
if command -v ${SYMLINK_NAME} &>/dev/null && [[ -L "$SYMLINK_PATH" ]]; then
    # Check if the symlink points to the expected installation directory structure
    # This is a basic check; a more thorough one would verify the version.
    if [[ "$(readlink -f "$SYMLINK_PATH")" == "${FINAL_INSTALL_PATH}/${APP_EXECUTABLE_NAME_IN_BUNDLE}" ]]; then
        print_success "${APP_NAME} version linked via ${SYMLINK_NAME} appears to be already installed at ${FINAL_INSTALL_PATH}."
        print_info "To reinstall or update, please remove the existing version first (e.g., sudo rm -rf ${FINAL_INSTALL_PATH} && sudo rm -f ${SYMLINK_PATH})."
        exit 0
    else
         print_warning "${APP_NAME} command found, but it may not be from this script's installation method or version."
    fi
elif [ -d "${FINAL_INSTALL_PATH}" ]; then
    print_warning "${APP_NAME} installation directory ${FINAL_INSTALL_PATH} found, but symlink ${SYMLINK_PATH} is missing or incorrect."
    print_warning "Consider removing ${FINAL_INSTALL_PATH} and rerunning this script for a clean install."
fi

# --- Main Installation Logic ---
print_header "${APP_NAME} Setup Script (Version ${LECTROTE_VERSION})"
print_info "This script will download and install ${APP_NAME} to ${FINAL_INSTALL_PATH}"
print_info "A symlink will be created at ${SYMLINK_PATH} (command: ${SYMLINK_NAME})"
echo ""
read -p "Do you want to continue? (Y/n): " confirmation
if [[ "$confirmation" == [nN] || "$confirmation" == [nN][oO] ]]; then
    print_info "Installation aborted by user."
    exit 0
fi

# --- Check for root/sudo privileges ---
if [[ $EUID -eq 0 ]]; then
    print_info "Script is running as root. Sudo will not be prefixed for commands."
    SUDO_CMD=""
else
    print_info "Script is not running as root. Sudo will be used for system-wide installations."
    SUDO_CMD="sudo"
    if ! $SUDO_CMD -v; then # Test sudo privileges
        print_error "Sudo privileges are required but could not be obtained."
        exit 1
    fi
fi

# 1. Update package lists and install dependencies
print_subheader "Step 1: Installing dependencies (wget, unzip)..."
$SUDO_CMD apt update -qq
$SUDO_CMD apt install -y -qq wget unzip
print_success "Dependencies checked/installed."

# 2. Create a temporary build/download directory
print_subheader "Step 2: Creating temporary download directory..."
DOWNLOAD_TMP_DIR=$(mktemp -d -t lectrote_download_XXXXXX)
print_info "Download directory: ${DOWNLOAD_TMP_DIR}"
cd "$DOWNLOAD_TMP_DIR" || { print_error "Failed to cd into download directory ${DOWNLOAD_TMP_DIR}"; exit 1; }

# 3. Download Lectrote archive
print_subheader "Step 3: Downloading ${APP_NAME} ${LECTROTE_VERSION} (${ARCH})..."
print_info "URL: ${DOWNLOAD_URL}"
if wget --progress=bar:force:noscroll -O "${DOWNLOAD_FILE}" "${DOWNLOAD_URL}"; then
    print_success "${APP_NAME} archive downloaded."
else
    print_error "Failed to download ${APP_NAME} archive from ${DOWNLOAD_URL}."
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} intentionally preserved for debugging."
    exit 1
fi

# 4. Install Lectrote
print_subheader "Step 4: Installing ${APP_NAME} to ${FINAL_INSTALL_PATH}..."
print_info "Extracting ${DOWNLOAD_FILE}..."
if unzip -q "${DOWNLOAD_FILE}"; then
    print_success "Archive extracted."
else
    print_error "Failed to extract ${DOWNLOAD_FILE}."
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} intentionally preserved for debugging."
    exit 1
fi

if [ ! -d "${EXTRACTED_CONTENT_DIR_NAME}" ]; then
    print_error "Extracted content directory '${EXTRACTED_CONTENT_DIR_NAME}' not found in ${DOWNLOAD_TMP_DIR}."
    print_info "Contents of download directory:"
    ls -lA "$DOWNLOAD_TMP_DIR"
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} intentionally preserved for debugging."
    exit 1
fi
print_info "Found extracted directory: ${EXTRACTED_CONTENT_DIR_NAME}"

print_info "Removing old installation (if any) at ${FINAL_INSTALL_PATH}..."
$SUDO_CMD rm -rf "${FINAL_INSTALL_PATH}"
print_info "Creating installation directory ${INSTALL_DIR_BASE} (if it doesn't exist)..."
$SUDO_CMD mkdir -p "${INSTALL_DIR_BASE}"
print_info "Moving extracted content ('${EXTRACTED_CONTENT_DIR_NAME}') to become ${FINAL_INSTALL_PATH}..."
if $SUDO_CMD mv "${EXTRACTED_CONTENT_DIR_NAME}" "${FINAL_INSTALL_PATH}"; then
    print_success "${APP_NAME} application files moved to ${FINAL_INSTALL_PATH}."
else
    print_error "Failed to move extracted files to ${FINAL_INSTALL_PATH}."
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} (with extracted files) is preserved."
    exit 1
fi

print_info "Setting permissions for ${FINAL_INSTALL_PATH}..."
$SUDO_CMD chmod -R a+rX "${FINAL_INSTALL_PATH}"

# 5. Create symlink
print_subheader "Step 5: Creating symlink..."
ACTUAL_EXECUTABLE_PATH="${FINAL_INSTALL_PATH}/${APP_EXECUTABLE_NAME_IN_BUNDLE}" # e.g. /opt/Lectrote/Lectrote

if [ ! -f "${ACTUAL_EXECUTABLE_PATH}" ]; then
    print_error "Lectrote executable not found at expected location: ${ACTUAL_EXECUTABLE_PATH}"
    print_warning "Installation at ${FINAL_INSTALL_PATH} might be incomplete or structured differently."
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} is preserved."
    exit 1
fi
# Check if it's executable, -f just checks if it's a regular file
if [ ! -x "${ACTUAL_EXECUTABLE_PATH}" ]; then
    print_error "Lectrote executable found at ${ACTUAL_EXECUTABLE_PATH} but it is not executable!"
    print_warning "Check permissions. The chmod command might have failed or been insufficient."
    print_warning "Download directory ${DOWNLOAD_TMP_DIR} is preserved."
    exit 1
fi
print_info "Actual executable found at: ${ACTUAL_EXECUTABLE_PATH}"

print_info "Creating symlink from ${ACTUAL_EXECUTABLE_PATH} to ${SYMLINK_PATH} (for command: ${SYMLINK_NAME})"
$SUDO_CMD ln -sf "${ACTUAL_EXECUTABLE_PATH}" "${SYMLINK_PATH}"
print_success "Symlink created. You should now be able to run '${SYMLINK_NAME}'."

# 6. Cleanup
print_subheader "Step 6: Cleaning up temporary files..."
cd /tmp
if rm -rf "$DOWNLOAD_TMP_DIR"; then
    print_success "Temporary download files removed from ${DOWNLOAD_TMP_DIR}."
else
    print_warning "Failed to remove temporary download directory ${DOWNLOAD_TMP_DIR}. You may need to remove it manually."
fi

# 7. Final Verification and Summary
print_header "${APP_NAME} Setup Complete!"
if command -v ${SYMLINK_NAME} &>/dev/null && [[ "$(readlink -f $(command -v ${SYMLINK_NAME}))" == "$ACTUAL_EXECUTABLE_PATH" ]]; then
    print_success "${APP_NAME} is now installed and accessible via the '${SYMLINK_NAME}' command."
    print_info "Application installed to: ${FINAL_INSTALL_PATH}"
    print_info "Executable: ${ACTUAL_EXECUTABLE_PATH}"
    print_info "Symlink (command): ${SYMLINK_PATH}"
    print_info "You might need to run 'hash -r' or open a new terminal for the '${SYMLINK_NAME}' command to be recognized by your shell immediately."
    echo ""
    print_info "To run ${APP_NAME}, type: ${COL_GREEN}${SYMLINK_NAME} /path/to/your/game.ulx${COL_RESET} (or .z5, .gblorb, etc.)"
else
    print_error "Installation verification failed."
    print_error "The '${SYMLINK_NAME}' command may not be set up correctly."
    print_error "Check if ${ACTUAL_EXECUTABLE_PATH} exists and if ${SYMLINK_PATH} points to it."
fi

exit 0
