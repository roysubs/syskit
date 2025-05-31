#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to download, compile, and install Gargoyle Interactive Fiction player
# Version: 2023.1 (Latest known stable as of May 2024)
#
# --- Brief Introduction and Confirmation ---
print_header "${APP_NAME} - Interactive Fiction Player"
echo ""
print_info "${APP_NAME} is a graphical application used to play all major interactive fiction formats."
print_info "It provides a visually appealing and configurable interface for your text adventures."
print_warning "Important: ${APP_NAME} requires a graphical desktop environment (e.g., X11 or Wayland) to run."
print_warning "It will not work in a text-only console."
echo ""
read -p "Do you want to continue with the installation of ${APP_NAME} ${GARGOYLE_VERSION}? (Y/n): " initial_confirmation
if [[ "$initial_confirmation" == [nN] || "$initial_confirmation" == [nN][oO] ]]; then   # no,nO,No,NO in second option
    print_info "Installation aborted by user."
    exit 0
fi

# --- Configuration ---
APP_NAME="Gargoyle"
GARGOYLE_VERSION="2023.1"
SOURCE_TARBALL="gargoyle-${GARGOYLE_VERSION}.tar.gz"
SOURCE_URL="https://github.com/garglk/garglk/releases/download/${GARGOYLE_VERSION}/${SOURCE_TARBALL}"
INSTALL_EXECUTABLE="/usr/local/bin/gargoyle"
BUILD_DIR_NAME="gargoyle-${GARGOYLE_VERSION}"

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

# --- Gargoyle Help and Summary Function ---
display_gargoyle_summary() {
    print_header "${APP_NAME} Usage Summary"

    print_subheader "Running Gargoyle:"
    echo -e "  To run Gargoyle, simply type: ${COL_GREEN}gargoyle /path/to/your/game.z5${COL_RESET} (or .ulx, .gblorb, etc.)"
    echo -e "  Example: ${COL_GREEN}gargoyle my_adventure.zblorb${COL_RESET}"

    print_subheader "Key Runtime Options (Non-Mac):"
    echo -e "  ${COL_YELLOW}Ctrl + ,${COL_RESET}          : Open Gargoyle's configuration file in a text editor."
    echo -e "  ${COL_YELLOW}Ctrl + .${COL_RESET}          : List paths to all configuration and theme files."
    echo -e "  ${COL_YELLOW}Ctrl + Shift + t${COL_RESET} : Display a list of all available color themes."
    echo -e "  ${COL_YELLOW}Ctrl + Shift + s${COL_RESET} : Save the scrollback buffer (ad hoc transcript)."
    echo -e "  ${COL_YELLOW}Alt + Enter${COL_RESET}      : Toggle fullscreen mode."

    print_subheader "Command Line Options:"
    echo -e "  ${COL_GREEN}gargoyle --edit-config${COL_RESET} : Open the user configuration file for editing."
    echo -e "  ${COL_GREEN}gargoyle --paths${COL_RESET}        : List all config file paths."
    echo -e "  ${COL_GREEN}gargoyle --paths /path/to/game${COL_RESET} : List config paths including game-specific ones."

    print_subheader "Readline/Emacs-style Line Editor Bindings:"
    echo -e "  ${COL_YELLOW}Ctrl + a${COL_RESET} : Go to the beginning of the line."
    echo -e "  ${COL_YELLOW}Ctrl + b${COL_RESET} : Move the cursor to the left."
    echo -e "  ${COL_YELLOW}Ctrl + d${COL_RESET} : Erase the character under the cursor."
    echo -e "  ${COL_YELLOW}Ctrl + e${COL_RESET} : Go to the end of the line."
    echo -e "  ${COL_YELLOW}Ctrl + f${COL_RESET} : Move the cursor to the right."
    echo -e "  ${COL_YELLOW}Ctrl + h${COL_RESET} : Erase the character to the left of the cursor (Backspace)."
    echo -e "  ${COL_YELLOW}Ctrl + n${COL_RESET} : Next history entry."
    echo -e "  ${COL_YELLOW}Ctrl + p${COL_RESET} : Previous history entry."
    echo -e "  ${COL_YELLOW}Ctrl + u${COL_RESET} : Erase entire line."

    print_subheader "Configuration Files:"
    echo -e "  Gargoyle uses a layered configuration system. Priority (highest to lowest):"
    echo -e "  1. Game-specific (e.g., /path/to/game/game.ini, /path/to/game/garglk.ini)"
    echo -e "  2. User (e.g., ~/.config/garglk.ini, ~/.garglkrc)"
    echo -e "  3. System (e.g., /etc/garglk.ini or ${COL_YELLOW}/usr/local/etc/garglk.ini${COL_RESET} after this install)"
    echo -e "  Use ${COL_GREEN}Ctrl + ,${COL_RESET} in-game or ${COL_GREEN}gargoyle --edit-config${COL_RESET} to easily edit your user config."
    echo -e ""
}

