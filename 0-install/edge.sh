#!/usr/bin/env bash

#
# SYNOPSIS
#    Automates the process of completely resetting Microsoft Edge on Linux, 
#    reinstalling the latest stable version, and applying a predefined set of user 
#    preferences with initial bookmarks.
#
# DESCRIPTION
#    This script performs the following actions:
#    1.  Checks for required root (sudo) privileges.
#    2.  Detects the system's package manager (supports APT and DNF).
#    3.  Defines script parameters for customization (e.g., --force).
#    4.  Prompts for user-defined settings like Home Page and Download Directory.
#    5.  (Conditionally) Kills any running Microsoft Edge processes.
#    6.  (Based on user choice or --force) Purges existing Edge installation and all user data.
#    7.  Adds the official Microsoft repository and GPG key if not already present.
#    8.  Installs the latest 'microsoft-edge-stable' package.
#    9.  Generates a clean 'Preferences' file with custom settings (homepage, downloads, telemetry disabled, etc.).
#   10.  Generates a 'Bookmarks' file with a default set of useful bookmarks.
#   11.  Places the new configuration files in the appropriate user directory.
#   12.  Provides guidance on manual steps for installing extensions.
#
# NOTES
#    Author: Rewritten by an AI Assistant based on a PowerShell script by E-D-H.
#    Version: 1.0
#    This script modifies system packages and user configuration files. 
#    Run with caution. It must be run with 'sudo' or as the root user.
#

# --- Script Configuration & Color Definitions ---
set -Eeuo pipefail # Fail on error, unset variables, and pipe failures.
shopt -s nocasematch # Enable case-insensitive comparisons for user input

# Define colors for output messages
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'

# --- Helper Functions ---
info() { echo -e "${C_CYAN}[INFO]${C_RESET}  $1"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET}  $1"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; }
success() { echo -e "${C_GREEN}[OK]${C_RESET}    $1"; }
prompt() { read -r -p "$(echo -e "${C_WHITE}[PROMPT]${C_RESET} ${1} ")" "${2}"; }

# --- Check for Root Privileges ---
if [[ $EUID -ne 0 ]]; then
   error "This script requires root privileges for package management. Please run with sudo."
   exit 1
fi

# --- Global Variables & Default Parameters ---
FORCE_REINSTALL=false
HOME_PAGE_URL=""
DOWNLOAD_DIR=""
PACKAGE_MANAGER=""
USER_HOME="" # Home directory of the user who ran sudo

# --- Argument Parsing ---
while getopts ":f" opt; do
  case ${opt} in
    f)
      FORCE_REINSTALL=true
      ;;
    \?)
      error "Invalid option: -${OPTARG}"
      exit 1
      ;;
  esac
done

# --- Functions ---

detect_environment() {
    info "Detecting user and package manager..."
    # Detect the home directory of the user who invoked sudo
    USER_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
    if [[ -z "$USER_HOME" ]]; then
        error "Could not determine the home directory of the user. Aborting."
        exit 1
    fi
    success "Running on behalf of user: ${C_WHITE}${SUDO_USER:-$(whoami)}${C_RESET} (Home: $USER_HOME)"

    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
        success "Detected APT package manager (Debian/Ubuntu-based)."
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        success "Detected DNF package manager (Fedora/RHEL-based)."
    else
        error "Unsupported package manager. This script supports 'apt' and 'dnf'."
        exit 1
    fi
}

ask_user_settings() {
    info "Configuring user preferences..."
    
    # Set Home Page
    local default_home_page="https://www.google.com"
    prompt "Enter desired Edge Home Page URL (default: '$default_home_page'):" user_input
    HOME_PAGE_URL="${user_input:-$default_home_page}"
    success "Home Page will be set to: ${C_WHITE}$HOME_PAGE_URL${C_RESET}"

    # Set Download Directory
    local default_download_dir="$USER_HOME/Downloads"
    prompt "Enter desired Edge Download Directory (default: '$default_download_dir'):" user_input
    DOWNLOAD_DIR="${user_input:-$default_download_dir}"
    
    # Create the directory if it doesn't exist, owned by the original user
    if [[ ! -d "$DOWNLOAD_DIR" ]]; then
        warn "Download directory '$DOWNLOAD_DIR' does not exist."
        prompt "Create it now? [Y/n]: " create_choice
        if [[ -z "$create_choice" || "$create_choice" == "y" ]]; then
            info "Creating download directory: $DOWNLOAD_DIR"
            mkdir -p "$DOWNLOAD_DIR"
            chown "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$DOWNLOAD_DIR"
            success "Directory created."
        fi
    fi
    success "Download Directory will be set to: ${C_WHITE}$DOWNLOAD_DIR${C_RESET}"
}

