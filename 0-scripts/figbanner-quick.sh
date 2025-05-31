#!/bin/bash
# Author: Roy Wiseman 2025-04
#
# Script: login-banner.sh
# Description: Displays a customized login banner with system information, date/time,
#              and an optional figlet art of the hostname.
#              It checks if necessary tools (like figlet) are installed and offers
#              to install them on demand using the system's package manager.
#              The banner is skipped if the shell is already running inside a
#              tmux or byobu session (checking TMUX and BYOBU environment variables).
#
# Dependencies:
#   - Standard shell builtins (printf, date, type, read)
#   - Basic system commands (hostname, uname, uptime)
#   - Optional: figlet (installed on demand for the figlet hostname art)
#   - Optional: lsb_release command (or relies on /etc/os-release) for OS info
#   - Package managers for installation: apt, dnf, yum, zypper, apk (requires sudo)
#
# Usage:
#   Typically, this script is sourced in your shell startup file (~/.bashrc or ~/.profile).
#   Example: source /path/to/login-banner.sh
#   Make sure it's executable if calling directly: chmod +x /path/to/login-banner.sh
#

# --- Configuration ---
# Basic colors for the banner using ANSI escape codes
BOLD_GREEN='\033[1;32m'
NC='\033[0m' # No Color / Reset terminal attributes

# --- Helper Functions ---

# Get OS name and version information
# Tries lsb_release first, then /etc/os-release, falls back to 'Unknown OS'
ver() {
    if type lsb_release >/dev/null 2>&1; then
        lsb_release -ds
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        # Use PRETTY_NAME if available, otherwise combine ID and VERSION_ID, or fall back to ID
        echo "${PRETTY_NAME:-${ID}${VERSION_ID:+ ${VERSION_ID}}}"
    else
        echo "Unknown OS"
    fi
}

# Get system information including hostname, kernel, and uptime
sys() {
    local kernel=$(uname -sr)
    # Use 'uptime -p' for human-readable uptime if available (GNU coreutils),
    # otherwise parse the standard 'uptime' output.
    local up=$(uptime -p 2>/dev/null || uptime | sed -E 's/.*up +([^,]+).*/Up \1/')
    echo "Host: $(hostname) | Kernel: $kernel | $up"
}

# Display the hostname using the 'figlet' command
# Requires 'figlet' to be installed.
fignow() {
    if type figlet >/dev/null 2>&1; then
        figlet "$(hostname)"
    fi
}

# --- Tool Installation Logic ---

# Detect the system's package manager and define the install command
manager=""
pkg_figlet=""

if type apt-get >/dev/null 2>&1; then manager="sudo apt-get update && sudo apt-get install -y"; pkg_figlet="figlet";
elif type dnf >/dev/null 2>&1; then manager="sudo dnf install -y"; pkg_figlet="figlet";
elif type yum >/dev/null 2>/dev/null; then manager="sudo yum install -y"; pkg_figlet="figlet"; # Check both yum and dnf as dnf might exist but yum is preferred on some systems
elif type zypper >/dev/null 2>&1; then manager="sudo zypper install -y"; pkg_figlet="figlet";
elif type apk >/dev/null 2>&1; then manager="sudo apk add"; pkg_figlet="figlet"; # figlet package name might vary slightly on Alpine
fi

# Check for and offer to install missing required tools
install_missing_tools() {
    local missing_pkgs=()
    local missing_cmds=()

    # Check for figlet command
    if ! type figlet >/dev/null 2>&1; then
        if [ -n "$pkg_figlet" ]; then
           missing_pkgs+=("$pkg_figlet")
           missing_cmds+=("figlet")
        else
           echo "Warning: 'figlet' command not found and package name for your distro is unknown. Figlet banner will be skipped." >&2
           return 0 # Not a critical failure
        fi
    fi

    # Add checks for other commands if necessary (e.g., uptime, uname, hostname are standard)
    # if ! type some_command >/dev/null 2>&1; then missing_pkgs+=("some_package"); missing_cmds+=("some_command"); fi

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        if [ -z "$manager" ]; then
            echo "Error: No supported package manager found (apt, dnf, yum, zypper, apk)." >&2
            echo "Cannot automatically install missing tools: ${missing_cmds[*]}." >&2
            return 1 # Indicate failure
        fi

        echo "Missing tools required for full banner functionality:"
        printf "  Commands: %s\n" "${missing_cmds[*]}"
        printf "  Packages: %s\n" "${missing_pkgs[*]}"

        # Use /dev/tty to ensure read works even if script output is piped/redirected
        read -r -p "Attempt to install these using '$manager'? (y/N) " response < /dev/tty
        case "$response" in
            [yY][eE][sS]|[yY])
                echo "Attempting installation..."
                # Use eval to correctly handle managers with multiple commands (like apt-get update && ...)
                if eval "$manager ${missing_pkgs[*]}"; then
                    echo "Installation successful."
                    # Optional: Re-check if commands are available after install
                    # for cmd in "${missing_cmds[@]}"; do type "$cmd" >/dev/null 2>&1 || echo "Warning: $cmd still not found."; done
                else
                    echo "Error during installation. Some banner features may not work." >&2
                    return 1 # Indicate installation failure
                fi
                ;;
            *)
                echo "Skipping installation. Some banner features may not work." >&2
                return 1 # Indicate skipped installation
                ;;
        esac
    fi
    return 0 # Indicate success (either tools were found, installed, or skipped non-critically)
}


# --- Main Banner Function ---

# Display the formatted login banner
login_banner() {
    # Print initial newline and apply color to the entire block
    printf "${NC}\n${BOLD_GREEN}"

    # Print OS and Date/Time line
    printf "%s : %s\n" "$(ver)" "$(date +"%Y-%m-%d, %H:%M:%S, %A, Week %V")"

    # Print System Info line
    printf "%s\n" "$(sys)"

    # Print Figlet Banner if figlet is available
    if type figlet >/dev/null 2>&1; then
        fignow
    fi

    # Reset color and add final newlines
    printf "${NC}\n\n"
}

# --- Execution Logic ---

# Only display the banner if NOT in a tmux or byobu session
# Check for standard environment variables set by tmux and byobu
if [ -z "$TMUX" ] && [ -z "$BYOBU" ]; then
    # Attempt to install necessary tools, and if successful (or if no tools were missing),
    # proceed to display the login banner.
    install_missing_tools && login_banner
fi

# Optional: Example of how you might integrate auto-starting tmux/byobu
# This part is commented out by default. Uncomment and customize if desired.
# if [ -z "$TMUX" ] && [ -z "$BYOBU" ]; then
#     echo "Starting terminal multiplexer..."
#     # Choose one:
#     # exec tmux new-session -A -s main # Start/attach to a tmux session named 'main'
#     # exec byobu # Start byobu
# fi