# --- Check if Gargoyle is Already Installed ---
if command -v gargoyle &>/dev/null && [[ -x "$INSTALL_EXECUTABLE" || -L "$INSTALL_EXECUTABLE" ]]; then
    print_success "${APP_NAME} appears to be already installed at $(command -v gargoyle)."
    display_gargoyle_summary
    exit 0
elif command -v gargoyle &>/dev/null; then
    print_warning "${APP_NAME} command found, but not at the expected install location ($INSTALL_EXECUTABLE)."
    print_warning "It might have been installed via a different method (e.g., package manager)."
    print_warning "This script installs from source to ${INSTALL_EXECUTABLE%/*}."
    read -p "Do you want to proceed with compiling and installing from source? (y/N): " confirm_reinstall
    if [[ "$confirm_reinstall" != [yY] && "$confirm_reinstall" != [yY][eE][sS] ]]; then
        print_info "Aborting installation. Displaying summary for the found version."
        display_gargoyle_summary
        exit 0
    fi
    print_info "Proceeding with source installation."
fi

# --- Main Installation Logic ---
print_header "Gargoyle Interactive Fiction Player Setup Script"
print_info "This script will download, compile, and install ${APP_NAME} version ${GARGOYLE_VERSION}."
print_info "Installation path: ${INSTALL_EXECUTABLE%/*}"
echo ""
read -p "Do you want to continue? (Y/n): " confirmation
if [[ "$confirmation" == [nN] || "$confirmation" == [nN][oO] ]]; then
    print_info "Installation aborted by user."
    exit 0
fi

# --- Check for root/sudo privileges early for apt commands ---
if [[ $EUID -eq 0 ]]; then
    print_info "Script is running as root. Sudo will not be prefixed for apt commands."
    SUDO_CMD=""
else
    print_info "Script is not running as root. Sudo will be used for system-wide installations."
    SUDO_CMD="sudo"
    # Test sudo privileges now
    if ! $SUDO_CMD -v; then
        print_error "Sudo privileges are required but could not be obtained. Please run with sudo or ensure your user has sudo rights."
        exit 1
    fi
fi


# 1. Update package lists
print_subheader "Step 1: Updating package lists..."
$SUDO_CMD apt update -qq
print_success "Package lists updated."

# 2. Install dependencies
print_subheader "Step 2: Installing build dependencies..."
# Based on Gargoyle's INSTALL.md and Debian packaging info
# build-essential for compiler, make, etc.
# cmake for build system
# pkg-config for finding libraries
# libfontconfig1-dev, libfreetype6-dev for font rendering
# libjpeg-dev, libpng-dev for image formats
# libsdl2-dev, libsdl2-mixer-dev for sound and basic windowing (though Qt is also used)
# qtbase5-dev for the main UI framework
# zlib1g-dev common compression library
# libfmt-dev (sometimes needed, good to have)
# git (for cloning if we were not using a tarball)
DEPENDENCIES=(
    build-essential
    cmake
    pkg-config
    libfontconfig1-dev
    libfreetype6-dev
    libjpeg-dev
    libpng-dev
    libsdl2-dev
    libsdl2-mixer-dev
    qtbase5-dev
    zlib1g-dev
    libfmt-dev  # Often a dependency for modern C++ projects
    git # Useful for version control, though not strictly for tarball build
)
$SUDO_CMD apt install -y -qq "${DEPENDENCIES[@]}"
print_success "Build dependencies installed."

