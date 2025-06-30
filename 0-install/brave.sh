#!/usr/bin/env bash

#
# SYNOPSIS
#   Automates the process of completely resetting Brave Browser on Linux,
#   reinstalling the latest stable version, and applying a clean configuration.
#   Designed for daily automated refresh to maintain a pristine environment.
#
# DESCRIPTION
#   This script is run as a normal user. It will automatically request
#   administrator (sudo) privileges when it needs to manage software packages
#   or modify system files.
#
# USAGE
#   ./brave-reset.sh [OPTIONS]
#
# OPTIONS
#   -f, --force-reinstall   Force complete reinstallation even if up-to-date
#   -q, --quiet             Suppress non-essential output
#   -y, --yes               Assume 'yes' to all prompts (for automation)
#   -k, --keep-bookmarks    Preserve bookmarks during reset (backup/restore)
#   -h, --help              Show this help message
#
# NOTES
#   Author: AI Assistant (Based on user feedback)
#   Version: 3.0
#   This script is designed to be idempotent and safe for daily automation.
#

# --- Script Configuration & Error Handling ---
set -Eeuo pipefail # Fail on error, unset variables, and pipe failures
shopt -s nocasematch # Enable case-insensitive comparisons

# --- Global Variables ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="3.0"
readonly BRAVE_PACKAGE="brave-browser"
readonly LOG_FILE="/tmp/brave-reset-$(date +%Y%m%d-%H%M%S).log"

# Define colors for output (disabled if not a TTY or in quiet mode)
if [[ -t 1 ]] && [[ "${QUIET:-false}" != "true" ]]; then
    readonly C_RESET='\033[0m'
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_CYAN='\033[0;36m'
    readonly C_WHITE='\033[1;37m'
    readonly C_BLUE='\033[0;34m'
else
    readonly C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_WHITE='' C_BLUE=''
fi

# Configuration flags
FORCE_REINSTALL=false
QUIET=false
ASSUME_YES=false
KEEP_BOOKMARKS=false
PACKAGE_MANAGER=""
USER_HOME=""
CURRENT_USER=""
HAS_GUI=false

# --- Helper Functions ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

info() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${C_CYAN}[INFO]${C_RESET}  $1"
    log "INFO: $1"
}

warn() {
    echo -e "${C_YELLOW}[WARN]${C_RESET}  $1" >&2
    log "WARN: $1"
}

error() {
    echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2
    log "ERROR: $1"
}

success() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${C_GREEN}[OK]${C_RESET}    $1"
    log "OK: $1"
}

prompt() {
    [[ "$ASSUME_YES" == "true" ]] && return 0
    local message="$1"
    local default="${2:-y}"
    local response

    read -r -p "$(echo -e "${C_WHITE}[PROMPT]${C_RESET} ${message} [${default}/n]: ")" response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

# --- Cleanup Function ---
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then # 130 is exit code for Ctrl+C
        error "Script failed with exit code $exit_code"
        info "Log file available at: $LOG_FILE"
    fi
    exit $exit_code
}

trap cleanup EXIT

# --- Privilege Management ---
elevate_privileges() {
    # If we can run `sudo` non-interactively, we don't need to prompt.
    sudo -n true 2>/dev/null && return 0

    info "Administrative privileges are required to manage packages and system files."
    if prompt "This script will use 'sudo' to continue. Proceed?"; then
        # -v will prompt for a password and cache it.
        if ! sudo -v; then
            error "Failed to obtain administrative privileges. Aborting."
            exit 1
        fi
        success "Privileges acquired."
    else
        error "User declined privilege escalation. Aborting."
        exit 1
    fi
}

