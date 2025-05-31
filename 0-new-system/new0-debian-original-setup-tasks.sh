#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script to re-configure Linux system identity and setup settings
# Run with sudo: sudo ./reconfigure_linux_enhanced.sh

# --- Function to check if a package is installed (Debian-based) ---
is_pkg_installed() {
    dpkg -s "$1" &> /dev/null
    return $?
}

# --- Function to offer installation of a package (Debian-based) ---
offer_install_pkg() {
    local pkg_name="$1"
    local pkg_purpose="$2"
    if ! is_pkg_installed "$pkg_name"; then
        read -r -p "$pkg_name is not installed. It's needed for $pkg_purpose. Install $pkg_name now? (y/N): " install_pkg
        if [[ "$install_pkg" =~ ^[Yy]$ ]]; then
            echo "Installing $pkg_name..."
            apt update && apt install -y "$pkg_name"
            if ! is_pkg_installed "$pkg_name"; then
                echo "Failed to install $pkg_name. Please install it manually and re-run this option if desired."
                return 1
            fi
        else
            echo "$pkg_name not installed. Skipping this step."
            return 1
        fi
    fi
    return 0
}


echo "Linux System Re-configuration Tool (Enhanced)"
echo "============================================="
echo "This script will help you update key system settings by running through"
echo "the choices made during the original Linux setup."
echo "IMPORTANT: Run this script with sudo privileges."
echo ""

# --- Check for sudo ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# --- Get Current Distribution (Basic Detection) ---
DISTRO=""
FULL_DISTRO_NAME="" # For display
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    FULL_DISTRO_NAME=$PRETTY_NAME
elif type lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    FULL_DISTRO_NAME=$(lsb_release -sd)
else
    echo "Cannot reliably determine Linux distribution."
    # Add fallbacks or exit if necessary
fi

echo "Detected Distribution: $FULL_DISTRO_NAME (ID: $DISTRO)"
echo ""

# --- Summary of Operations ---
echo "This script can help you configure the following:"
echo "  1. DNS Domain Name (for network identification)"
echo "  2. Package Repository Mirrors (for software updates)"
if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
echo "  3. Debian Popularity Contest (popcon) participation"
fi
echo "  4. System Hostname (computer's network name)"
echo "  5. System Timezone"
if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
echo "  6. Debian Tasksel (for installing package groups like desktop environments)"
fi
echo ""
read -r -p "Press Enter to proceed with the configuration steps, or Ctrl+C to exit."

# --- 1. Configure DNS Domain Name ---
echo ""
echo "--- 1. DNS Domain Name ---"
read -r -p "Enter your new DNS domain name (e.g., mycompany.local, leave blank to skip): " dns_domain

if [[ -n "$dns_domain" ]]; then
    echo "Attempting to set search domain in /etc/resolv.conf (may be overwritten by NetworkManager/systemd-resolved)"
    if grep -q "^search " /etc/resolv.conf; then
        sed -i "/^search /c\search $dns_domain" /etc/resolv.conf
    elif grep -q "^domain " /etc/resolv.conf; then
        sed -i "/^domain /c\domain $dns_domain" /etc/resolv.conf
    else
        echo "search $dns_domain" >> /etc/resolv.conf
    fi
    echo "Search domain set to '$dns_domain' in /etc/resolv.conf."
    echo "NOTE: If you use NetworkManager or systemd-resolved, this change might be temporary."
    echo "You may need to configure it via NetworkManager settings (nm-connection-editor) or in /etc/systemd/resolved.conf (and restart systemd-resolved)."
    echo "For systemd-resolved: Consider adding 'Domains=$dns_domain' to /etc/systemd/resolved.conf and restarting with 'sudo systemctl restart systemd-resolved'."
else
    echo "Skipping DNS domain name configuration."
fi

# --- 2. Pick a Country and Repository ---
echo ""
echo "--- 2. Repository Configuration ---"
echo "This section helps update your package manager's repository sources."
echo "NOTE: This is highly distribution-specific."

