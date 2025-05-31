#!/usr/bin/env bash
# Author: Roy Wiseman 2025-05
#
# yt-dlp-get.sh: Checks for and installs/updates yt-dlp to the latest GitHub version.
# It handles removal of apt-installed versions.
#

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate pipe failures.
# set -u # Uncomment for stricter debugging of unset variables

# --- Configuration ---
GITHUB_REPO="yt-dlp/yt-dlp"
INSTALL_DIR="$HOME/.local/bin"
EXE_NAME="yt-dlp"
TARGET_EXE_PATH="$INSTALL_DIR/$EXE_NAME"

# --- Helper Functions ---
# Color codes
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'

# Print messages
msg() {
    echo -e "${COLOR_BLUE}[*]${COLOR_RESET} $1"
}
msg_ok() {
    echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $1"
}
msg_warn() {
    echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"
}
msg_error() {
    echo -e "${COLOR_RED}[-]${COLOR_RESET} $1" >&2
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a directory is in PATH
is_dir_in_path() {
    local dir_to_check="$1"
    if [[ ":$PATH:" == *":$dir_to_check:"* ]]; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Check for essential dependencies
check_dependencies() {
    msg "Checking for essential dependencies..."
    local missing_deps=0
    local deps=("curl" "grep" "sed" "mktemp")

    if command_exists dpkg && command_exists apt-get; then
        msg_ok "dpkg and apt-get found (for managing apt packages)."
    else
        msg_warn "dpkg or apt-get not found. Cannot manage apt-installed yt-dlp."
        # This is not fatal if yt-dlp is not apt-installed or not installed at all.
    fi

    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            msg_error "Missing dependency: $dep. Please install it."
            missing_deps=1
        fi
    done

    if [ "$missing_deps" -eq 1 ]; then
        msg_error "Please install missing dependencies and try again."
        exit 1
    fi
    msg_ok "All essential dependencies found."
}

# Get currently installed yt-dlp path and version
get_current_ytdlp_info() {
    CURRENT_YTDLP_PATH=""
    CURRENT_YTDLP_VERSION=""
    IS_APT_MANAGED=false

    if command_exists "$EXE_NAME"; then
        CURRENT_YTDLP_PATH=$(command -v "$EXE_NAME")
        # Try to get version
        if [ -n "$CURRENT_YTDLP_PATH" ] && [ -x "$CURRENT_YTDLP_PATH" ]; then
            CURRENT_YTDLP_VERSION=$("$CURRENT_YTDLP_PATH" --version 2>/dev/null | head -n1) || CURRENT_YTDLP_VERSION="unknown"
        else
            CURRENT_YTDLP_VERSION="unknown" # Path found but not executable or version command failed
        fi

        # Check if managed by dpkg (apt)
        if command_exists dpkg && dpkg -S "$CURRENT_YTDLP_PATH" >/dev/null 2>&1; then
            IS_APT_MANAGED=true
            local apt_version
            apt_version=$(dpkg-query -W -f='${Version}' yt-dlp 2>/dev/null || echo "apt-version-unknown")
            msg_warn "Found yt-dlp at $CURRENT_YTDLP_PATH (version $CURRENT_YTDLP_VERSION, reported by apt as $apt_version)."
            msg_warn "This appears to be managed by apt."
        elif [ -n "$CURRENT_YTDLP_PATH" ]; then
            msg_ok "Found manually installed yt-dlp at $CURRENT_YTDLP_PATH (version $CURRENT_YTDLP_VERSION)."
        fi
    else
        msg "yt-dlp not found in PATH."
    fi
}

# Uninstall apt version of yt-dlp
uninstall_apt_ytdlp() {
    if ! command_exists apt-get || ! command_exists sudo; then
        msg_error "apt-get or sudo command not found. Cannot uninstall apt version."
        return 1
    fi
    msg_warn "The apt version of yt-dlp can cause issues and is often outdated."
    read -r -p "Do you want to uninstall the apt version of yt-dlp? This requires sudo. (y/N): " confirmation
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        msg "Uninstalling apt version of yt-dlp..."
        if sudo apt-get remove -y yt-dlp; then
            msg_ok "Successfully removed yt-dlp package."
            read -r -p "Do you want to run 'sudo apt autoremove' to remove unused dependencies? (y/N): " autoremove_confirm
            if [[ "$autoremove_confirm" =~ ^[Yy]$ ]]; then
                sudo apt-get autoremove -y
                msg_ok "Successfully ran apt autoremove."
            fi
            CURRENT_YTDLP_PATH="" # Reset, as it's gone
            CURRENT_YTDLP_VERSION=""
            IS_APT_MANAGED=false # No longer apt managed
            return 0
        else
            msg_error "Failed to uninstall apt version of yt-dlp."
            return 1
        fi
    else
        msg "Skipping uninstallation of apt version. The script will not proceed with GitHub version."
        return 1
    fi
}

# Get latest version from GitHub
get_latest_github_version() {
    msg "Fetching latest yt-dlp version from GitHub..."
    
    # Use sed to directly parse curl output and extract the tag_name value.
    # -n: suppress automatic printing of pattern space
    # -E: use extended regular expressions
    # s/.../.../p: substitute and print if successful
    # ^[[:space:]]* : matches any leading spaces on the line
    # "tag_name":[[:space:]]* : matches "tag_name": and any following spaces
    # "\([^"]+\)" : captures the version string (one or more characters that are not a quote)
    # .* : matches the rest of the line
    # \1 : the captured version string
    LATEST_GITHUB_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
                            sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*/\1/p')

    if [ -z "$LATEST_GITHUB_VERSION" ]; then
        msg_error "Failed to fetch or parse the latest version from GitHub. The extracted version string was empty."
        msg_error "Please check your internet connection and ensure GitHub API is accessible."
        exit 1
    fi

    # Sanity check the extracted version string
    if [[ "$LATEST_GITHUB_VERSION" =~ [[:space:]\'\":\{\}] ]]; then # Checks for spaces, quotes, colons, braces
        msg_error "Fetched version string appears malformed: '$LATEST_GITHUB_VERSION'"
        msg_error "This might indicate an issue with the script's parsing logic or a change in GitHub API response format."
        msg_error "Ensure the get_latest_github_version function in the script is up-to-date with the latest provided version."
        exit 1
    fi

    msg_ok "Latest GitHub version: $LATEST_GITHUB_VERSION"
}

# Download and install/update yt-dlp
download_and_install_ytdlp() {
    local version_tag="$1"
    # Correctly define the asset name on GitHub for Linux
    local github_asset_name_on_server="yt-dlp_linux"

    msg "Preparing to install yt-dlp version $version_tag to $TARGET_EXE_PATH..."
    # $TARGET_EXE_PATH is "$INSTALL_DIR/$EXE_NAME" which resolves to "$HOME/.local/bin/yt-dlp"

    if ! mkdir -p "$INSTALL_DIR"; then
        msg_error "Failed to create installation directory: $INSTALL_DIR"
        msg_error "Please check permissions or create it manually."
        exit 1
    fi

    local download_url="https://github.com/$GITHUB_REPO/releases/download/$version_tag/$github_asset_name_on_server"
    local temp_file
    temp_file=$(mktemp)

    if [ -z "$temp_file" ]; then
        msg_error "Failed to create a temporary file."
        exit 1
    fi

    msg "Downloading $download_url ..." # This will now show the correct asset name
    if curl -SL --progress-bar -o "$temp_file" "$download_url"; then
        msg_ok "Download complete."
        if chmod +x "$temp_file"; then
            msg_ok "Made temporary file executable."
            
            # Check if target exists and if it's a symlink or a file before overwriting
            if [ -e "$TARGET_EXE_PATH" ] && [ ! -L "$TARGET_EXE_PATH" ]; then
                 msg_warn "An existing file at $TARGET_EXE_PATH will be overwritten."
            elif [ -L "$TARGET_EXE_PATH" ]; then
                 msg_warn "An existing symlink at $TARGET_EXE_PATH will be overwritten."
            fi

            # Move the downloaded file (e.g., yt-dlp_linux) to the target path (e.g., ~/.local/bin/yt-dlp)
            # This also handles the renaming from "yt-dlp_linux" to "yt-dlp"
            if mv "$temp_file" "$TARGET_EXE_PATH"; then
                msg_ok "yt-dlp version $version_tag (downloaded as $github_asset_name_on_server) installed successfully as $TARGET_EXE_PATH"
                
                # Verify installation by checking the version of the installed file
                local installed_version
                installed_version=$("$TARGET_EXE_PATH" --version 2>/dev/null | head -n1)
                if [ "$installed_version" == "$version_tag" ]; then
                    msg_ok "Verification successful: Installed version is $installed_version."
                else
                    msg_warn "Verification issue: Installed version reports '$installed_version', expected '$version_tag'."
                    msg_warn "This could be a temporary issue or a problem with the downloaded file."
                fi

                # Check if INSTALL_DIR is in PATH
                if ! is_dir_in_path "$INSTALL_DIR"; then
                    msg_warn "Directory $INSTALL_DIR is not in your PATH."
                    msg_warn "You may need to add it to your shell's configuration file (e.g., ~/.bashrc, ~/.zshrc):"
                    msg_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                    msg_warn "Then, open a new terminal or source the file (e.g., 'source ~/.bashrc')."
                else
                    msg_ok "$INSTALL_DIR is in your PATH."
                fi
            else
                msg_error "Failed to move downloaded file to $TARGET_EXE_PATH."
                msg_error "Please check permissions for $INSTALL_DIR."
                rm -f "$temp_file" # Clean up temp file on error
                exit 1
            fi
        else
            msg_error "Failed to make downloaded file executable."
            rm -f "$temp_file" # Clean up temp file
            exit 1
        fi
    else
        msg_error "Download failed from $download_url."
        rm -f "$temp_file" # Clean up temp file
        exit 1
    fi
}

# --- Main Logic ---
main() {
    check_dependencies
    get_current_ytdlp_info

    if [ "$IS_APT_MANAGED" = true ]; then
        if ! uninstall_apt_ytdlp; then
            msg "Exiting as apt version was not uninstalled."
            exit 0 # User chose not to uninstall, or uninstallation failed.
        fi
        # Re-check info after potential uninstall
        get_current_ytdlp_info
    fi

    get_latest_github_version

    if [ -z "$CURRENT_YTDLP_VERSION" ] || [ "$CURRENT_YTDLP_VERSION" == "unknown" ]; then
        msg "yt-dlp is not installed or current version is unknown."
        download_and_install_ytdlp "$LATEST_GITHUB_VERSION"
    elif [ "$CURRENT_YTDLP_VERSION" == "$LATEST_GITHUB_VERSION" ]; then
        msg_ok "You already have the latest version of yt-dlp ($CURRENT_YTDLP_VERSION) at $CURRENT_YTDLP_PATH."
        # Ensure it's in the target location if it matches version but not path
        if [ "$CURRENT_YTDLP_PATH" != "$TARGET_EXE_PATH" ]; then
             msg_warn "However, it's not in the standard user path ($TARGET_EXE_PATH)."
             msg_warn "This script installs to $TARGET_EXE_PATH."
             # Optionally, offer to move/reinstall it here. For now, just inform.
        fi
    else
        msg "Current version ($CURRENT_YTDLP_VERSION) is older than the latest GitHub version ($LATEST_GITHUB_VERSION)."
        download_and_install_ytdlp "$LATEST_GITHUB_VERSION"
    fi

    msg_ok "Script finished."
}

# Run main function
main