# --- Help Function ---
show_help() {
    cat << EOF
${C_WHITE}Brave Browser Reset & Installer Script v${SCRIPT_VERSION}${C_RESET}

${C_CYAN}SYNOPSIS${C_RESET}
    Completely resets Brave Browser on Linux, ensuring a pristine environment.
    This script is run as a normal user and will request sudo privileges on its own.

${C_CYAN}USAGE${C_RESET}
    $SCRIPT_NAME [OPTIONS]

${C_CYAN}OPTIONS${C_RESET}
    ${C_GREEN}-f, --force-reinstall${C_RESET}   Force complete reinstallation even if up-to-date
    ${C_GREEN}-q, --quiet${C_RESET}             Suppress non-essential output
    ${C_GREEN}-y, --yes${C_RESET}               Assume 'yes' to all prompts (for automation)
    ${C_GREEN}-k, --keep-bookmarks${C_RESET}    Preserve bookmarks during reset
    ${C_GREEN}-h, --help${C_RESET}              Show this help message
EOF
}

# --- Argument Parsing ---
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force-reinstall) FORCE_REINSTALL=true; shift ;;
            -q|--quiet) QUIET=true; shift ;;
            -y|--yes) ASSUME_YES=true; shift ;;
            -k|--keep-bookmarks) KEEP_BOOKMARKS=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) error "Unknown option: $1"; echo "Use -h or --help for usage information."; exit 1 ;;
        esac
    done
}

# --- System Detection (runs as user) ---
detect_environment() {
    info "Detecting system environment..."

    CURRENT_USER="$(whoami)"
    USER_HOME="$HOME"
    success "Running for user: ${C_WHITE}$CURRENT_USER${C_RESET} (Home: $USER_HOME)"

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
        success "Detected APT package manager (Debian/Ubuntu-based)"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        success "Detected DNF package manager (Fedora/RHEL-based)"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
        success "Detected Pacman package manager (Arch-based)"
    else
        error "Unsupported package manager. This script supports APT, DNF, and Pacman."
        exit 1
    fi

    # Detect GUI environment (now runs as user, so it will work reliably)
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || (command -v loginctl &>/dev/null && loginctl show-session "$(loginctl list-sessions --no-legend | grep "$CURRENT_USER" | awk '{print $1}' | head -n 1)" -p Type --value | grep -qE 'x11|wayland') ; then
        HAS_GUI=true
        success "GUI environment detected"
    else
        info "Headless environment detected (no GUI setup will be performed)"
    fi
}

# --- Process Management ---
stop_brave_processes() {
    info "Checking for running Brave processes..."
    # pgrep doesn't need sudo if just checking own user's processes
    local brave_pids
    brave_pids=$(pgrep -u "$CURRENT_USER" -f "$BRAVE_PACKAGE" 2>/dev/null || true)

    if [[ -n "$brave_pids" ]]; then
        warn "Found running Brave processes: $brave_pids"
        if prompt "Stop all Brave processes to continue?"; then
            info "Gracefully stopping Brave processes..."
            # Kill doesn't need sudo for own processes
            pkill -u "$CURRENT_USER" -f -TERM "$BRAVE_PACKAGE" 2>/dev/null || true
            sleep 2
            # Force kill remaining processes
            pkill -u "$CURRENT_USER" -f -KILL "$BRAVE_PACKAGE" 2>/dev/null || true
            success "Brave processes stopped"
        else
            error "Cannot proceed with Brave processes running."
            exit 1
        fi
    else
        success "No running Brave processes found"
    fi
}

