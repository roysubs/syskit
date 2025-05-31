#!/bin/bash
# Author: Roy Wiseman 2025-03

# --- Script Information ---
# Name: show_repos.sh
# Description: Identifies the Linux distribution, displays repository configurations,
#              and provides commands and guidance for repository management and diagnostics.
# Author: AI Assistant (Conceptual Script)
# Version: 1.1
# Disclaimer: This script provides information and suggests commands.
#             Execute modification commands with caution and ensure you understand them.
#             Always back up critical configuration files if unsure.

# --- Helper Functions ---

# Function to print a colored message
# Usage: print_msg COLOR "Message"
# Colors: header (bold blue), success (green), warning (yellow), error (red), info (cyan), cmd (light_purple)
print_msg() {
    local color_name="$1"
    local message="$2"
    local color_code=""

    case "$color_name" in
        header) color_code="\033[1;34m" ;; # Bold Blue
        success) color_code="\033[0;32m" ;; # Green
        warning) color_code="\033[0;33m" ;; # Yellow
        error) color_code="\033[0;31m" ;;   # Red
        info) color_code="\033[0;36m" ;;    # Cyan
        cmd) color_code="\033[0;35m" ;;     # Light Purple
        bold) color_code="\033[1m" ;;       # Bold
        *) color_code="\033[0m" ;;          # Default (reset)
    esac
    echo -e "${color_code}${message}\033[0m"
}

# Function to detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif type lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO=$(echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/fedora-release ]; then
        DISTRO="fedora"
    elif [ -f /etc/redhat-release ]; then
        if grep -qi "CentOS" /etc/redhat-release; then
            DISTRO="centos"
        elif grep -qi "Rocky" /etc/redhat-release; then
            DISTRO="rocky"
        elif grep -qi "AlmaLinux" /etc/redhat-release; then
            DISTRO="almalinux"
        else
            DISTRO="rhel" # Generic RHEL or other derivatives
        fi
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        # /etc/SUSE-brand is used on SLES and openSUSE Leap 15+
        if grep -qi "openSUSE" /etc/SUSE-brand /etc/SuSE-release 2>/dev/null; then
            DISTRO="opensuse"
        else
            DISTRO="sles"
        fi
    else
        DISTRO="unknown"
    fi
    echo "$DISTRO"
}

# Function to ask for user confirmation before running a command
ask_to_run() {
    local command_to_run="$1"
    local purpose="$2"
    read -r -p "$(print_msg info "Do you want to run '") $(print_msg cmd "$command_to_run") $(print_msg info "' to $purpose? (y/N): ")" choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        print_msg info "Running: $command_to_run"
        eval "$command_to_run" # Use eval with caution, ensure command_to_run is safe.
                               # Here it's safe as we construct it internally.
        print_msg success "Command finished."
    else
        print_msg warning "Skipped."
    fi
    echo ""
}

# --- Main Logic ---

print_msg "header" "===== Repository Information and Management Tool ====="
echo ""

CURRENT_DISTRO=$(detect_distro)
print_msg "info" "Detected Distribution: $(print_msg bold "$CURRENT_DISTRO")"
echo "-----------------------------------------------------"

if [[ "$EUID" -ne 0 ]]; then
  print_msg "warning" "This script is running without root privileges (sudo)."
  print_msg "warning" "Some diagnostic commands that require sudo will be shown but not run automatically."
  print_msg "warning" "You will be prompted if you choose to run commands requiring sudo."
  echo ""
fi


