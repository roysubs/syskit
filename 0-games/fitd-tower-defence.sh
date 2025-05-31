#!/bin/bash
# Author: Roy Wiseman 2025-05

# --- Script Configuration ---
GAME_NAME="fiTD (Terminal Tower Defence)"
REPO_URL="https://github.com/odditica/fiTD.git"
# Use /tmp for temporary build location
TEMP_BUILD_BASE="/tmp/fiTD_build_$$"  # $$ adds process ID for uniqueness
REPO_DIR_NAME="fiTD"
CLONE_DEST_DIR="${TEMP_BUILD_BASE}/${REPO_DIR_NAME}"
BUILD_DIR_NAME="build"
GAME_EXECUTABLE_NAME="fitd"

# Installation locations
INSTALL_DIR="${HOME}/.local/bin"
GAME_INSTALL_PATH="${INSTALL_DIR}/${GAME_EXECUTABLE_NAME}"

# Dependencies required by the game
DEPENDENCIES=("cmake" "catch2" "libncurses5-dev" "doxygen" "git" "build-essential" "sed") # build-essential for make/g++

# --- Helper Functions for Colored Output ---
print_header() { echo -e "\n\033[1;36m--- $1 ---\033[0m"; }
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; } # Exit on error
print_command() { echo -e "  \033[0;35m\$ \033[1;35m$1\033[0m"; }

# --- Cleanup function ---
cleanup_temp_files() {
    if [ -d "${TEMP_BUILD_BASE}" ]; then
        print_info "Cleaning up temporary build directory: ${TEMP_BUILD_BASE}"
        rm -rf "${TEMP_BUILD_BASE}"
    fi
}

# Set trap to cleanup on script exit
trap cleanup_temp_files EXIT

# --- Prerequisite Checking ---
check_prerequisites() {
    print_header "Checking Prerequisites"
    local missing_pkg=0
    for pkg in "${DEPENDENCIES[@]}"; do
        # A specific check for catch2 as it's often a library not a command
        if [[ "$pkg" == "catch2" || "$pkg" == "libncurses5-dev" || "$pkg" == "doxygen" ]]; then
            # For libraries, we rely on apt to handle them.
            # We ensure 'apt' itself is available for dependency installation.
            if ! command -v apt &> /dev/null && ! command -v apt-get &> /dev/null; then
                 print_error "'apt' or 'apt-get' command not found. Cannot manage Debian/Ubuntu packages."
            fi
            continue
        fi
        if ! command -v "$pkg" &> /dev/null; then
            print_warning "$pkg is not installed."
            missing_pkg=1
        else
            print_info "$pkg is installed."
        fi
    done

    if [ $missing_pkg -eq 1 ]; then
        print_warning "Some command-line tools are missing. The script will attempt to install them via APT along with libraries."
        print_warning "Ensure you have sudo privileges."
    else
        print_success "Basic command-line prerequisites met."
    fi
    # Check for sudo
    if ! command -v sudo &> /dev/null; then
        print_error "sudo command not found. This script requires sudo for installing dependencies."
    fi
}

# --- Introduction and Confirmation ---
display_intro_and_confirm() {
    print_header "Welcome to the ${GAME_NAME} Installer"
    echo "This script will guide you through the installation of ${GAME_NAME}."
    echo "It's a minimalistic ncurses-based tower defence game by 'odditica'."
    echo ""
    print_info "The script will perform the following main steps:"
    echo "  1. Check for necessary tools (git, cmake, make, etc.)."
    echo "  2. Create a temporary build directory in /tmp"
    echo "  3. Clone the game's source code from GitHub."
    echo "  4. Install required system dependencies using 'apt-get' (requires sudo):"
    echo "     - cmake, catch2, libncurses5-dev, doxygen, and potentially build-essential/git if missing."
    echo "  5. Apply minor source code fixes needed for compilation on some systems."
    echo "  6. Compile the game in the temporary location."
    echo "  7. Install the compiled game to ${INSTALL_DIR}"
    echo "  8. Create a symlink so you can run the game with 'fitd' from anywhere."
    echo "  9. Clean up temporary files."
    echo ""
    echo "The game will be installed to: ${GAME_INSTALL_PATH}"
    echo "You'll be able to run it from anywhere with: fitd"
    echo ""
    read -r -p "Do you want to proceed with the installation? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        print_info "Installation aborted by user."
        exit 0
    fi
}