# --- Backup and Uninstall ---
uninstall_brave() {
    info "Starting complete uninstallation of Brave Browser..."
    local bookmarks_backup=""

    # Backup bookmarks (no sudo needed)
    if [[ "$KEEP_BOOKMARKS" == "true" ]]; then
        local bookmarks_file="$USER_HOME/.config/BraveSoftware/Brave-Browser/Default/Bookmarks"
        if [[ -f "$bookmarks_file" ]]; then
            local backup_file="/tmp/brave-bookmarks-backup-$(date +%Y%m%d-%H%M%S).json"
            info "Backing up bookmarks to: $backup_file"
            cp "$bookmarks_file" "$backup_file"
            bookmarks_backup="$backup_file"
        fi
    fi

    # Remove user configuration and caches (no sudo needed)
    info "Removing user configuration and cache directories..."
    rm -rf "$USER_HOME/.config/BraveSoftware"
    rm -rf "$USER_HOME/.cache/BraveSoftware"

    # Uninstall package (sudo required)
    if dpkg -s "$BRAVE_PACKAGE" &>/dev/null; then
        info "Uninstalling Brave Browser package..."
        case "$PACKAGE_MANAGER" in
            apt)
                sudo apt-get purge -y "$BRAVE_PACKAGE" &>/dev/null
                sudo apt-get autoremove -y &>/dev/null
                ;;
            dnf) sudo dnf remove -y "$BRAVE_PACKAGE" &>/dev/null ;;
            pacman) sudo pacman -Rns --noconfirm "$BRAVE_PACKAGE" &>/dev/null ;;
        esac
        success "Brave Browser package removed."
    else
        info "Brave Browser not installed, skipping package removal."
    fi

    echo "$bookmarks_backup"
}

# --- Installation ---
install_brave_package() {
    info "Setting up and installing Brave Browser..."
    case "$PACKAGE_MANAGER" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y curl gnupg
            curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-core.asc | sudo gpg --dearmor -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
            sudo apt-get update -qq
            sudo apt-get install -y "$BRAVE_PACKAGE"
            ;;
        dnf)
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/x86_64/
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.gpg
            sudo dnf install -y "$BRAVE_PACKAGE"
            ;;
        pacman)
            # Arch users often have an AUR helper or know how to build packages.
            # This is a basic attempt that assumes a helper that works with `sudo pacman`.
            warn "For Arch Linux, you may need an AUR helper like 'yay' or 'paru'."
            warn "This script will attempt a standard installation."
            sudo pacman -S --noconfirm --needed git base-devel
            # Simple yay check
            if command -v yay &>/dev/null; then
                 yay -S --noconfirm "$BRAVE_PACKAGE"
            else
                 error "No AUR helper found. Please install Brave manually."
                 exit 1
            fi
            ;;
    esac

    if ! command -v brave-browser &>/dev/null; then
        error "Brave Browser installation failed."
        exit 1
    fi
    success "Brave Browser installed successfully."
}

# --- Post-Install Configuration ---
configure_brave() {
    # Restore bookmarks if a backup was made
    if [[ "$KEEP_BOOKMARKS" == "true" && -n "${1:-}" && -f "$1" ]]; then
        info "Restoring bookmarks..."
        local bookmarks_dir="$USER_HOME/.config/BraveSoftware/Brave-Browser/Default"
        mkdir -p "$bookmarks_dir"
        cp "$1" "$bookmarks_dir/Bookmarks"
        success "Bookmarks restored."
        rm -f "$1"
    fi

    # Create desktop entry if in a GUI environment
    if [[ "$HAS_GUI" == "true" ]]; then
        info "Updating desktop applications database..."
        update-desktop-database -q "$USER_HOME/.local/share/applications"
    fi
}

# --- Main Logic ---
main() {
    info "Starting Brave Browser Reset & Installer v$SCRIPT_VERSION"
    parse_arguments "$@"
    detect_environment

    local perform_action=false
    if [[ "$FORCE_REINSTALL" == "true" ]]; then
        info "Forcing reinstallation as requested."
        perform_action=true
    elif ! command -v brave-browser &> /dev/null; then
        info "Brave Browser is not installed."
        perform_action=true
    else
        info "Brave is already installed."
        if prompt "Do you want to completely reset and reinstall it anyway?"; then
            perform_action=true
        fi
    fi

    if [[ "$perform_action" == "true" ]]; then
        # Elevate privileges right before they are needed.
        elevate_privileges
        stop_brave_processes
        local bookmarks_backup
        bookmarks_backup=$(uninstall_brave)
        install_brave_package
        configure_brave "$bookmarks_backup"
        success "Brave Browser has been successfully reset and installed."
    else
        info "No action taken. Exiting."
    fi

    echo -e "\n${C_GREEN}✓ Script completed.${C_RESET}"
}

# --- Script Entry Point ---
main "$@"