case "$CURRENT_DISTRO" in
    debian|ubuntu|mint|pop|elementary|raspbian)
        print_msg "header" "--- APT Repositories (Debian/Ubuntu-based) ---"
        APT_SOURCES_MAIN="/etc/apt/sources.list"
        APT_SOURCES_DIR="/etc/apt/sources.list.d"

        print_msg "info" "APT repositories are defined in:"
        print_msg "cmd" "  1. Main file: $APT_SOURCES_MAIN"
        print_msg "cmd" "  2. Additional files in directory: $APT_SOURCES_DIR/*.list"
        echo ""

        print_msg "info" "Contents of $(print_msg bold "$APT_SOURCES_MAIN") (excluding comments and empty lines):"
        if [ -f "$APT_SOURCES_MAIN" ]; then
            grep -vE '^\s*#|^\s*$' "$APT_SOURCES_MAIN" || print_msg "warning" "  (No active entries or file is empty)"
        else
            print_msg "warning" "  $APT_SOURCES_MAIN not found."
        fi
        echo ""

        print_msg "info" "Contents of files in $(print_msg bold "$APT_SOURCES_DIR") (excluding comments and empty lines):"
        if [ -d "$APT_SOURCES_DIR" ] && [ "$(ls -A "$APT_SOURCES_DIR"/*.list 2>/dev/null)" ]; then
            for repo_file in "$APT_SOURCES_DIR"/*.list; do
                if [ -f "$repo_file" ]; then
                    print_msg "info" "  --- File: $(print_msg bold "$repo_file") ---"
                    grep -vE '^\s*#|^\s*$' "$repo_file" || print_msg "warning" "    (No active entries or file is empty)"
                    echo ""
                fi
            done
        else
            print_msg "warning" "  No .list files found in $APT_SOURCES_DIR or directory doesn't exist."
        fi
        echo ""

        print_msg "header" "--- APT Health Check & Updates ---"
        print_msg "info" "To check repository health and update package lists, APT uses the command:"
        print_msg "cmd" "  sudo apt update"
        print_msg "info" "This command will:"
        print_msg "info" "  - Download package information from all configured sources."
        print_msg "info" "  - Report errors if a repository is unavailable, misconfigured, or has GPG key issues."
        print_msg "info" "  - Tell you if any packages can be upgraded."
        print_msg "info" "Look for lines starting with 'Err:' (Error), 'W:' (Warning), 'Hit:' (Already up-to-date), or 'Get:' (Fetching new data)."
        ask_to_run "sudo apt update" "refresh package lists and check repository health"

        print_msg "header" "--- APT Repository Management Tips ---"
        print_msg "info" "$(print_msg bold "To List PPAs (Personal Package Archives) often added with 'add-apt-repository':")"
        print_msg "cmd" "  grep -RoPish '(?<=^deb http://ppa.launchpad.net/)[^/]+/[^/ ]+' /etc/apt/sources.list* | sort -u"
        echo ""
        print_msg "info" "$(print_msg bold "To Add a Repository (e.g., a PPA):")"
        print_msg "cmd" "  sudo add-apt-repository ppa:user/ppa-name"
        print_msg "cmd" "  sudo apt update"
        print_msg "warning" "  Always ensure you trust the source of a PPA before adding it."
        echo ""
        print_msg "info" "$(print_msg bold "To Disable a Repository:")"
        print_msg "info" "  1. Identify the .list file (in $APT_SOURCES_MAIN or $APT_SOURCES_DIR) containing the repo."
        print_msg "info" "  2. Edit the file (e.g., $(print_msg cmd "sudo nano $APT_SOURCES_DIR/some-repo.list"))."
        print_msg "info" "  3. Comment out the line(s) for that repository by adding a '#' at the beginning."
        print_msg "info" "  4. Then run $(print_msg cmd "sudo apt update")."
        echo ""
        print_msg "info" "$(print_msg bold "To Remove a PPA (if added with 'add-apt-repository'):")"
        print_msg "cmd" "  sudo add-apt-repository --remove ppa:user/ppa-name"
        print_msg "cmd" "  sudo apt update"
        echo ""
        print_msg "info" "$(print_msg bold "To Remove a Repository Manually (Use with extreme caution!):")"
        print_msg "info" "  1. Delete the specific .list file from $APT_SOURCES_DIR or remove/comment lines from $APT_SOURCES_MAIN."
        print_msg "cmd" "     Example: sudo rm $APT_SOURCES_DIR/unwanted-repo.list"
        print_msg "info" "  2. Then run $(print_msg cmd "sudo apt update")."
        echo ""
        print_msg "info" "$(print_msg bold "Troubleshooting Common APT Issues:")"
        print_msg "info" "  - $(print_msg bold "GPG Key Errors ('NO_PUBKEY'):") Often solved by importing the missing key. Search for the key ID online for instructions, usually involving 'apt-key adv' or downloading a .gpg file."
        print_msg "info" "  - $(print_msg bold "Repository Not Found (404 errors):") The repository URL might be wrong, or the repo no longer exists or doesn't support your distribution version."
        print_msg "info" "  - $(print_msg bold "Hash Sum Mismatch:") Indicates data corruption during download. Try running $(print_msg cmd "sudo apt clean && sudo apt update") again."
        ;;

    fedora|rhel|centos|rocky|almalinux)
        PKG_MANAGER="dnf"
        command -v dnf >/dev/null || PKG_MANAGER="yum"

        print_msg "header" "--- $PKG_MANAGER Repositories (Fedora/RHEL-based) ---"
        REPO_DIR="/etc/yum.repos.d"
        print_msg "info" "$PKG_MANAGER repositories are primarily defined in .repo files within the directory:"
        print_msg "cmd" "  $REPO_DIR"
        echo ""
        print_msg "info" "Listing .repo files in $(print_msg bold "$REPO_DIR"):"
        if [ -d "$REPO_DIR" ]; then
            ls -1 "$REPO_DIR"/*.repo 2>/dev/null || print_msg "warning" "  No .repo files found."
        else
            print_msg "error" "  $REPO_DIR directory not found."
        fi
        echo ""

        print_msg "info" "To list all $(print_msg bold "enabled") repositories and their status:"
        print_msg "cmd" "  sudo $PKG_MANAGER repolist enabled"
        ask_to_run "sudo $PKG_MANAGER repolist enabled" "list enabled repositories"

        print_msg "info" "To list $(print_msg bold "all") configured repositories (enabled and disabled):"
        print_msg "cmd" "  sudo $PKG_MANAGER repolist all"
        # ask_to_run "sudo $PKG_MANAGER repolist all" "list all repositories" # Can be verbose
        echo ""

        print_msg "header" "--- $PKG_MANAGER Health Check & Cache Refresh ---"
        print_msg "info" "To check repository health and refresh the local metadata cache, $PKG_MANAGER uses commands like:"
        print_msg "cmd" "  sudo $PKG_MANAGER check-update"
        print_msg "info" "  (Checks for available package updates, implicitly refreshing metadata if needed)"
        print_msg "cmd" "  sudo $PKG_MANAGER makecache"
        print_msg "info" "  (Forces a refresh of the metadata from all enabled repositories)"
        print_msg "info" "These commands will connect to repository servers and download metadata. Errors usually indicate connectivity issues, misconfigured URLs, or GPG key problems."
        ask_to_run "sudo $PKG_MANAGER makecache" "refresh metadata cache and check repository health"

        print_msg "header" "--- $PKG_MANAGER Repository Management Tips ---"
        print_msg "info" "$(print_msg bold "To View Details of a Specific Repository (e.g., its URLs):")"
        print_msg "info" "  First, get the repo ID from '$(print_msg cmd "$PKG_MANAGER repolist")'."
        print_msg "cmd" "  sudo $PKG_MANAGER repoinfo <repo_id>"
        print_msg "cmd" "  Or look inside the corresponding .repo file in $REPO_DIR."
        echo ""
        print_msg "info" "$(print_msg bold "To Add a Repository:")"
        print_msg "info" "  1. $(print_msg bold "Using a .repo file:") Create a file (e.g., mycustom.repo) in $REPO_DIR with content like:"
        print_msg "cmd" "     [my-custom-repo]"
        print_msg "cmd" "     name=My Custom Repository"
        print_msg "cmd" "     baseurl=http://example.com/repo/\$releasever/\$basearch/"
        print_msg "cmd" "     gpgcheck=1"
        print_msg "cmd" "     gpgkey=http://example.com/repo/RPM-GPG-KEY-mycustom"
        print_msg "cmd" "     enabled=1"
        print_msg "info" "     (Replace with actual details. '\$releasever' and '\$basearch' are variables.)"
        print_msg "info" "  2. $(print_msg bold "Using config-manager (if dnf-plugins-core is installed):")"
        print_msg "cmd" "     sudo $PKG_MANAGER config-manager --add-repo http://example.com/repo.repo"
        print_msg "info" "  After adding, refresh the cache: $(print_msg cmd "sudo $PKG_MANAGER makecache")"
        echo ""
        print_msg "info" "$(print_msg bold "To Disable a Repository:")"
        print_msg "cmd" "  sudo $PKG_MANAGER config-manager --disable <repo_id>"
        print_msg "info" "  Or, edit the .repo file (e.g., $(print_msg cmd "sudo nano $REPO_DIR/problematic.repo")) and set $(print_msg cmd "enabled=0")."
        echo ""
        print_msg "info" "$(print_msg bold "To Enable a Repository:")"
        print_msg "cmd" "  sudo $PKG_MANAGER config-manager --enable <repo_id>"
        print_msg "info" "  Or, edit the .repo file and set $(print_msg cmd "enabled=1")."
        echo ""
        print_msg "info" "$(print_msg bold "To Remove a Repository (Use with caution!):")"
        print_msg "info" "  1. If added via $(print_msg cmd "config-manager --add-repo"), you might need to remove the .repo file it created."
        print_msg "info" "  2. Delete the .repo file from $REPO_DIR:"
        print_msg "cmd" "     sudo rm $REPO_DIR/unwanted-repo.repo"
        print_msg "info" "  3. Then run $(print_msg cmd "sudo $PKG_MANAGER clean all && sudo $PKG_MANAGER makecache")."
        echo ""
        print_msg "info" "$(print_msg bold "Troubleshooting Common $PKG_MANAGER Issues:")"
        print_msg "info" "  - $(print_msg bold "Errors during 'makecache' or 'check-update':") Check URLs in .repo files, network connectivity."
        print_msg "info" "  - $(print_msg bold "GPG Key Errors:") Ensure 'gpgcheck=1' and a correct 'gpgkey=' URL are in the .repo file. Keys are usually imported automatically or on first use. If issues persist, you might temporarily set 'gpgcheck=0' (NOT recommended for untrusted repos) or manually import the key with $(print_msg cmd "sudo rpm --import <key_url_or_file>")."
        print_msg "info" "  - $(print_msg bold "Failed to synchronize cache for repo '...'") Verify baseurl/metalink in the .repo file. Ensure your system's date/time are correct."
        ;;

    arch)
        print_msg "header" "--- Pacman Repositories (Arch Linux-based) ---"
        PACMAN_CONF="/etc/pacman.conf"
        MIRRORLIST="/etc/pacman.d/mirrorlist"

        print_msg "info" "Pacman repositories are defined in the main configuration file:"
        print_msg "cmd" "  $PACMAN_CONF"
        print_msg "info" "This file lists repositories (like core, extra, multilib) and includes mirror lists."
        echo ""

        print_msg "info" "Active repositories from $(print_msg bold "$PACMAN_CONF") (excluding comments, options, and blank lines):"
        if [ -f "$PACMAN_CONF" ]; then
            grep -vE '^\s*#|^\s*$|^\s*\[options\]' "$PACMAN_CONF" | grep -E '^\s*\[.+\]|^\s*Server\s*=|^\s*Include\s*='
        else
            print_msg "error" "  $PACMAN_CONF not found."
        fi
        echo ""
        print_msg "info" "The actual server URLs for official repositories are typically in:"
        print_msg "cmd" "  $MIRRORLIST"
        print_msg "info" "It's important that this file is up-to-date and mirrors are uncommented and ordered (optionally by speed)."
        echo ""

        print_msg "header" "--- Pacman Health Check & Database Sync ---"
        print_msg "info" "To check repository health and synchronize package databases, Pacman uses:"
        print_msg "cmd" "  sudo pacman -Sy"
        print_msg "info" "  (Synchronizes databases. Add 'y' again - $(print_msg cmd "sudo pacman -Syy") - to force download even if up-to-date.)"
        print_msg "cmd" "  sudo pacman -Syyu"
        print_msg "info" "  (Synchronizes databases and upgrades installed packages.)"
        print_msg "info" "During these operations, Pacman connects to mirrors. Errors indicate problems with mirrors, network, or $PACMAN_CONF."
        ask_to_run "sudo pacman -Syy" "synchronize package databases and check mirror health"

        print_msg "header" "--- Pacman Repository Management Tips ---"
        print_msg "info" "$(print_msg bold "To Manage Official Repositories (core, extra, multilib):")"
        print_msg "info" "  - Edit $(print_msg cmd "$PACMAN_CONF")."
        print_msg "info" "  - Uncomment or comment out repository sections (e.g., '[multilib]')."
        print_msg "info" "  - Do NOT remove [core], [extra] unless you know exactly what you are doing."
        echo ""
        print_msg "info" "$(print_msg bold "To Manage Mirrors ($MIRRORLIST):")"
        print_msg "info" "  - Edit $(print_msg cmd "sudo nano $MIRRORLIST")."
        print_msg "info" "  - Uncomment servers geographically close to you or known to be fast."
        print_msg "info" "  - Tools like $(print_msg cmd "reflector") can help automate updating this list:"
        print_msg "cmd" "    sudo reflector --country 'YourCountry' --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
        echo ""
        print_msg "info" "$(print_msg bold "To Add an Unofficial/Custom Repository (e.g., for AUR helpers or specific software):")"
        print_msg "info" "  - Edit $(print_msg cmd "sudo nano $PACMAN_CONF")."
        print_msg "info" "  - Add a new section at the end (usually):"
        print_msg "cmd" "    [custom-repo-name]"
        print_msg "cmd" "    SigLevel = Optional TrustAll  # Or specific SigLevel"
        print_msg "cmd" "    Server = http://example.com/archlinux/\$repo/\$arch"
        print_msg "warning" "    Ensure you trust the repository and understand its SigLevel implications."
        echo ""
        print_msg "info" "$(print_msg bold "To Remove/Disable a Custom Repository:")"
        print_msg "info" "  - Edit $(print_msg cmd "sudo nano $PACMAN_CONF")."
        print_msg "info" "  - Comment out or delete the section for that repository."
        print_msg "info" "  - Then run $(print_msg cmd "sudo pacman -Syy")."
        echo ""
        print_msg "info" "$(print_msg bold "Troubleshooting Common Pacman Issues:")"
        print_msg "info" "  - $(print_msg bold "'failed to synchronize databases' / 'error: failed retrieving file ...':")"
        print_msg "info" "    - Check network connection."
        print_msg "info" "    - Ensure your system clock is accurate (NTP recommended: $(print_msg cmd "sudo timedatectl set-ntp true"))."
        print_msg "info" "    - Update your mirror list (see above)."
        print_msg "info" "    - Run $(print_msg cmd "sudo pacman -Syyu") to force refresh and update."
        print_msg "info" "  - $(print_msg bold "Signature/Key Errors ('invalid or corrupted package (PGP signature)'):")"
        print_msg "info" "    - Ensure $(print_msg cmd "archlinux-keyring") package is up-to-date: $(print_msg cmd "sudo pacman -Sy archlinux-keyring && sudo pacman -Syyu")"
        print_msg "info" "    - If a custom repo key is bad, you may need to re-fetch/re-add it using $(print_msg cmd "pacman-key")."
        ;;

    opensuse|sles)
        print_msg "header" "--- Zypper Repositories (openSUSE/SLES) ---"
        print_msg "info" "Zypper repositories are managed using the 'zypper' command and configuration files typically in:"
        print_msg "cmd" "  /etc/zypp/repos.d/"
        echo ""

        print_msg "info" "To list all configured repositories with details (Alias, Name, Enabled, GPG Check, URI, Priority):"
        print_msg "cmd" "  sudo zypper lr -dPEu"
        ask_to_run "sudo zypper lr -dPEu" "list detailed repository information"

        print_msg "info" "A simpler list of enabled repositories:"
        print_msg "cmd" "  sudo zypper repos -E" # or zypper lr -E
        # ask_to_run "sudo zypper repos -E" "list enabled repositories"
        echo ""

        print_msg "header" "--- Zypper Health Check & Refresh ---"
        print_msg "info" "To check repository health and refresh metadata from all enabled repositories:"
        print_msg "cmd" "  sudo zypper refresh"
        print_msg "info" "To refresh a specific repository by its alias or number (from 'zypper lr'):"
        print_msg "cmd" "  sudo zypper refresh <alias_or_repo_#>"
        print_msg "info" "This command will connect to repository servers and download metadata. Errors indicate issues."
        ask_to_run "sudo zypper refresh" "refresh all repositories and check health"

        print_msg "header" "--- Zypper Repository Management Tips ---"
        print_msg "info" "$(print_msg bold "To Add a Repository:")"
        print_msg "cmd" "  sudo zypper addrepo --refresh <URI> <alias>"
        print_msg "cmd" "  Example: sudo zypper ar -f http://download.opensuse.org/oss/tumbleweed/ OssRepoAlias"
        print_msg "info" "  (Use 'ar' as a shortcut for 'addrepo'. '-f' or '--refresh' enables auto-refresh)"
        print_msg "info" "  You can also add .repo files to /etc/zypp/repos.d/ and then run $(print_msg cmd "sudo zypper refresh")."
        echo ""
        print_msg "info" "$(print_msg bold "To Disable a Repository:")"
        print_msg "cmd" "  sudo zypper modifyrepo --disable <alias_or_repo_#>"
        print_msg "info" "  (Use 'mr' as a shortcut for 'modifyrepo'. '-d' for disable)"
        echo ""
        print_msg "info" "$(print_msg bold "To Enable a Repository:")"
        print_msg "cmd" "  sudo zypper modifyrepo --enable <alias_or_repo_#>"
        print_msg "info" "  ('-e' for enable)"
        echo ""
        print_msg "info" "$(print_msg bold "To Remove a Repository (Use with caution!):")"
        print_msg "cmd" "  sudo zypper removerepo <alias_or_repo_#>"
        print_msg "info" "  (Use 'rr' as a shortcut for 'removerepo')"
        echo ""
        print_msg "info" "$(print_msg bold "To Modify Repository Properties (e.g., priority, refresh settings):")"
        print_msg "cmd" "  sudo zypper mr --priority 90 <alias_or_repo_#>"
        print_msg "cmd" "  sudo zypper mr --refresh <alias_or_repo_#>"
        print_msg "cmd" "  sudo zypper mr --no-gpgcheck <alias_or_repo_#>"
        print_msg "info" "  See $(print_msg cmd "zypper mr --help") for all options."
        echo ""
        print_msg "info" "$(print_msg bold "Troubleshooting Common Zypper Issues:")"
        print_msg "info" "  - $(print_msg bold "Refresh Errors ('Download failed: ...'):") Check URI in $(print_msg cmd "zypper lr -d"), network, and if the repo supports your openSUSE/SLES version."
        print_msg "info" "  - $(print_msg bold "Signature Verification Failed:") GPG key might be missing or incorrect. Repos added with 'zypper ar' often handle keys. If not, you might need to import it manually or adjust GPG check settings for that repo (e.g., $(print_msg cmd "sudo zypper mr --gpgcheck-strict <alias>") or temporarily with $(print_msg cmd "sudo zypper mr --no-gpgcheck <alias>") - use with caution)."
        print_msg "info" "  - $(print_msg bold "File conflicts between repositories:") Adjust repository priorities. Lower number means higher priority."
        print_msg "info" "  - Use YaST (Software Repositories module) for a GUI alternative to manage repos."
        ;;

    *)
        print_msg "error" "Unsupported distribution: $CURRENT_DISTRO"
        print_msg "warning" "This script currently supports Debian/Ubuntu-based, Fedora/RHEL-based, Arch-based, and openSUSE/SLES-based systems."
        print_msg "info" "If you know the commands for your system, you could try to adapt one of the existing sections."
        ;;
esac

echo "-----------------------------------------------------"
print_msg "header" "===== Script Finished ====="
print_msg "info" "Remember to run suggested modification commands with 'sudo' and understand their impact."
