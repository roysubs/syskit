#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script to download, compile, and install Gargoyle Interactive Fiction player
# Version: 2023.1 (Latest known stable as of May 2024)
# Includes patch for stdint header compatibility and runs ldconfig.

# --- Configuration ---
APP_NAME="Gargoyle"
GARGOYLE_VERSION="2023.1"
SOURCE_TARBALL="gargoyle-${GARGOYLE_VERSION}.tar.gz"
SOURCE_URL="https://github.com/garglk/garglk/releases/download/${GARGOYLE_VERSION}/${SOURCE_TARBALL}"
INSTALL_EXECUTABLE="/usr/local/bin/gargoyle" # Standard install location
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

# --- Brief Introduction and Confirmation ---
print_header "${APP_NAME} - Interactive Fiction Player Setup"
echo ""
print_info "${APP_NAME} is a graphical application used to play all major interactive fiction formats."
print_info "It provides a visually appealing and configurable interface for your text adventures."
print_warning "Important: ${APP_NAME} requires a graphical desktop environment (e.g., X11 or Wayland) to run."
print_warning "It will not work in a text-only console."
echo ""
read -p "Do you want to continue with the installation of ${APP_NAME} ${GARGOYLE_VERSION}? (Y/n): " initial_confirmation
if [[ "$initial_confirmation" == [nN] || "$initial_confirmation" == [nN][oO] ]]; then
    print_info "Installation aborted by user."
    exit 0
fi

# --- Gargoyle Help and Summary Function ---
display_gargoyle_summary() {
    print_header "${APP_NAME} Usage Summary"
    print_subheader "Running Gargoyle:"
    echo -e "  To run Gargoyle, simply type: ${COL_GREEN}gargoyle /path/to/your/game.z5${COL_RESET} (or .ulx, .gblorb, etc.)"
    echo -e "  Example: ${COL_GREEN}gargoyle my_adventure.zblorb${COL_RESET}"
    print_subheader "Key Runtime Options (Non-Mac):"
    echo -e "  ${COL_YELLOW}Ctrl + ,${COL_RESET}         : Open Gargoyle's configuration file in a text editor."
    echo -e "  ${COL_YELLOW}Ctrl + .${COL_RESET}         : List paths to all configuration and theme files."
    echo -e "  ${COL_YELLOW}Ctrl + Shift + t${COL_RESET} : Display a list of all available color themes."
    echo -e "  ${COL_YELLOW}Ctrl + Shift + s${COL_RESET} : Save the scrollback buffer (ad hoc transcript)."
    echo -e "  ${COL_YELLOW}Alt + Enter${COL_RESET}      : Toggle fullscreen mode."
    print_subheader "Command Line Options:"
    echo -e "  ${COL_GREEN}gargoyle --edit-config${COL_RESET} : Open the user configuration file for editing."
    echo -e "  ${COL_GREEN}gargoyle --paths${COL_RESET}        : List all config file paths."
    # ... (other options can be added)
    print_subheader "Configuration Files:"
    echo -e "  Gargoyle uses a layered configuration system. Use ${COL_GREEN}Ctrl + ,${COL_RESET} or ${COL_GREEN}gargoyle --edit-config${COL_RESET}."
    echo -e ""
}

# --- Check if Gargoyle is Already Installed ---
if command -v gargoyle &>/dev/null && [[ -x "$INSTALL_EXECUTABLE" || -L "$INSTALL_EXECUTABLE" ]]; then
    print_success "${APP_NAME} appears to be already installed at $(command -v gargoyle)."
    display_gargoyle_summary
    exit 0
elif command -v gargoyle &>/dev/null; then
    print_warning "${APP_NAME} command found, but not at the expected install location ($INSTALL_EXECUTABLE)."
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

# --- Check for root/sudo privileges ---
if [[ $EUID -eq 0 ]]; then
    print_info "Script is running as root. Sudo will not be prefixed for apt commands."
    SUDO_CMD=""
else
    print_info "Script is not running as root. Sudo will be used for system-wide installations."
    SUDO_CMD="sudo"
    if ! $SUDO_CMD -v; then
        print_error "Sudo privileges are required but could not be obtained."
        exit 1
    fi
