#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04
# Cross-platform install of PowerShell 7 (pwsh).
#
# Detects the OS and installs via the best available method:
#   macOS                        -> Homebrew formula (brew install powershell)
#   Debian, Ubuntu, Linux Mint   -> Microsoft's apt repo (packages.microsoft.com)
#   RHEL, CentOS, Rocky, AlmaLinux -> Microsoft's dnf/yum repo
#   openSUSE, SLES, Fedora       -> Microsoft's documented binary tar.gz method
#                                    (these aren't in Microsoft's supported package-repo list)
#
# References:
#   https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux
#   https://learn.microsoft.com/powershell/scripting/install/alternate-install-methods

echo "Install PowerShell 7 (pwsh) - cross-platform"
start_time=$(date +%s)

# --- Already installed? Don't fight an existing install (esp. macOS cask vs formula). ---
if command -v pwsh &>/dev/null; then
    echo "pwsh is already installed:"
    pwsh --version
    exit 0
fi

install_debian_ubuntu() {
    # $1 = packages.microsoft.com distro id ("debian" or "ubuntu"), $2 = version id (e.g. "12", "24.04")
    local distro_id="$1" version_id="$2"
    sudo apt-get update && sudo apt-get install -y wget
    sudo wget -q "https://packages.microsoft.com/config/${distro_id}/${version_id}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
    if [ ! -s /tmp/packages-microsoft-prod.deb ]; then
        echo "ERROR: Failed to download the Microsoft repo package for ${distro_id} ${version_id}." >&2
        echo "This version may not be officially supported yet - see https://aka.ms/powershell-release" >&2
        exit 1
    fi
    sudo dpkg -i /tmp/packages-microsoft-prod.deb
    rm -f /tmp/packages-microsoft-prod.deb
    sudo apt-get update
    sudo apt-get install -y powershell
}

install_rhel_family() {
    local majorver="${VERSION_ID%%.*}"
    curl -sSL -o /tmp/packages-microsoft-prod.rpm "https://packages.microsoft.com/config/rhel/${majorver}/packages-microsoft-prod.rpm"
    sudo rpm -i /tmp/packages-microsoft-prod.rpm
    rm -f /tmp/packages-microsoft-prod.rpm
    sudo dnf update -y
    sudo dnf install -y powershell
}

install_binary_fallback() {
    # Used for distros Microsoft doesn't publish native packages for (openSUSE/SLES, Fedora).
    # See: https://learn.microsoft.com/powershell/scripting/install/alternate-install-methods
    echo "This distribution isn't in Microsoft's officially supported package-repo list."
    echo "Installing via the documented binary tar.gz method instead."

    echo "Installing runtime dependencies (best-effort)..."
    if command -v zypper &>/dev/null; then
        for pkg in krb5 libopenssl3 libicu; do sudo zypper --non-interactive install -y "$pkg" 2>/dev/null || true; done
    elif command -v dnf &>/dev/null; then
        for pkg in krb5-libs openssl-libs libicu; do sudo dnf install -y "$pkg" 2>/dev/null || true; done
    fi

    local arch plat
    arch=$(uname -m)
    case "$arch" in
        x86_64)  plat="linux-x64" ;;
        aarch64) plat="linux-arm64" ;;
        armv7l|armv6l) plat="linux-arm32" ;;
        *) echo "ERROR: Unsupported architecture '$arch' for the binary tar.gz method." >&2; exit 1 ;;
    esac

    echo "Looking up the latest PowerShell release for $plat..."
    local url
    url=$(curl -sSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
        | grep -o "\"browser_download_url\": *\"[^\"]*${plat}\.tar\.gz\"" \
        | head -1 | grep -o 'https://[^"]*')

    if [ -z "$url" ]; then
        echo "ERROR: Could not determine the latest PowerShell download URL from GitHub." >&2
        echo "Install manually from https://github.com/PowerShell/PowerShell/releases" >&2
        exit 1
    fi

    echo "Downloading $url ..."
    curl -L -o /tmp/powershell.tar.gz "$url"
    sudo mkdir -p /opt/microsoft/powershell/7
    sudo tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7
    sudo chmod +x /opt/microsoft/powershell/7/pwsh
    sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
    rm -f /tmp/powershell.tar.gz
}

install_macos() {
    if ! command -v brew &>/dev/null; then
        echo "ERROR: Homebrew is required to install PowerShell on macOS." >&2
        echo "Install it from https://brew.sh first, then re-run this script." >&2
        exit 1
    fi
    brew install powershell
}

# --- Detect platform and dispatch ---
if [[ "$(uname)" == "Darwin" ]]; then
    echo "Detected macOS."
    install_macos
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        debian)
            echo "Detected Debian $VERSION_ID."
            install_debian_ubuntu debian "$VERSION_ID"
            ;;
        ubuntu)
            echo "Detected Ubuntu $VERSION_ID."
            install_debian_ubuntu ubuntu "$VERSION_ID"
            ;;
        linuxmint)
            base_ver=""
            if [ -f /etc/upstream-release/lsb-release ]; then
                base_ver=$(grep '^DISTRIB_RELEASE=' /etc/upstream-release/lsb-release | cut -d= -f2)
            fi
            if [ -z "$base_ver" ]; then
                echo "ERROR: Could not determine the underlying Ubuntu version for Linux Mint" >&2
                echo "(expected /etc/upstream-release/lsb-release to be present)." >&2
                exit 1
            fi
            echo "Detected Linux Mint (Ubuntu $base_ver base)."
            install_debian_ubuntu ubuntu "$base_ver"
            ;;
        rhel|centos|rocky|almalinux)
            echo "Detected $PRETTY_NAME."
            install_rhel_family
            ;;
        opensuse*|sles|sled|fedora)
            echo "Detected $PRETTY_NAME."
            install_binary_fallback
            ;;
        *)
            case "${ID_LIKE:-}" in
                *debian*)          echo "Unrecognized Debian-derivative ($ID) - trying the Ubuntu package path."; install_debian_ubuntu ubuntu "22.04" ;;
                *rhel*|*fedora*)   echo "Unrecognized RHEL-derivative ($ID) - trying the RHEL dnf/rpm path."; install_rhel_family ;;
                *suse*)            echo "Unrecognized SUSE-derivative ($ID) - using the binary tar.gz method."; install_binary_fallback ;;
                *)
                    echo "ERROR: Unsupported/unrecognized Linux distribution '$ID'." >&2
                    echo "Install manually: https://aka.ms/powershell-release" >&2
                    exit 1
                    ;;
            esac
            ;;
    esac
else
    echo "ERROR: Unsupported OS - not macOS and no /etc/os-release found." >&2
    exit 1
fi

# --- Verify ---
if command -v pwsh &>/dev/null; then
    pwsh --version
else
    echo "WARNING: pwsh not found on PATH after installation. Try opening a new shell." >&2
fi

end_time=$(date +%s)
total_time=$((end_time - start_time))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