case "$DISTRO" in
    debian|ubuntu|linuxmint|pop)
        echo "Detected Debian-based system."
        current_mirror=$(grep -Eom1 "deb\s+http://[^ ]+" /etc/apt/sources.list | head -n1 | cut -d' ' -f2)
        echo "Current primary mirror (from sources.list, if any): $current_mirror"
        read -r -p "Do you want to manually edit /etc/apt/sources.list? (y/N): " edit_sources
        if [[ "$edit_sources" =~ ^[Yy]$ ]]; then
            echo "Please make your changes to /etc/apt/sources.list."
            echo "You can use a tool like 'apt-select' or find mirrors at:"
            echo "  - Debian: https://www.debian.org/mirror/list"
            echo "  - Ubuntu: https://launchpad.net/ubuntu/+archivemirrors"
            read -r -p "Press Enter to open /etc/apt/sources.list with nano (Ctrl+X to save and exit)..."
            nano /etc/apt/sources.list
            echo "After saving, running 'sudo apt update' is strongly recommended."
        else
            echo "Skipping manual repository edit. You might want to use:"
            echo "  - 'software-properties-gtk' (GUI tool on desktops)"
            echo "  - Or manually edit /etc/apt/sources.list and files in /etc/apt/sources.list.d/"
            echo "  - For Ubuntu, you can often select 'Download from: Other...' in 'Software & Updates'."
        fi
        ;;
    fedora|rhel|centos|almalinux|rocky)
        echo "Detected Fedora/RHEL-based system."
        echo "Repository configuration is typically managed in /etc/yum.repos.d/"
        echo "You might need to:"
        echo "  1. Disable old base/appstream mirrorlist or metalink lines in .repo files."
        echo "  2. Add new baseurl lines pointing to a specific country mirror."
        echo "Example: For Fedora, find mirrors at https://admin.fedoraproject.org/mirrormanager/"
        read -r -p "Do you want to list files in /etc/yum.repos.d/ to manually edit them? (y/N): " list_repos
        if [[ "$list_repos" =~ ^[Yy]$ ]]; then
            ls -la /etc/yum.repos.d/
            echo "Identify the relevant .repo files (e.g., fedora.repo, centos-base.repo) and edit them."
            echo "You'll typically comment out 'mirrorlist=' lines and uncomment/add 'baseurl=' lines."
            echo "After changes, run 'sudo dnf clean all && sudo dnf makecache' or 'sudo yum clean all && sudo yum makecache'."
        else
            echo "Skipping manual repository edit."
        fi
        ;;
    arch|manjaro)
        echo "Detected Arch-based system."
        echo "Repositories are configured in /etc/pacman.d/mirrorlist."
        echo "You can use the 'reflector' utility to automatically find and rank the fastest mirrors for your country."
        read -r -p "Do you want to edit /etc/pacman.d/mirrorlist manually? (y/N): " edit_mirrorlist
        if [[ "$edit_mirrorlist" =~ ^[Yy]$ ]]; then
            echo "Consider backing up your current mirrorlist first: sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak"
            echo "You can uncomment servers from your desired country."
            read -r -p "Press Enter to open /etc/pacman.d/mirrorlist with nano..."
            nano /etc/pacman.d/mirrorlist
            echo "After saving, run 'sudo pacman -Syyu' to refresh package lists and upgrade."
        else
            echo "Skipping manual mirrorlist edit. Consider using 'reflector', e.g.:"
            echo "  sudo reflector --country 'YourCountry' --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
            echo "Replace 'YourCountry' with the actual country name (e.g., 'Netherlands', 'Germany')."
        fi
        ;;
    *)
        echo "Repository configuration for '$DISTRO' is not specifically handled by this script."
        echo "Please consult your distribution's documentation for changing repository mirrors."
        ;;
esac

# --- 3. Debian Popularity Contest (popcon) ---
if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
    echo ""
    echo "--- 3. Debian Popularity Contest (popcon) ---"
    read -r -p "Do you want to configure participation in the Debian Popularity Contest? (y/N): " config_popcon
    if [[ "$config_popcon" =~ ^[Yy]$ ]]; then
        if offer_install_pkg "popularity-contest" "configuring popcon"; then
            echo "Running popularity-contest configuration..."
            dpkg-reconfigure popularity-contest
            echo "Popularity Contest configuration finished."
        fi
    else
        echo "Skipping Popularity Contest configuration."
    fi
fi

# --- 4. Hostname ---
echo ""
echo "--- 4. Hostname ---"
current_hostname=$(hostname)
echo "Current hostname: $current_hostname"
read -r -p "Enter new hostname (leave blank to keep '$current_hostname'): " new_hostname

