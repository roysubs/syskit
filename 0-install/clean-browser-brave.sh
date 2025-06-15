#!/usr/bin/env bash

#
# SYNOPSIS
#   Automates the process of completely resetting Brave Browser on Linux,
#   reinstalling the latest stable version, and applying a clean configuration
#   with optional helpers for extensions and ad-block lists.
#
# DESCRIPTION
#   This script is run as a normal user. It will automatically request
#   administrator (sudo) privileges when it needs to manage software packages.
#
#   Running without flags will trigger a safe, interactive confirmation prompt.
#   Use -f or --force-reinstall for automated (non-interactive) runs.
#
# USAGE
#   ./brave.sh [OPTIONS]
#
# OPTIONS
#   -f, --force-reinstall   Force a full reinstallation (non-interactive).
#   -p, --purge             Completely uninstall Brave and all its data.
#       --install-helpers   Opens tabs to help one-click install of useful extensions.
#       --with-filters      Add extra ad-blocking filter lists to Brave Shields.
#       --vertical-tabs     Enable Vertical Tabs feature by default.
#   -k, --keep-bookmarks    Preserve bookmarks during reset.
#   -y, --yes               Assume 'yes' to all prompts (for automation).
#   -h, --help              Show this help message.
#
# NOTES
#   Author: Roy Wiseman
#   Version: 4.6
#

# --- Script Configuration & Error Handling ---
set -Eeuo pipefail
shopt -s nocasematch

# --- Global Variables ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="4.6"
readonly BRAVE_PACKAGE="brave-browser"
readonly BRAVE_PROCESS_PATTERN="brave"
readonly LOG_FILE="/tmp/brave-reset-$(date +%Y%m%d-%H%M%S).log"

# Define colors for output
if [[ -t 1 ]]; then
    # CORRECT: Use $'...' to interpret escape codes
    readonly C_RESET=$'\033[0m' C_RED=$'\033[0;31m' C_GREEN=$'\033[0;32m' C_YELLOW=$'\033[0;33m' C_CYAN=$'\033[0;36m' C_WHITE=$'\033[1;37m'
else
    # This part is fine as-is
    readonly C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_WHITE=''
fi

# Configuration flags
FORCE_REINSTALL=false
PURGE_ONLY=false
INSTALL_HELPERS=false
WITH_FILTERS=false
VERTICAL_TABS=false
KEEP_BOOKMARKS=false
ASSUME_YES=false
PACKAGE_MANAGER=""
USER_HOME=""
CURRENT_USER=""
HAS_GUI=false

# --- Helper Functions ---
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }
info() { echo -e "${C_CYAN}[INFO]${C_RESET}  $1"; log "INFO: $1"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET}  $1" >&2; log "WARN: $1"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; log "ERROR: $1"; }
success() { echo -e "${C_GREEN}[OK]${C_RESET}    $1"; log "OK: $1"; }
prompt() {
    [[ "$ASSUME_YES" == "true" ]] && return 0
    local message="$1" response
    read -r -p "$(echo -e "${C_WHITE}[PROMPT]${C_RESET} ${message} [y/N]: ")" response
    [[ "$response" =~ ^[Yy]$ ]]
}
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
        error "Script exited with an error (code: $exit_code)."
        info "Log file available at: $LOG_FILE"
    fi
    exit $exit_code
}

# --- Privilege Management ---
elevate_privileges() {
    sudo -n true 2>/dev/null && return 0
    info "Administrative privileges are required for system changes."
    if [[ "$ASSUME_YES" == "true" ]] || prompt "This script will use 'sudo' to continue. Proceed?"; then
        if ! sudo -v; then error "Failed to obtain administrative privileges. Aborting."; exit 1; fi
        success "Privileges acquired."
    else
        error "User declined privilege escalation. Aborting."; exit 1
    fi
}

# --- Help Function ---
show_help() {
    cat << EOF
${C_WHITE}Brave Browser Reset & Installer v${SCRIPT_VERSION}${C_RESET}

${C_CYAN}SYNOPSIS${C_RESET}
    Completely resets and reinstalls Brave Browser with opinionated privacy extras.
    Run as a normal user; the script will request sudo privileges when needed.

${C_CYAN}USAGE${C_RESET}
    $SCRIPT_NAME [OPTIONS]

${C_CYAN}OPTIONS${C_RESET}
    ${C_GREEN}-f, --force-reinstall${C_RESET}    Force a full reinstallation (non-interactive).
    ${C_GREEN}-p, --purge, --uninstall${C_RESET} Completely uninstall Brave and all its data.
    ${C_GREEN}    --install-helpers${C_RESET}    Opens tabs to help one-click install of useful extensions.
    ${C_GREEN}    --with-filters${C_RESET}       Add extra ad-blocking filter lists to Brave Shields.
    ${C_GREEN}    --vertical-tabs${C_RESET}      Enable the Vertical Tabs feature by default.
    ${C_GREEN}-k, --keep-bookmarks${C_RESET}     Preserve bookmarks during the reset process.
    ${C_GREEN}-y, --yes${C_RESET}                Assume 'yes' to all prompts (for automation).
    ${C_GREEN}-h, --help${C_RESET}               Show this help message.
EOF
    exit 0
}

