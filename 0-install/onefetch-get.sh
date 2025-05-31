#!/bin/bash
# Author: Roy Wiseman 2025-02
#
# Compiled version currently uses GLIBC 2.39 which we can't use without
# breaking the host OS.
# The manual cargo compilation would be:
#   git clone https://github.com/o2sh/onefetch.git
#   cd onefetch
#   cargo build --release
# The compiled binary would then be in target/release/onefetch.

# --- Script Configuration ---
PROGRAM_NAME="onefetch"
GITHUB_REPO_OWNER="o2sh"
GITHUB_REPO_NAME="onefetch"
INSTALL_DIR="/usr/local/bin"
# Asset name pattern for Linux generic tarball
ASSET_PATTERN="onefetch-linux.tar.gz"
DEFAULT_FALLBACK_VERSION="2.24.0" # Used if API fetch fails

# --- Helper Functions for Colored Output ---
print_header() { echo -e "\n\033[1;36m--- $1 ---\033[0m"; }
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; } # Exit on error
print_command() { echo -e "  \033[0;35m\$ \033[1;35m$1\033[0m"; }

# --- Prerequisite Checking ---
check_prerequisites() {
    print_header "Checking Prerequisites"
    local missing_pkg=0
    # Check for curl or wget
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        print_error "Neither 'curl' nor 'wget' is installed. Please install one to download files."
        missing_pkg=1
    else
        print_info "'curl' or 'wget' found."
    fi

    for pkg in tar gzip sudo; do
        if ! command -v "$pkg" &> /dev/null; then
            print_error "$pkg is not installed. Please install it to continue."
            missing_pkg=1
        else
            print_info "$pkg is installed."
        fi
    done

    if [ $missing_pkg -ne 0 ]; then
        print_error "One or more prerequisites are missing. Please install them and try again."
    fi
    print_success "All prerequisites met."
}

# --- Introduction and Confirmation ---
display_intro_and_confirm() {
    print_header "Welcome to the ${PROGRAM_NAME} Installer"
    echo "This script will download and install the latest version of ${PROGRAM_NAME},"
    echo "a command-line Git information tool that displays project information and"
    echo "statistics for a local Git repository directly to your terminal."
    echo ""
    print_info "The script will perform the following main steps:"
    echo "  1. Check for necessary tools (curl/wget, tar, gzip, sudo)."
    echo "  2. Fetch the latest release information for ${PROGRAM_NAME} from GitHub."
    echo "  3. Download the Linux tarball (${ASSET_PATTERN})."
    echo "  4. Extract the '${PROGRAM_NAME}' executable."
    echo "  5. Install it to ${INSTALL_DIR}/${PROGRAM_NAME} (requires sudo)."
    echo "  6. Verify the installation."
    echo ""
    read -r -p "Do you want to proceed with the installation? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        print_info "Installation aborted by user."
        exit 0
    fi
}

# --- Core Functions ---
get_latest_release_info() {
    print_info "Fetching latest release information for ${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}..."
    local api_url="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/latest"
    local response
    
    if command -v curl &> /dev/null; then
        response=$(curl -s "$api_url")
    elif command -v wget &> /dev/null; then
        response=$(wget -qO- "$api_url")
    else
        print_warning "Cannot fetch release info (curl/wget missing). Using fallback version."
        LATEST_VERSION_TAG="$DEFAULT_FALLBACK_VERSION"
        # Construct a fallback URL - this is a guess and might not always work if asset names change structure
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${LATEST_VERSION_TAG}/${ASSET_PATTERN}"
        return
    fi

    if [ -z "$response" ]; then
        print_warning "Failed to get a response from GitHub API. Using fallback version."
        LATEST_VERSION_TAG="$DEFAULT_FALLBACK_VERSION"
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${LATEST_VERSION_TAG}/${ASSET_PATTERN}"
        return
    fi
    
    # Check for API rate limit error or other messages
    if echo "$response" | grep -q "API rate limit exceeded"; then
        print_warning "GitHub API rate limit exceeded. Using fallback version."
        LATEST_VERSION_TAG="$DEFAULT_FALLBACK_VERSION"
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${LATEST_VERSION_TAG}/${ASSET_PATTERN}"
        return
    fi

    LATEST_VERSION_TAG=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)
    DOWNLOAD_URL=$(echo "$response" | grep '"browser_download_url":' | grep "${ASSET_PATTERN}" | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)

    if [ -z "$LATEST_VERSION_TAG" ] || [ -z "$DOWNLOAD_URL" ]; then
        print_warning "Could not parse latest version tag or download URL from GitHub API. Using fallback version."
        LATEST_VERSION_TAG="$DEFAULT_FALLBACK_VERSION"
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${LATEST_VERSION_TAG}/${ASSET_PATTERN}"
    else
        print_success "Latest version: ${LATEST_VERSION_TAG}. Download URL found."
    fi
}