# 3. Create a temporary build directory
print_subheader "Step 3: Creating temporary build directory..."
BUILD_TMP_DIR=$(mktemp -d -t gargoyle_build_XXXXXX)
if [[ ! "$BUILD_TMP_DIR" || ! -d "$BUILD_TMP_DIR" ]]; then
    print_error "Could not create temporary build directory."
    exit 1
fi
print_info "Build directory: ${BUILD_TMP_DIR}"
cd "$BUILD_TMP_DIR"

# 4. Download Gargoyle source
print_subheader "Step 4: Downloading ${APP_NAME} ${GARGOYLE_VERSION} source..."
if wget --progress=bar:force:noscroll -O "${SOURCE_TARBALL}" "${SOURCE_URL}"; then
    print_success "${APP_NAME} source downloaded."
else
    print_error "Failed to download ${APP_NAME} source from ${SOURCE_URL}."
    print_error "Please check the URL or your internet connection."
    rm -rf "$BUILD_TMP_DIR"
    exit 1
fi

# 5. Extract source
print_subheader "Step 5: Extracting source code..."
if tar -xzf "${SOURCE_TARBALL}"; then
    print_success "Source code extracted."
else
    print_error "Failed to extract ${SOURCE_TARBALL}."
    rm -rf "$BUILD_TMP_DIR"
    exit 1
fi

# 6. Compile and Install
print_subheader "Step 6: Compiling and Installing ${APP_NAME}..."
cd "${BUILD_DIR_NAME}"
mkdir -p build
cd build

print_info "Configuring with CMake..."
# Default install prefix is /usr/local, which is fine.
if cmake ..; then
    print_success "CMake configuration complete."
else
    print_error "CMake configuration failed. Check output for errors (e.g., missing dependencies)."
    cd "$BUILD_TMP_DIR"/.. # Go up one level before removing
    rm -rf "$BUILD_TMP_DIR"
    exit 1
fi

print_info "Building with make (-j$(nproc) for parallel build)..."
if make -j$(nproc); then
    print_success "Build complete."
else
    print_error "Make build failed. Check output for errors."
    cd "$BUILD_TMP_DIR"/..
    rm -rf "$BUILD_TMP_DIR"
    exit 1
fi

print_info "Installing with 'sudo make install'..."
if $SUDO_CMD make install; then
    print_success "${APP_NAME} installed to ${INSTALL_EXECUTABLE%/*}."
else
    print_error "Installation (sudo make install) failed."
    print_error "You might need to run this script with sudo if you haven't already, or resolve permission issues."
    cd "$BUILD_TMP_DIR"/..
    rm -rf "$BUILD_TMP_DIR"
    exit 1
fi

# 7. Cleanup
print_subheader "Step 7: Cleaning up build files..."
cd /tmp # Move out of build directory before removing it
rm -rf "$BUILD_TMP_DIR"
print_success "Temporary build files removed."

# 8. Final Verification and Summary
print_header "${APP_NAME} Setup Complete!"
if command -v gargoyle &>/dev/null && [[ -x "$INSTALL_EXECUTABLE" || -L "$INSTALL_EXECUTABLE" ]]; then
    print_success "${APP_NAME} is now installed at $(command -v gargoyle)."
    print_info "You might need to run 'hash -r' or open a new terminal for the 'gargoyle' command to be recognized immediately if it wasn't before."
    display_gargoyle_summary
else
    print_error "Installation seems to have failed. '${INSTALL_EXECUTABLE}' not found or not executable."
    print_error "Please check the output above for any errors during compilation or installation."
    exit 1
fi

exit 0