fi

# 1. Update package lists
print_subheader "Step 1: Updating package lists..."
$SUDO_CMD apt update -qq
print_success "Package lists updated."

# 2. Install dependencies
print_subheader "Step 2: Installing build dependencies..."
DEPENDENCIES=( build-essential cmake pkg-config libfontconfig1-dev libfreetype6-dev libjpeg-dev libpng-dev libsdl2-dev libsdl2-mixer-dev qtbase5-dev zlib1g-dev libfmt-dev git )
$SUDO_CMD apt install -y -qq "${DEPENDENCIES[@]}"
print_success "Build dependencies installed."

# --- Check C++ compiler version ---
print_subheader "Checking C++ compiler version(s)..."
if command -v g++ &>/dev/null; then print_info "g++ version: $(g++ --version | head -n1)"; else print_warning "g++ not found."; fi
if command -v c++ &>/dev/null; then print_info "c++ (default) version: $(c++ --version | head -n1)"; else print_warning "c++ (default compiler) not found."; fi

# 3. Create a temporary build directory
print_subheader "Step 3: Creating temporary build directory..."
BUILD_TMP_DIR=$(mktemp -d -t gargoyle_build_XXXXXX)
print_info "Build directory: ${BUILD_TMP_DIR}"
cd "$BUILD_TMP_DIR" || { print_error "Failed to cd into build directory ${BUILD_TMP_DIR}"; exit 1; }

# 4. Download Gargoyle source
print_subheader "Step 4: Downloading ${APP_NAME} ${GARGOYLE_VERSION} source..."
if wget --progress=bar:force:noscroll -O "${SOURCE_TARBALL}" "${SOURCE_URL}"; then
    print_success "${APP_NAME} source downloaded."
else
    print_error "Failed to download ${APP_NAME} source from ${SOURCE_URL}."
    print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved for debugging download issues."
    exit 1
fi

# 5. Extract source
print_subheader "Step 5: Extracting source code..."
if tar -xzf "${SOURCE_TARBALL}"; then
    print_success "Source code extracted."
else
    print_error "Failed to extract ${SOURCE_TARBALL}."
    print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved for debugging extraction issues."
    exit 1
fi

# --- Apply patch to garglk.h ---
print_subheader "Applying patch to garglk/garglk.h for stdint compatibility..."
GARGLK_H_PATH="${BUILD_DIR_NAME}/garglk/garglk.h" # Relative path from BUILD_TMP_DIR
PATCH_MARKER="// --- Applied stdint patch by script ---"

if [ -f "$GARGLK_H_PATH" ]; then
    if ! grep -qF "$PATCH_MARKER" "$GARGLK_H_PATH"; then
        PATCH_CONTENT="#ifdef __cplusplus\n#include <cstdint>  // For C++\n#else\n#include <stdint.h>   // For C\n#endif\n${PATCH_MARKER}\n"
        TEMP_PATCH_FILE="garglk.h.patchdata.$$"
        echo -e "$PATCH_CONTENT" > "$TEMP_PATCH_FILE"
        cat "$GARGLK_H_PATH" >> "$TEMP_PATCH_FILE"
        if mv "$TEMP_PATCH_FILE" "$GARGLK_H_PATH"; then
            print_success "${GARGLK_H_PATH} patched."
        else
            print_error "Failed to move patched file to ${GARGLK_H_PATH}."
            rm -f "$TEMP_PATCH_FILE" # Clean up temp file on error
            print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved."
            exit 1
        fi
    else
        print_info "stdint patch already applied to ${GARGLK_H_PATH}."
    fi
else
    print_error "Could not find ${GARGLK_H_PATH} to patch."
    print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved."
    exit 1
fi