# --- Argument Parsing ---
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force-reinstall) FORCE_REINSTALL=true; shift ;;
            -p|--purge|--uninstall) PURGE_ONLY=true; shift ;;
            --install-helpers) INSTALL_HELPERS=true; shift ;;
            --with-filters) WITH_FILTERS=true; shift ;;
            --vertical-tabs) VERTICAL_TABS=true; shift ;;
            -k|--keep-bookmarks) KEEP_BOOKMARKS=true; shift ;;
            -y|--yes) ASSUME_YES=true; shift ;;
            -h|--help) show_help ;;
            *) error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# --- System Detection ---
detect_environment() {
    info "Detecting system environment..."
    CURRENT_USER="$(whoami)"
    USER_HOME="$HOME"
    success "Running for user: ${C_WHITE}$CURRENT_USER${C_RESET}"

    if command -v apt-get &>/dev/null; then PACKAGE_MANAGER="apt";
    else error "Unsupported package manager. This script currently requires APT (Debian/Ubuntu/Mint)."; exit 1; fi
    success "Detected APT package manager."

    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then HAS_GUI=true;
    elif (command -v loginctl &>/dev/null && loginctl show-session "$(loginctl list-sessions --no-legend | grep -w "$CURRENT_USER" | awk '{print $1}' | head -n 1)" -p Type --value | grep -qE 'x11|wayland' &>/dev/null) ; then HAS_GUI=true;
    fi

    if [[ "$HAS_GUI" == "true" ]]; then success "GUI environment detected.";
    else warn "Headless environment (or SSH session) detected. A GUI is needed to use Brave Browser."; fi
}

# --- Core Functions ---
stop_brave_processes() {
    local brave_pids
    brave_pids=$(pgrep -u "$CURRENT_USER" -f "$BRAVE_PROCESS_PATTERN" | grep -v "$$" || true)

    if [[ -n "$brave_pids" ]]; then
        info "Stopping running Brave processes..."
        kill -s SIGTERM $brave_pids 2>/dev/null || true
        sleep 1
        brave_pids=$(pgrep -u "$CURRENT_USER" -f "$BRAVE_PROCESS_PATTERN" | grep -v "$$" || true)
        if [[ -n "$brave_pids" ]]; then
            kill -s SIGKILL $brave_pids 2>/dev/null || true
        fi
        success "Brave processes stopped."
    fi
}

purge_system() {
    info "Starting complete system purge of Brave Browser."
    elevate_privileges
    stop_brave_processes

    info "Removing user configuration and cache..."
    rm -rf "$USER_HOME/.config/BraveSoftware" "$USER_HOME/.cache/BraveSoftware"
    success "User data removed."

    info "Removing Brave package, repository, and policy files..."
    sudo apt-get purge -y "$BRAVE_PACKAGE" &>/dev/null
    sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
    sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
    sudo apt-get update -qq
    success "Brave package and system files removed."
}