stop_edge_process() {
    info "Checking for running Microsoft Edge processes..."
    if pgrep -f "microsoft-edge" > /dev/null; then
        warn "Microsoft Edge is currently running."
        prompt "To proceed, all Edge processes must be closed. Close them now? [Y/n]: " kill_choice
        if [[ -z "$kill_choice" || "$kill_choice" == "y" ]]; then
            info "Stopping all Microsoft Edge processes..."
            pkill -f "microsoft-edge"
            sleep 2
            success "Processes stopped."
        else
            error "User chose not to close Edge. Script cannot safely proceed."
            exit 1
        fi
    else
        success "No running Microsoft Edge processes found."
    fi
}

uninstall_edge() {
    info "Starting complete uninstallation of Microsoft Edge."
    
    local edge_config_dir="$USER_HOME/.config/microsoft-edge"
    if [[ -d "$edge_config_dir" ]]; then
        info "Removing user configuration directory: $edge_config_dir"
        rm -rf "$edge_config_dir"
        success "User configuration removed."
    else
        info "No existing user configuration directory found."
    fi

    if command -v microsoft-edge-stable &> /dev/null; then
        info "Purging 'microsoft-edge-stable' package..."
        case "$PACKAGE_MANAGER" in
            apt)
                apt-get purge -y microsoft-edge-stable &> /dev/null
                ;;
            dnf)
                dnf remove -y microsoft-edge-stable &> /dev/null
                ;;
        esac
        success "'microsoft-edge-stable' package purged."
    else
        info "'microsoft-edge-stable' package not found. Skipping purge."
    fi
}

install_edge() {
    info "Preparing to install Microsoft Edge..."

    # Setup repository based on package manager
    case "$PACKAGE_MANAGER" in
        apt)
            info "Setting up Microsoft repository for APT..."
            local repo_file="/etc/apt/sources.list.d/microsoft-edge.list"
            if [[ ! -f "$repo_file" ]]; then
                # Add MS GPG Key and Repo
                install -o root -g root -m 644 <(wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor) /etc/apt/trusted.gpg.d/packages.microsoft.gpg
                echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" > "$repo_file"
                success "Microsoft APT repository added."
            else
                success "Microsoft APT repository already configured."
            fi
            info "Updating package lists..."
            apt-get update &> /dev/null
            ;;
        dnf)
            info "Setting up Microsoft repository for DNF..."
            local repo_file="/etc/yum.repos.d/microsoft-edge.repo"
            if [[ ! -f "$repo_file" ]]; then
                rpm --import https://packages.microsoft.com/keys/microsoft.asc
                dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/edge
                # The default name is ugly, rename it
                mv /etc/yum.repos.d/packages.microsoft.com_yumrepos_edge.repo "$repo_file" &>/dev/null || true
                success "Microsoft YUM/DNF repository added."
            else
                success "Microsoft YUM/DNF repository already configured."
            fi
            ;;
    esac

    info "Installing 'microsoft-edge-stable'..."
    case "$PACKAGE_MANAGER" in
        apt)
            apt-get install -y microsoft-edge-stable
            ;;
        dnf)
            dnf install -y microsoft-edge-stable
            ;;
    esac
    
    if ! command -v microsoft-edge-stable &> /dev/null; then
        error "Microsoft Edge installation failed. Please check your connection or package manager output."
        exit 1
    fi
    success "Microsoft Edge installed successfully."
}