# 6. Compile and Install
print_subheader "Step 6: Compiling and Installing ${APP_NAME}..."
cd "${BUILD_DIR_NAME}" || { print_error "Failed to cd into source directory ${BUILD_DIR_NAME}"; print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved."; exit 1; }
mkdir -p build
cd build || { print_error "Failed to cd into build subdirectory"; cd ..; print_warning "Build directory ${BUILD_TMP_DIR} intentionally preserved."; exit 1; }

print_info "Configuring with CMake (forcing C++17 standard)..."
ORIGINAL_CXXFLAGS="${CXXFLAGS:-}"
export CXXFLAGS="-std=c++17 ${ORIGINAL_CXXFLAGS}"
CXXFLAGS=$(echo "${CXXFLAGS}" | awk '{$1=$1};1')
print_info "Exported CXXFLAGS for CMake: ${CXXFLAGS}"

CMAKE_ARGS=( "-D CMAKE_BUILD_TYPE=Release" "-D CMAKE_CXX_STANDARD=17" "-D CMAKE_CXX_STANDARD_REQUIRED=ON" "-D CMAKE_EXPORT_COMPILE_COMMANDS=ON" "-D CMAKE_CXX_FLAGS=${CXXFLAGS}" )
print_info "CMake arguments: ${CMAKE_ARGS[*]}"

if [ -f CMakeCache.txt ]; then print_info "Removing existing CMakeCache.txt..."; rm -f CMakeCache.txt; fi
if [ -f compile_commands.json ]; then print_info "Removing existing compile_commands.json..."; rm -f compile_commands.json; fi

if cmake "${CMAKE_ARGS[@]}" ..; then
    print_success "CMake configuration complete."
    print_info "A 'compile_commands.json' file is in (${PWD}/compile_commands.json) for diagnostics if needed."
else
    print_error "CMake configuration failed."
    print_warning "Build directory ${BUILD_TMP_DIR} and its contents (like ${PWD}) are preserved for debugging."
    exit 1
fi

print_info "Building with make (-j$(nproc) for parallel build)..."
if make -j"$(nproc)"; then
    print_success "Build complete."
else
    print_error "Make build failed. Check output for errors."
    print_error "The 'compile_commands.json' file in '${PWD}/compile_commands.json' might provide clues."
    print_warning "Build directory ${BUILD_TMP_DIR} and its contents (like ${PWD}) are preserved for debugging."
    exit 1
fi

print_info "Installing with '$SUDO_CMD make install'..."
if $SUDO_CMD make install; then
    print_success "${APP_NAME} installed to ${INSTALL_EXECUTABLE%/*} (executable: $INSTALL_EXECUTABLE)."

    print_subheader "Updating shared library cache..."
    if $SUDO_CMD ldconfig; then
        print_success "Shared library cache updated."
    else
        print_warning "ldconfig command failed. You might need to run it manually: sudo ldconfig"
        print_warning "If gargoyle fails to start due to missing .so files, running 'sudo ldconfig' should fix it."
    fi
else
    print_error "Installation ($SUDO_CMD make install) failed."
    print_warning "Build directory ${BUILD_TMP_DIR} and its contents are preserved for debugging."
    exit 1
fi

# 7. Cleanup
print_subheader "Step 7: Cleaning up build files..."
cd /tmp
if rm -rf "$BUILD_TMP_DIR"; then
    print_success "Temporary build files removed from ${BUILD_TMP_DIR}."
else
    # This case should ideally not happen if BUILD_TMP_DIR was created and script has permissions
    print_warning "Failed to remove temporary build directory ${BUILD_TMP_DIR}. You may need to remove it manually."
fi

# 8. Final Verification and Summary
print_header "${APP_NAME} Setup Complete!"
if command -v gargoyle &>/dev/null && [[ -x "$INSTALL_EXECUTABLE" || -L "$INSTALL_EXECUTABLE" ]]; then
    print_success "${APP_NAME} is now installed at $(command -v gargoyle)."
    print_info "You might need to run 'hash -r' or open a new terminal for the 'gargoyle' command to be recognized by your shell."
    print_info "The shared library cache has been updated, so 'gargoyle' should find its libraries."
    display_gargoyle_summary
else
    print_error "Installation seems to have failed. '${INSTALL_EXECUTABLE}' not found or not executable."
    print_error "If the executable is present but gives library errors, try running 'sudo ldconfig' manually."
fi

exit 0