# --- Installation Steps ---
setup_directories() {
    print_header "Setting Up Temporary Build Directory"
    print_info "Creating temporary build directory: ${TEMP_BUILD_BASE}"
    mkdir -p "${TEMP_BUILD_BASE}"
    if [ $? -ne 0 ]; then
        print_error "Failed to create temporary directory: ${TEMP_BUILD_BASE}. Check permissions."
    fi
    
    print_info "Creating installation directory: ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    if [ $? -ne 0 ]; then
        print_error "Failed to create installation directory: ${INSTALL_DIR}. Check permissions."
    fi
}

clone_repository() {
    print_header "Cloning Game Repository"
    print_info "Cloning ${GAME_NAME} repository into ${CLONE_DEST_DIR}..."
    print_command "git clone ${REPO_URL} ${CLONE_DEST_DIR}"
    if ! git clone "${REPO_URL}" "${CLONE_DEST_DIR}"; then
        print_error "Failed to clone the repository. Check URL and network connection."
    fi
    print_success "Repository cloned successfully."
}

install_game_dependencies() {
    print_header "Installing Dependencies"
    print_info "This step requires sudo privileges to install packages."
    print_info "The following packages will be ensured: cmake catch2 libncurses5-dev doxygen git build-essential"

    # Check if sudo credentials are still active or prompt if needed at first sudo command
    if sudo -n true 2>/dev/null; then
      print_info "Sudo credentials active."
    else
      print_warning "Sudo access is required. You might be prompted for your password."
    fi

    print_command "sudo apt-get update"
    if ! sudo apt-get update; then
        print_warning "apt-get update failed. Continuing, but package lists might be outdated."
    fi

    print_command "sudo apt-get install -y cmake catch2 libncurses5-dev doxygen git build-essential"
    if ! sudo apt-get install -y cmake catch2 libncurses5-dev doxygen git build-essential; then
        print_error "Failed to install one or more dependencies. Please check apt-get output."
    fi
    print_success "Dependencies should now be installed/updated."
}

apply_source_fixes() {
    print_header "Applying Source Code Fixes"
    if [ ! -f "${CLONE_DEST_DIR}/src/CGameGraphics.cpp" ] || [ ! -f "${CLONE_DEST_DIR}/src/CGfx.cpp" ]; then
        print_error "Source files not found in ${CLONE_DEST_DIR}/src/. Cannot apply fixes."
    fi

    # Fix 1 for CGameGraphics.cpp
    if grep -q 'mvwprintw(stdscr, ' "${CLONE_DEST_DIR}/src/CGameGraphics.cpp"; then
        print_info "Fix for CGameGraphics.cpp already seems to be applied or original code doesn't match pattern 'mvwprintw('."
    elif grep -q 'mvwprintw(' "${CLONE_DEST_DIR}/src/CGameGraphics.cpp"; then
        print_info "Applying fix to src/CGameGraphics.cpp..."
        print_command "sed -i 's/mvwprintw(/mvwprintw(stdscr, /' \"${CLONE_DEST_DIR}/src/CGameGraphics.cpp\""
        sed -i 's/mvwprintw(/mvwprintw(stdscr, /' "${CLONE_DEST_DIR}/src/CGameGraphics.cpp"
        print_success "CGameGraphics.cpp patched."
    else
        print_info "No calls to 'mvwprintw(' found in CGameGraphics.cpp that would require patching."
    fi

    # Fix 2 for CGfx.cpp - skipping as noted in original script
    print_info "Skipping 'sed' patch for CGfx.cpp related to 'mvwaddchstr'."
    print_info "The upstream source code for 'mvwaddchstr' calls in CGfx.cpp appears to be correct and does not need this patch."
}

build_game() {
    print_header "Building ${GAME_NAME}"
    local game_build_path="${CLONE_DEST_DIR}/${BUILD_DIR_NAME}"
    
    # Ensure build directory exists
    print_info "Ensuring build directory exists: ${game_build_path}"
    mkdir -p "${game_build_path}"
    cd "${game_build_path}" || print_error "Failed to cd into build directory: ${game_build_path}"

    print_info "Running CMake configuration..."
    print_warning "Disabling tests completely due to Catch2 compatibility issues with newer glibc versions."
    print_command "cmake .. -DFITD_TEST:BOOL=OFF -DBUILD_TESTING=OFF"
    if ! cmake .. -DFITD_TEST:BOOL=OFF -DBUILD_TESTING=OFF; then
        print_error "CMake configuration failed. Check CMake output."
    fi

    print_info "Compiling the game (tests disabled to avoid Catch2 issues)..."
    print_command "make fitd"
    if ! make fitd; then
        print_error "Build failed (make fitd). Check compilation errors."
    fi

    # The executable is actually in build/build/fitd due to nested build directories
    local actual_executable_path="${game_build_path}/build/${GAME_EXECUTABLE_NAME}"
    if [ ! -f "${actual_executable_path}" ]; then
        print_error "Build process finished, but game executable not found at expected location: ${actual_executable_path}"
    fi

    print_success "${GAME_NAME} built successfully!"
    print_info "Executable found at: ${actual_executable_path}"
    GAME_BUILT_SUCCESSFULLY=true
    BUILT_EXECUTABLE_PATH="${actual_executable_path}"
    cd - > /dev/null # Go back
}

