#!/bin/bash
# Author: Roy Wiseman 2025-01

# --- Script Configuration ---
INSTALL_DIR="/usr/local/bin"
CHEAT_EXECUTABLE_NAME="cheat"
DEFAULT_CHEAT_VERSION="4.4.2" # Fallback if fetching latest fails
GITHUB_REPO="cheat/cheat"
COMMUNITY_SHEETS_REPO_URL="https://github.com/cheat/cheatsheets.git"

# --- Helper Functions for Colored Output ---
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }
print_command() { echo -e "  \033[0;35m\$ \033[1;35m$1\033[0m"; }
print_header() { echo -e "\n\033[1;36m--- $1 ---\033[0m"; }

# --- Prerequisite Checking ---
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed. Please install it to continue."
        exit 1
    fi
}

# --- Core Functions ---

get_latest_cheat_version_tag() {
    print_info "Fetching the latest cheat version tag from GitHub..."
    # Try curl first, then wget
    if command -v curl &> /dev/null; then
        LATEST_TAG=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    elif command -v wget &> /dev/null; then
        LATEST_TAG=$(wget -qO- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        print_warning "Neither curl nor wget found. Cannot fetch the latest version automatically."
        LATEST_TAG=""
    fi

    if [ -z "$LATEST_TAG" ]; then
        print_warning "Could not fetch the latest version tag. Using default: $DEFAULT_CHEAT_VERSION"
        CHEAT_VERSION="$DEFAULT_CHEAT_VERSION"
    else
        print_success "Latest version tag found: $LATEST_TAG"
        CHEAT_VERSION="$LATEST_TAG"
    fi
}

install_cheat() {
    print_header "Installing cheat Utility (Version: $CHEAT_VERSION)"

    if command -v $CHEAT_EXECUTABLE_NAME &> /dev/null; then
        INSTALLED_VERSION=$($CHEAT_EXECUTABLE_NAME --version 2>&1 | awk '{print $NF}')
        print_warning "cheat is already installed (Version: $INSTALLED_VERSION)."
        read -r -p "Do you want to try reinstalling/updating to version $CHEAT_VERSION? (y/N): " reinstall_choice
        if [[ ! "$reinstall_choice" =~ ^[Yy]$ ]]; then
            print_info "Skipping installation."
            # Proceed to show info even if skipped, as it's still useful
            return 0 
        fi
        print_info "Proceeding with reinstallation..."
    fi

    ARCHITECTURE=$(uname -m)
    OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]') # Get OS type (linux, darwin, etc.)

    case "$ARCHITECTURE" in
        x86_64) ARCH_SUFFIX="amd64" ;;
        aarch64|arm64) ARCH_SUFFIX="arm64" ;;
        armv7l|armhf) ARCH_SUFFIX="armv7" ;; # Common for 32-bit ARM
        *)
            print_error "Unsupported architecture: $ARCHITECTURE. Please install cheat manually."
            return 1
            ;;
    esac

    if [ "$OS_TYPE" != "linux" ] && [ "$OS_TYPE" != "darwin" ]; then # cheat primarily provides for linux and darwin
        print_error "This script primarily supports Linux and macOS (Darwin) for automatic download."
        print_error "For OS '$OS_TYPE', please check cheat releases page for a suitable binary."
        return 1
    fi
    
    # Adjust asset name based on common patterns, 'darwin' usually implies macOS
    ASSET_OS_NAME="$OS_TYPE" 

    DOWNLOAD_ASSET_NAME="cheat-${ASSET_OS_NAME}-${ARCH_SUFFIX}.gz"
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${CHEAT_VERSION}/${DOWNLOAD_ASSET_NAME}"
    TEMP_DIR=$(mktemp -d)

    print_info "Downloading $DOWNLOAD_ASSET_NAME from $DOWNLOAD_URL"
    cd "$TEMP_DIR" || { print_error "Failed to change to temp directory."; return 1; }

    DOWNLOAD_CMD=""
    if command -v curl &> /dev/null; then
        DOWNLOAD_CMD="curl -Lo $DOWNLOAD_ASSET_NAME $DOWNLOAD_URL"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget -O $DOWNLOAD_ASSET_NAME $DOWNLOAD_URL"
    fi
    
    eval "$DOWNLOAD_CMD"
    if [ $? -ne 0 ]; then
        print_error "Download failed. Please check the URL or your network connection."
        print_error "URL attempted: $DOWNLOAD_URL"
        print_warning "It's possible the asset name pattern has changed or this version/arch is not available."
        print_warning "Please check https://github.com/${GITHUB_REPO}/releases/tag/${CHEAT_VERSION}"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    print_info "Decompressing $DOWNLOAD_ASSET_NAME..."
    gunzip "$DOWNLOAD_ASSET_NAME"
    if [ $? -ne 0 ]; then
        print_error "Decompression failed."
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # The decompressed name is the asset name without .gz
    DECOMPRESSED_NAME="${DOWNLOAD_ASSET_NAME%.gz}"

    print_info "Setting execute permissions for $DECOMPRESSED_NAME..."
    chmod +x "$DECOMPRESSED_NAME"

    print_info "Moving $DECOMPRESSED_NAME to $INSTALL_DIR/$CHEAT_EXECUTABLE_NAME (requires sudo)..."
    if sudo mv "$DECOMPRESSED_NAME" "$INSTALL_DIR/$CHEAT_EXECUTABLE_NAME"; then
        print_success "cheat version $CHEAT_VERSION installed successfully to $INSTALL_DIR/$CHEAT_EXECUTABLE_NAME"
    else
        print_error "Failed to move cheat to $INSTALL_DIR. Check sudo permissions or if directory exists."
        print_warning "You might need to move it manually: sudo mv $TEMP_DIR/$DECOMPRESSED_NAME $INSTALL_DIR/$CHEAT_EXECUTABLE_NAME"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    if command -v $CHEAT_EXECUTABLE_NAME &> /dev/null; then
        print_info "Verifying installation..."
        $CHEAT_EXECUTABLE_NAME --version
    else
        print_error "cheat command not found in PATH after installation."
        return 1
    fi
    return 0
}