apply_edge_customizations() {
    info "Applying custom configurations..."
    local config_dir="$USER_HOME/.config/microsoft-edge/Default"
    
    # Edge creates the ~/.config/microsoft-edge directory but not the Default profile on install
    # We create it to place our files inside.
    info "Ensuring profile directory exists: $config_dir"
    mkdir -p "$config_dir"

    # --- Create Preferences file ---
    local preferences_file="$config_dir/Preferences"
    info "Generating new preferences file: $preferences_file"
    
    # Escape for JSON: backslashes in download path
    local json_download_dir="${DOWNLOAD_DIR//\//\\/}"

    # Use a HEREDOC to create the JSON structure
    cat > "$preferences_file" << PREFS_EOF
{
    "bookmark_bar": {
        "show": true
    },
    "browser": {
        "has_been_opened": false,
        "show_window_on_first_run": true,
        "tabs": {
            "vertical_tabs_enabled": true
        }
    },
    "download": {
        "default_directory": "$DOWNLOAD_DIR",
        "directory_upgrade": true,
        "prompt_for_download": false
    },
    "metrics": {
        "enabled": false
    },
    "session": {
        "restore_on_startup": 4,
        "startup_urls": [
            "$HOME_PAGE_URL"
        ]
    },
    "user_experience_metrics": {
        "reporting_enabled": false
    }
}
PREFS_EOF
    success "Preferences file created."

    # --- Create Bookmarks file ---
    local bookmarks_file="$config_dir/Bookmarks"
    info "Generating new bookmarks file: $bookmarks_file"

    cat > "$bookmarks_file" << BOOKMARKS_EOF
{
   "checksum": "000000000000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [
            { "date_added": "13361427155000000", "id": "1", "name": "Google", "type": "url", "url": "https://www.google.com/" },
            { "date_added": "13361427156000000", "id": "2", "name": "YouTube", "type": "url", "url": "https://www.youtube.com/" },
            { "date_added": "13361427157000000", "id": "3", "name": "Microsoft Copilot", "type": "url", "url": "https://copilot.microsoft.com/" },
            { "date_added": "13361427158000000", "id": "4", "name": "GitHub", "type": "url", "url": "https://github.com/" },
            { "date_added": "13361427159000000", "id": "5", "name": "Wikipedia", "type": "url", "url": "https://www.wikipedia.org/" },
            { "date_added": "13361427160000000", "id": "6", "name": "Ars Technica", "type": "url", "url": "https://arstechnica.com/" }
         ],
         "date_added": "13361427154000000",
         "date_modified": "0",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": { "children": [], "date_added": "13361427154000000", "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder" },
      "synced": { "children": [], "date_added": "13361427154000000", "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder" }
   },
   "version": 1
}
BOOKMARKS_EOF
    success "Bookmarks file created."

    # Set correct ownership for all created files/dirs
    info "Setting correct ownership for '$USER_HOME/.config/microsoft-edge'..."
    chown -R "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$USER_HOME/.config/microsoft-edge"
    success "Ownership set."
}

print_final_notes() {
    echo -e "\n${C_CYAN}---------------------------------------------------------------------"
    echo -e "Microsoft Edge reset script finished."
    echo -e "---------------------------------------------------------------------${C_RESET}\n"
    echo -e "${C_WHITE}IMPORTANT NEXT STEPS & NOTES:${C_RESET}"
    echo -e " - ${C_GREEN}First Launch:${C_RESET} The next time you start Microsoft Edge, it will be a clean profile with your settings."
    echo -e " - ${C_GREEN}Bookmarks:${C_RESET} A default set of bookmarks has been added to your bookmarks bar."
    echo -e " - ${C_GREEN}Vertical Tabs:${C_RESET} This feature has been enabled by default. Right-click the title bar to toggle."
    echo -e " - ${C_YELLOW}Extensions:${C_RESET} Extensions must be installed manually from the Microsoft Edge Add-ons store."
    echo -e "   You can find popular extensions like uBlock Origin there."
    echo -e "\n"
}


# --- Main Script Logic ---
main() {
    detect_environment
    
    local perform_install_steps=false
    if [[ "$FORCE_REINSTALL" == true ]]; then
        info "'-f' flag was used. Forcing full reinstall."
        perform_install_steps=true
    elif ! command -v microsoft-edge-stable &> /dev/null; then
        info "Microsoft Edge is not installed. Proceeding with installation."
        perform_install_steps=true
    else
        warn "Microsoft Edge is already installed."
        prompt "Do you want to completely uninstall it and all its data, then reinstall? [y/N]: " reinstall_choice
        if [[ "$reinstall_choice" == "y" ]]; then
            perform_install_steps=true
        else
            info "Reinstallation skipped. The script will only apply profile settings."
        fi
    fi
    
    # Stop any running instances
    stop_edge_process

    if [[ "$perform_install_steps" == true ]]; then
        uninstall_edge
        install_edge
    fi

    # Always ask for settings and apply them
    ask_user_settings
    apply_edge_customizations
    
    print_final_notes
}

# --- Execute Script ---
main "$@"