reinstall_system() {
    if [[ "$HAS_GUI" == "false" ]]; then
      if ! prompt "Install Brave on this headless system anyway?"; then
        info "User aborted installation on headless system. Exiting."
        exit 0
      fi
    fi

    stop_brave_processes
    elevate_privileges

    info "Removing previous installation and user data..."
    local bookmarks_backup=""
    if [[ "$KEEP_BOOKMARKS" == "true" ]] && [[ -f "$USER_HOME/.config/BraveSoftware/Brave-Browser/Default/Bookmarks" ]]; then
        local backup_file="/tmp/brave-bookmarks-$(date +%s).json"
        cp "$USER_HOME/.config/BraveSoftware/Brave-Browser/Default/Bookmarks" "$backup_file"
        bookmarks_backup="$backup_file"
        info "Bookmarks backed up."
    fi
    rm -rf "$USER_HOME/.config/BraveSoftware" "$USER_HOME/.cache/BraveSoftware"
    sudo apt-get purge -y "$BRAVE_PACKAGE" &>/dev/null || true
    success "Previous data cleared."

    info "Installing Brave Browser package..."
    sudo apt-get install -y curl gnupg
    sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
    curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-core.asc | sudo gpg --dearmor -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y "$BRAVE_PACKAGE"
    success "Brave Browser installed successfully."

    # Create a dummy profile to apply settings to by briefly running Brave
    info "Applying post-install configurations..."
    brave-browser --headless --remote-debugging-port=9222 &>/dev/null &
    local brave_pid=$!
    sleep 2
    kill -s SIGTERM $brave_pid &>/dev/null || true

    local prefs_file="$USER_HOME/.config/BraveSoftware/Brave-Browser/Default/Preferences"
    if [[ ! -f "$prefs_file" ]]; then
        warn "Could not find Preferences file. Skipping advanced configuration."
    else
        # Configure Filters and Vertical Tabs using jq
        if [[ "$WITH_FILTERS" == "true" || "$VERTICAL_TABS" == "true" ]]; then
          if ! command -v jq &>/dev/null; then
              warn "'jq' command not found, which is required for advanced configuration."
              if prompt "Install 'jq' now?"; then sudo apt-get install -y jq; else
                  warn "Skipping filters/tabs configuration."
                  WITH_FILTERS=false
                  VERTICAL_TABS=false
              fi
          fi

          local jq_script=""
          if [[ "$WITH_FILTERS" == "true" ]]; then
              info "Adding custom ad-block filter lists..."
              local filter_lists_json
              filter_lists_json=$(printf '%s\n' \
                "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/YouTubeSubannoyancesList.txt" \
                "https://www.i-dont-care-about-cookies.eu/abp/" | jq -R . | jq -s .)
              jq_script+=".brave.shields.filter_lists.custom = (.brave.shields.filter_lists.custom // []) + ${filter_lists_json}"
          fi
          if [[ "$VERTICAL_TABS" == "true" ]]; then
              info "Enabling vertical tabs..."
              # Chain the commands with a pipe
              [[ -n "$jq_script" ]] && jq_script+=" | "
              jq_script+=".brave.tabs.vertical_tabs_enabled = true"
          fi

          # Apply the combined jq modifications
          if [[ -n "$jq_script" ]]; then
            jq "$jq_script" "$prefs_file" > "${prefs_file}.tmp" && mv "${prefs_file}.tmp" "$prefs_file"
            success "Advanced configuration applied."
          fi
        fi
    fi

    # Restore bookmarks last, after all file modifications
    if [[ -n "$bookmarks_backup" ]]; then
        info "Restoring bookmarks..."
        local bookmarks_dir="$USER_HOME/.config/BraveSoftware/Brave-Browser/Default"
        cp "$bookmarks_backup" "$bookmarks_dir/Bookmarks"
        rm -f "$bookmarks_backup"
        success "Bookmarks restored."
    fi

    # Launch browser with extension URLs if requested
    if [[ "$INSTALL_HELPERS" == "true" ]] && [[ "$HAS_GUI" == "true" ]]; then
        info "Opening browser tabs for one-click extension installation..."
        brave-browser \
          "https://chrome.google.com/webstore/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm" \
          "https://chrome.google.com/webstore/detail/privacy-badger/pkehgijcmpdhfbdbbnkijodmdjhbjlgp" \
          "https://chrome.google.com/webstore/detail/enhancer-for-youtube/ponfpcnoihfmfllpaingbgckeeldkhle" \
          "https://chrome.google.com/webstore/detail/i-dont-care-about-cookies/fihnjjcciajhdojfnbdddfaoknhalnja" \
          &> /dev/null &
    fi
}

# --- Main Logic ---
main() {
    # Parse args first, so -h can exit cleanly without triggering any other output.
    parse_arguments "$@"

    # Set the trap now that we know we are proceeding with the main script logic.
    trap cleanup EXIT

    info "Starting Brave Browser Reset & Installer v$SCRIPT_VERSION"
    detect_environment

    if [[ "$PURGE_ONLY" == "true" ]]; then
        purge_system
    # If no flags are passed, run interactively with a default "No" prompt.
    elif [[ "$FORCE_REINSTALL" == "false" && "$ASSUME_YES" == "false" ]]; then
        info "This script will completely remove the current Brave installation and user data, then reinstall the latest version."
        warn "All settings, history, and wallets (if not backed up) will be lost."
        if prompt "Are you sure you want to proceed?"; then
            reinstall_system
        else
            info "User aborted. No changes have been made."
            exit 0
        fi
    else # This case handles -f or -y flags for automated runs.
        reinstall_system
    fi

    info "To run the browser, use the command: brave-browser"
    echo -e "\n${C_GREEN}✓ Script completed.${C_RESET}"
}

# --- Script Entry Point ---
main "$@"
