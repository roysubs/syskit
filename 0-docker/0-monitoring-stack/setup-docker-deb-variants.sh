#!/usr/bin/env bash
# Author: Roy Wiseman 2025-05
set -euo pipefail

# === Initial Checks and Detection ===

# Detect architecture
ARCH=$(dpkg --print-architecture)
# Keep this output as it's basic system info
echo "Detected architecture: $ARCH"

# Detect distro and codename
if ! command -v lsb_release >/dev/null 2>&1; then
    echo "Error: lsb_release command not found. Please install 'lsb-release' package first."
    exit 1
fi

DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)

# Keep this output as it's basic system info
echo "Detected distro: $DISTRO"
echo "Detected codename: $CODENAME"

# Determine Docker repo base URL depending on distro
DOCKER_REPO_URL=""
if [[ "$DISTRO" == "ubuntu" ]] || [[ "$DISTRO" == "linuxmint" ]]; then
    # For Linux Mint, still use Ubuntu repos
    # Linux Mint codename often differs, map it to Ubuntu base if mint detected
    if [[ "$DISTRO" == "linuxmint" ]]; then
        # Map common Mint versions to Ubuntu codenames
        case "$CODENAME" in
            una|vanessa|vera|victoria) UBUNTU_BASE="jammy" ;;
            ulyana|ulyssa|uma) UBUNTU_BASE="focal" ;;
            tessa|tara) UBUNTU_BASE="bionic" ;;
            *)
                # Warning is okay here as it indicates a potential issue/fallback
                echo "Warning: Unknown Linux Mint codename '$CODENAME', defaulting to jammy"
                UBUNTU_BASE="jammy"
                ;;
        esac
        CODENAME=$UBUNTU_BASE
        DISTRO="ubuntu"
        # Keep this output as it's relevant mapping info
        echo "Using Ubuntu base codename: $CODENAME"
    fi
    DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
elif [[ "$DISTRO" == "debian" ]]; then
    DOCKER_REPO_URL="https://download.docker.com/linux/debian"
else
    # Error is necessary if distro is unsupported
    echo "Error: Unsupported distro '$DISTRO'. This script supports Ubuntu, Linux Mint, and Debian only."
    exit 1
fi

# Define the expected repository entry
REPO_ENTRY="deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL} ${CODENAME} stable"

# === Check and Setup Docker Repository (Silent if already configured) ===

NEEDS_REPO_SETUP=false
DOCKER_GPG_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_APT_SOURCE="/etc/apt/sources.list.d/docker.list"

# Check if GPG key exists
if [ ! -f "$DOCKER_GPG_KEYRING" ]; then
    NEEDS_REPO_SETUP=true
fi

# Check if APT source list exists and matches content
if [ ! -f "$DOCKER_APT_SOURCE" ]; then
    NEEDS_REPO_SETUP=true
else
    # Read existing content and compare, ignoring potential trailing newlines
    EXISTING_REPO_ENTRY=$(<"$DOCKER_APT_SOURCE")
    if [[ "$EXISTING_REPO_ENTRY" != "$REPO_ENTRY" ]]; then
        NEEDS_REPO_SETUP=true
    fi
fi

# Perform repository setup only if needed
if [ "$NEEDS_REPO_SETUP" = true ]; then
    echo "==> Setting up Docker repository..."

    # Create keyrings directory if it doesn't exist (idempotent)
    sudo mkdir -p /etc/apt/keyrings

    # Download Docker GPG key (will overwrite if exists but is different, or if missing)
    echo "Downloading Docker GPG key..."
    # Use --create-dirs with tee to handle the directory creation more robustly with the pipe
    curl -fsSL "${DOCKER_REPO_URL}/gpg" | sudo gpg --dearmor | sudo tee "$DOCKER_GPG_KEYRING" > /dev/null

    # Add Docker repo list file (will overwrite if exists but is different, or if missing)
    echo "Adding Docker repository:"
    echo "  $REPO_ENTRY"
    echo "$REPO_ENTRY" | sudo tee "$DOCKER_APT_SOURCE" > /dev/null

    # Update package lists after adding new repo
    echo "Updating package lists..."
    sudo apt update
else
    # Only print this if repo setup was NOT needed
    echo "==> Docker repository is already configured correctly."
fi

# === Check and Install Docker Packages (Silent if already installed) ===

# List of core Docker packages to check/install
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
ALL_PACKAGES_INSTALLED=true

# Check if all required packages are installed
for pkg in $DOCKER_PACKAGES; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        ALL_PACKAGES_INSTALLED=false
        break # Exit loop as soon as one missing package is found
    fi
done

if [ "$ALL_PACKAGES_INSTALLED" = true ]; then
    echo "==> Required Docker packages are already installed."
else
    echo "==> Installing Docker packages..."
    # Install packages (apt install is idempotent for already installed packages, but we only run it if needed)
    sudo apt install -y $DOCKER_PACKAGES
fi

# === Check and Add User to Docker Group (Existing conditional logic) ===

# Test and ensure that user is in docker group
if groups "$USER" | grep -qw docker; then
    # Silent if user is already in the group
    : # Do nothing, effectively silent
else
    # Only print messages if user needs to be added
    echo "==> User '$USER' is NOT in the docker group. Adding now..."
    sudo usermod -aG docker "$USER"
    echo "==> User '$USER' has been added to the docker group."
    echo "Please log out and log back in, or reboot your system, to apply this change."
fi

# === Final Success Message ===
# This message confirms the script finished and the desired state should be met
echo "==> Docker setup script finished."
echo "Check Docker version: docker --version"
echo "Run test container: sudo docker run hello-world"