install_program() {
    print_header "Installing ${PROGRAM_NAME} (Version: ${LATEST_VERSION_TAG:-$DEFAULT_FALLBACK_VERSION})"
    local installed_path="${INSTALL_DIR}/${PROGRAM_NAME}"

    if command -v "$PROGRAM_NAME" &> /dev/null; then
        # onefetch might not have a consistent way to get *just* the version number easily for comparison
        # So we'll just report what's found and ask to proceed.
        local current_version_output
        current_version_output=$($PROGRAM_NAME --version 2>&1) # Capture version output
        print_warning "${PROGRAM_NAME} seems to be already installed."
        print_info "Detected version output: ${current_version_output}"
        read -r -p "Do you want to try reinstalling/updating to version ${LATEST_VERSION_TAG:-$DEFAULT_FALLBACK_VERSION}? (y/N): " reinstall_choice
        if [[ ! "$reinstall_choice" =~ ^[Yy]$ ]]; then
            print_info "Skipping installation."
            return 0 
        fi
        print_info "Proceeding with reinstallation..."
    fi

    if [ -z "$DOWNLOAD_URL" ]; then
        print_error "Download URL is not set. Cannot proceed."
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    if [ ! -d "$temp_dir" ]; then
        print_error "Failed to create temporary directory."
    fi
    print_info "Created temporary directory: ${temp_dir}"
    cd "$temp_dir" || print_error "Failed to change to temp directory: ${temp_dir}"

    print_info "Downloading ${PROGRAM_NAME} from ${DOWNLOAD_URL}..."
    local downloaded_asset_name="${ASSET_PATTERN}" # Assuming the URL directly points to the asset

    if command -v curl &> /dev/null; then
        if ! curl -Lo "${downloaded_asset_name}" "${DOWNLOAD_URL}"; then
            print_error "Download failed using curl. Check URL or network. URL: ${DOWNLOAD_URL}"
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -O "${downloaded_asset_name}" "${DOWNLOAD_URL}"; then
            print_error "Download failed using wget. Check URL or network. URL: ${DOWNLOAD_URL}"
        fi
    fi
    print_success "Download complete: ${downloaded_asset_name}"

    print_info "Extracting ${downloaded_asset_name}..."
    # tar -xzf should extract the 'onefetch' executable directly into the current temp dir
    if ! tar -xzf "${downloaded_asset_name}"; then
        print_error "Extraction failed. The archive might be corrupt or the structure unexpected."
    fi
    
    # The executable is expected to be named 'onefetch' inside the archive
    local extracted_executable_name="${PROGRAM_NAME}"
    if [ ! -f "${extracted_executable_name}" ]; then
        print_error "Executable '${extracted_executable_name}' not found after extraction in ${temp_dir}."
        print_info "Files in temp dir:"
        ls -la "${temp_dir}"
    else
        print_success "Executable '${extracted_executable_name}' found."
    fi

    print_info "Setting execute permissions for ${extracted_executable_name}..."
    chmod +x "${extracted_executable_name}"

    print_info "Moving ${extracted_executable_name} to ${installed_path} (requires sudo)..."
    # Check if sudo credentials are still active or prompt if needed
    if ! sudo -n true 2>/dev/null; then
      print_warning "Sudo access is required. You will be prompted for your password."
    fi
    if sudo mv "${extracted_executable_name}" "${installed_path}"; then
        print_success "${PROGRAM_NAME} installed successfully to ${installed_path}"
    else
        print_error "Failed to move ${PROGRAM_NAME} to ${installed_path}. Check sudo permissions or if directory exists/is writable."
    fi
    
    print_info "Cleaning up temporary directory: ${temp_dir}"
    rm -rf "$temp_dir"
    
    # Verify installation
    if command -v "$PROGRAM_NAME" &> /dev/null; then
        print_info "Verifying installation..."
        print_command "${PROGRAM_NAME} --version"
        ${PROGRAM_NAME} --version
    else
        print_error "${PROGRAM_NAME} command not found in PATH after installation attempt."
        return 1
    fi
    return 0
}

display_usage_tips() {
    print_header "Basic ${PROGRAM_NAME} Usage"
    print_info "Navigate to a Git repository directory in your terminal, then run:"
    print_command "${PROGRAM_NAME}"
    echo "This will display information about the current Git repository."
    echo ""
    print_info "Other useful options:"
    echo "  - List available languages onefetch can detect:"
    print_command "${PROGRAM_NAME} --list-languages"
    echo "  - List available package managers onefetch can detect:"
    print_command "${PROGRAM_NAME} --list-package-managers"
    echo "  - Display output in JSON format:"
    print_command "${PROGRAM_NAME} --output json"
    echo "  - Exclude certain information (e.g., lines of code, size):"
    print_command "${PROGRAM_NAME} --exclude loc size"
    echo "  - Show help for all options:"
    print_command "${PROGRAM_NAME} --help"
    echo ""
    print_success "Enjoy using ${PROGRAM_NAME}!"
}

# --- Main Script Logic ---
clear
display_intro_and_confirm
check_prerequisites
get_latest_release_info # Sets LATEST_VERSION_TAG and DOWNLOAD_URL

if install_program; then
    display_usage_tips
else
    print_error "Installation of ${PROGRAM_NAME} failed. Please review the error messages above."
fi

print_header "Script Finished"
exit 0