display_post_install_guidance() {
    print_header "Cheat Post-Installation Guide & Usage"

    print_info "1. Initialize Cheat (Recommended)"
    echo "   This will create a configuration file and download community cheatsheets."
    print_command "cheat --init"
    echo "   Follow the on-screen prompts from cheat itself."
    echo "   Your config file will likely be at: $(cheat --conf 2>/dev/null || echo '~/.config/cheat/conf.yml')"
    echo "   Default cheatsheet paths can be seen with: $(print_command "cheat --paths")"
    
    print_header "Basic Cheat Usage"
    echo "View a cheatsheet:"
    print_command "cheat tar"
    print_command "cheat find"
    echo -e "\nList all available cheatsheets:"
    print_command "cheat -l"
    echo -e "\nSearch for cheatsheets containing a keyword:"
    print_command "cheat -s copy"
    echo -e "\nEdit an existing cheatsheet (or create a new one if it doesn't exist):"
    print_command "cheat -e mycommand"
    echo -e "\nView cheatsheets for a specific tag (if you use tags):"
    print_command "cheat -t devops"
    echo -e "\nCopy a line from a cheatsheet to clipboard (requires 'copy_cmd' in conf.yml):"
    print_command "cheat -c tar"

    print_header "Downloading/Updating Community Cheatsheets"
    echo "If you didn't run 'cheat --init' or want to update them later:"
    echo "The community cheatsheets are typically stored in a directory like:"
    echo "  ~/.config/cheat/cheatsheets/community/"
    echo "You can manage this directory as a Git repository:"
    print_command "git clone $COMMUNITY_SHEETS_REPO_URL ~/.config/cheat/cheatsheets/community"
    echo "To update later:"
    print_command "cd ~/.config/cheat/cheatsheets/community && git pull"

    print_header "Creating Your Own Cheatsheets"
    echo "1. Where to Create:"
    echo "   - By default, cheat looks for personal cheatsheets in a 'personal' subdirectory within one of its configured paths."
    echo "     A common location after 'cheat --init' might be:"
    print_command "mkdir -p ~/.config/cheat/cheatsheets/personal"
    echo "   - You can also define custom paths using the CHEAT_PATH environment variable or in the 'cheat_path' section of your 'conf.yml'."
    echo "     Example for CHEAT_PATH (add to your ~/.bashrc or ~/.zshrc):"
    print_command "export CHEAT_PATH=\"\$HOME/.my_custom_cheats:\$HOME/.config/cheat/cheatsheets/personal\""
    echo "     (Run 'source ~/.bashrc' or open a new terminal after adding)"
    echo ""
    echo "2. How to Create:"
    echo "   - Cheatsheets are simple text files. The filename is the command (e.g., 'my_script.cheat' or just 'my_script')."
    echo "   - You can use 'cheat -e your_new_command' to open an editor for a new sheet."
    echo "   - Example: Create a file named `~/.config/cheat/cheatsheets/personal/greet`"
    echo "     Contents of the 'greet' file:"
    echo "     ----------------------------------"
    echo "     # To greet someone"
    echo "     echo \"Hello, \$1!\""
    echo ""
    echo "     # To greet the world"
    echo "     echo \"Hello, World!\""
    echo "     ----------------------------------"
    echo "   - Now you can run: $(print_command "cheat greet")"

    print_header "Submitting Cheatsheets to the Community"
    echo "If you've made a cool, general-purpose cheatsheet, consider sharing it!"
    echo "1. The community cheatsheets are hosted on GitHub: $COMMUNITY_SHEETS_REPO_URL"
    echo "2. General Process (familiarity with Git/GitHub is helpful):"
    echo "   a. Fork the repository ($COMMUNITY_SHEETS_REPO_URL) on GitHub."
    echo "   b. Clone your fork locally."
    echo "   c. Create your new cheatsheet file (e.g., 'newtool.cheat') in the appropriate directory within your cloned fork."
    echo "   d. Commit and push your changes to your fork."
    echo "   e. Open a Pull Request (PR) from your fork to the main 'cheat/cheatsheets' repository."
    echo "   f. Follow any contribution guidelines mentioned in their repository (CONTRIBUTING.md, if it exists)."
    print_success "Happy cheating!"
}

# --- Main Script ---
clear
print_header "Enhanced 'cheat' Utility Installer & Guide"
echo "This script will download and install the 'cheat' utility, then provide"
echo "guidance on its usage, configuration, and how to manage cheatsheets."
echo ""

# 0. Check prerequisites
print_info "Checking prerequisites..."
check_command "gunzip" # wget/curl checked in get_latest_cheat_version_tag

# 1. Get latest version (or use default)
get_latest_cheat_version_tag

# 2. Install cheat
if install_cheat; then
    # 3. Display post-installation guidance and usage
    display_post_install_guidance
else
    print_error "Installation failed. Please see messages above."
fi

exit 0