install_game() {
    if [ "$GAME_BUILT_SUCCESSFULLY" != true ]; then
        print_error "Cannot install game - build was not successful."
    fi

    print_header "Installing ${GAME_NAME}"
    
    # Copy the executable to the installation directory
    print_info "Installing game executable to: ${GAME_INSTALL_PATH}"
    print_command "cp ${BUILT_EXECUTABLE_PATH} ${GAME_INSTALL_PATH}"
    if ! cp "${BUILT_EXECUTABLE_PATH}" "${GAME_INSTALL_PATH}"; then
        print_error "Failed to copy executable to installation directory."
    fi
    
    # Make sure it's executable
    chmod +x "${GAME_INSTALL_PATH}"
    
    print_success "Game installed successfully to: ${GAME_INSTALL_PATH}"
}

create_symlink() {
    print_header "Creating System-wide Access"
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        print_warning "~/.local/bin is not in your PATH."
        print_info "Adding ~/.local/bin to PATH in your ~/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        print_info "You'll need to run 'source ~/.bashrc' or start a new terminal session for the PATH change to take effect."
    else
        print_info "~/.local/bin is already in your PATH."
    fi
    
    print_success "You can now run the game from anywhere with: fitd"
}

generate_documentation() {
    GAME_BUILT_SUCCESSFULLY=${GAME_BUILT_SUCCESSFULLY:-false}
    if [ "$GAME_BUILT_SUCCESSFULLY" != true ]; then
        print_warning "Game build was not successful or skipped. Skipping documentation generation."
        return
    fi

    print_header "Generating Documentation (Optional)"
    read -r -p "Do you want to generate Doxygen documentation for the game? (y/N): " doc_choice
    if [[ ! "$doc_choice" =~ ^[Yy]$ ]]; then
        print_info "Skipping documentation generation."
        return
    fi

    local game_build_path="${CLONE_DEST_DIR}/${BUILD_DIR_NAME}"
    cd "${game_build_path}" || print_error "Failed to cd into build directory: ${game_build_path} for docs"

    print_info "Generating documentation with 'make doc'..."
    print_command "make doc"
    if ! make doc; then
        print_warning "Documentation generation failed or produced warnings. Check 'make doc' output."
    else
        local doc_path="${game_build_path}/doc/html/index.html"
        if [ -f "${doc_path}" ]; then
            # Copy documentation to a permanent location
            local doc_install_dir="${HOME}/.local/share/doc/fitd"
            mkdir -p "${doc_install_dir}"
            cp -r "${game_build_path}/doc/html"/* "${doc_install_dir}/"
            print_success "Documentation generated and saved to: ${doc_install_dir}/index.html"
        else
            print_success "Documentation generated in build directory."
        fi
    fi
    cd - > /dev/null # Go back
}

display_run_instructions() {
    GAME_BUILT_SUCCESSFULLY=${GAME_BUILT_SUCCESSFULLY:-false}
    if [ "$GAME_BUILT_SUCCESSFULLY" != true ]; then
        print_warning "Game build was not successful or skipped. Run instructions might not apply."
        return
    fi

    print_header "How to Play ${GAME_NAME}"
    print_success "${GAME_NAME} installation is complete!"
    print_info "To run the game, simply type:"
    print_command "fitd"
    echo ""
    print_info "In-Game Tips:"
    echo "  - This is an ncurses (terminal-based) game."
    echo "  - Once the game starts, press the 'h' key to see in-game controls and help."
    echo "  - Common keys in such games include arrow keys, spacebar, Enter, and 'q' to quit."
    echo ""
    print_info "Game is installed at: ${GAME_INSTALL_PATH}"
    print_info "To uninstall, simply delete the file: rm ${GAME_INSTALL_PATH}"
    echo ""
    print_info "To update the game later, just run this script again!"
    echo ""
    print_info "Enjoy the game!"
}

# --- Main Script Logic ---
clear
display_intro_and_confirm
check_prerequisites
setup_directories
clone_repository
install_game_dependencies
apply_source_fixes
build_game
install_game
create_symlink
generate_documentation
display_run_instructions

print_header "Script Finished"
print_info "Temporary build files have been cleaned up automatically."
exit 0