if [[ -n "$new_hostname" && "$new_hostname" != "$current_hostname" ]]; then
    if command -v hostnamectl > /dev/null; then
        hostnamectl set-hostname "$new_hostname"
        echo "Hostname set to '$new_hostname' using hostnamectl."
    else
        # Fallback for older systems
        echo "$new_hostname" > /etc/hostname
        hostname "$new_hostname" # Set for current session
        echo "Hostname set to '$new_hostname' in /etc/hostname. A reboot might be needed for all services to pick it up."
    fi

    echo "Updating /etc/hosts..."
    # Be careful with sed patterns to avoid matching too much
    # This assumes the old hostname is associated with 127.0.1.1, a common Debian/Ubuntu practice
    if grep -q "127\.0\.1\.1\s*$current_hostname" /etc/hosts; then
        sed -i "s/127\.0\.1\.1\s*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    elif ! grep -q "127\.0\.1\.1\s*$new_hostname" /etc/hosts; then # Add if not present and old wasn't specifically 127.0.1.1
        # Check if 127.0.1.1 entry exists with ANY hostname
        if grep -q "^127\.0\.1\.1\s" /etc/hosts; then
             sed -i "/^127\.0\.1\.1\s.*/c\127.0.1.1\t$new_hostname" /etc/hosts
        else
             echo "127.0.1.1       $new_hostname" >> /etc/hosts
        fi
    fi
    # Also ensure localhost is present
    if ! grep -q "127\.0\.0\.1\s*localhost" /etc/hosts; then
        echo "127.0.0.1       localhost" >> /etc/hosts
    fi
    echo "/etc/hosts updated."
else
    echo "Hostname unchanged."
fi

# --- 5. Timezone ---
echo ""
echo "--- 5. Timezone ---"
current_timezone=""
if command -v timedatectl > /dev/null; then
    current_timezone=$(timedatectl status | grep "Time zone" | awk '{print $3}')
else
    # Basic attempt to read /etc/timezone if timedatectl not present
    if [ -f /etc/timezone ]; then
        current_timezone=$(cat /etc/timezone)
    elif [ -L /etc/localtime ]; then
        current_timezone=$(readlink /etc/localtime | sed "s|/usr/share/zoneinfo/||")
    fi
fi
echo "Current timezone: $current_timezone (or best guess)"
read -r -p "Do you want to change the timezone? (y/N): " change_timezone

if [[ "$change_timezone" =~ ^[Yy]$ ]]; then
    if command -v timedatectl > /dev/null; then
        echo "Available timezones can be listed with 'timedatectl list-timezones'."
        echo "You can use 'timedatectl list-timezones | grep YourCityOrRegion' to find yours."
        read -r -p "Enter new timezone (e.g., America/New_York, Europe/Amsterdam): " new_timezone
        if [[ -n "$new_timezone" ]]; then
            timedatectl set-timezone "$new_timezone"
            echo "Timezone set to $new_timezone."
        else
            echo "No timezone entered, skipping."
        fi
    else
        echo "timedatectl command not found. Please change timezone manually."
        echo "This usually involves:"
        echo "  1. Listing available timezones in /usr/share/zoneinfo/"
        echo "  2. Creating/updating /etc/timezone with the chosen path (e.g., Europe/Amsterdam)"
        echo "  3. Symlinking /etc/localtime: sudo ln -sf /usr/share/zoneinfo/Your/Zone /etc/localtime"
        echo "  4. On some older systems, dpkg-reconfigure tzdata: sudo dpkg-reconfigure tzdata"
    fi
else
    echo "Timezone unchanged."
fi


# --- 6. Debian Tasksel (Package Groups) ---
if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
    echo ""
    echo "--- 6. Debian Tasksel (Package Groups) ---"
    echo "Tasksel allows you to easily install coordinated sets of packages (tasks) like a Desktop Environment (GNOME, KDE, XFCE) or Web Server."
    read -r -p "Do you want to run tasksel to add or remove package groups? (y/N): " run_tasksel
    if [[ "$run_tasksel" =~ ^[Yy]$ ]]; then
        if offer_install_pkg "tasksel" "managing package groups"; then
            echo "Launching tasksel... Follow the on-screen instructions."
            tasksel
            echo "Tasksel finished."
        fi
    else
        echo "Skipping tasksel."
    fi
fi


echo ""
echo "============================================="
echo "Re-configuration process finished."
echo "Important Reminders:"
echo "  - You may need to REBOOT for all changes (especially hostname and some network settings) to take full effect."
echo "  - If you changed repositories, update your package lists:"
if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" || "$DISTRO" == "pop" ]]; then
echo "    sudo apt update"
elif [[ "$DISTRO" == "fedora" || "$DISTRO" == "rhel" || "$DISTRO" == "centos" || "$DISTRO" == "almalinux" || "$DISTRO" == "rocky" ]]; then
echo "    sudo dnf clean all && sudo dnf makecache  (or yum for older systems)"
elif [[ "$DISTRO" == "arch" || "$DISTRO" == "manjaro" ]]; then
echo "    sudo pacman -Syyu"
fi
echo "  - For DNS domain changes to be effective system-wide, ensure your network interface configurations (e.g., in NetworkManager) are also updated if they override /etc/resolv.conf."
