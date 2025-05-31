#!/bin/bash
# Author: Roy Wiseman 2025-05

# dockurr/windows Docker Setup Script
# ────────────────────────────────────────────────
# Automates the deployment of Windows inside a Docker container.

# ---[ Prerequisites Check ]----------------------
# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Installing...${NC}"
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo -e "${GREEN}Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'.${NC}"
        exit 1
    else
        echo -e "${RED}❌ Failed to install Docker.${NC}"
        exit 1
    fi
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    echo "See instructions: https://docs.docker.com/engine/install/"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker and rerun."
    exit 1
fi

# Check for KVM
echo "Checking KVM availability..."
if ! grep -q -w "vmx\|svm" /proc/cpuinfo; then
    echo -e "${RED}✖ CPU does not support hardware virtualization (VT-x or AMD-V). KVM cannot be used.${NC}"
    echo "Please ensure virtualization is enabled in your BIOS/UEFI."
    exit 1
fi

if ! lsmod | grep -q kvm; then
    echo -e "${YELLOW}⚠️ KVM modules not loaded. Attempting to load...${NC}"
    sudo modprobe kvm_intel || sudo modprobe kvm_amd
    if ! lsmod | grep -q kvm; then
        echo -e "${RED}✖ Failed to load KVM modules. Ensure KVM is enabled in BIOS/UEFI and you have permissions.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ KVM modules loaded.${NC}"
fi

if ! command -v kvm-ok &> /dev/null; then
    echo -e "${YELLOW}kvm-ok command not found. Attempting to install cpu-checker...${NC}"
    sudo apt update >/dev/null 2>&1 && sudo apt install -y cpu-checker >/dev/null 2>&1
    if ! command -v kvm-ok &> /dev/null; then
        echo -e "${RED}✖ Failed to install cpu-checker. Please install it manually and run 'kvm-ok' to verify KVM setup.${NC}"
        # We can proceed but with a warning, as the device might still work.
    fi
fi

if command -v kvm-ok &> /dev/null; then
    KVM_CHECK_OUTPUT=$(sudo kvm-ok 2>&1)
    if [[ "$KVM_CHECK_OUTPUT" != *"KVM acceleration can be used"* ]]; then
        echo -e "${RED}✖ KVM check failed:${NC}"
        echo "$KVM_CHECK_OUTPUT"
        echo "Please resolve KVM issues. Common fixes:"
        echo "  - Ensure virtualization (Intel VT-x or AMD SVM) is enabled in your BIOS/UEFI."
        echo "  - If running in a VM, enable 'nested virtualization'."
        echo "  - You might be on a cloud provider that disallows nested virtualization."
        echo "  - Try adding 'privileged: true' to Docker Compose or '--privileged' to Docker CLI (use with caution)."
        # exit 1 # You might choose to exit or allow the user to proceed at their own risk
        read -p "KVM check failed or couldn't be fully verified. Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✓ KVM acceleration can be used.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ Could not run kvm-ok. Proceeding, but ensure /dev/kvm is accessible to Docker.${NC}"
fi


# ──[ Styling ]────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m' # Used for default paths
BOLD='\033[1m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'

# ──[ Detect Host IP ]─────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    HOST_IP="YOUR_HOST_IP" # Fallback
fi
echo -e "${CYAN}Detected local IP for connection info: ${HOST_IP}${NC}"


# ──[ Configuration ]──────────────────────────────
# --- Container Settings ---
DEFAULT_CONTAINER_NAME="windows"
DOCKURR_IMAGE="dockurr/windows:latest"

# --- Default Host directory for Windows Data ---
DEFAULT_HOST_STORAGE_DIR="${PWD}/windows_storage" # Changed from ./windows to be more explicit
WINDOWS_CONTAINER_STORAGE_DIR="/storage" # Internal data path inside the container (fixed by image)

# --- Default Windows Settings ---
declare -A WINDOWS_VERSIONS=(
    ["Windows 11 Pro (Default)"]="11"
    ["Windows 11 LTSC"]="11l"
    ["Windows 11 Enterprise"]="11e"
    ["Windows 10 Pro"]="10"
    ["Windows 10 LTSC"]="10l"
    ["Windows 10 Enterprise"]="10e"
    ["Windows 8.1 Enterprise"]="8e"
    ["Windows 7 Ultimate"]="7u"
    ["Windows Vista Ultimate"]="vu"
    ["Windows XP Professional"]="xp"
    ["Windows Server 2025"]="2025"
    ["Windows Server 2022"]="2022"
    ["Windows Server 2019"]="2019"
    ["Windows Server 2016"]="2016"
    ["Windows Server 2012"]="2012"
    ["Windows Server 2008"]="2008"
    ["Windows Server 2003"]="2003"
    ["Custom ISO URL"]="CUSTOM_URL"
    ["Custom Local ISO Path"]="CUSTOM_LOCAL_ISO"
)
DEFAULT_WINDOWS_VERSION_CODE="11" # Windows 11 Pro

DEFAULT_DISK_SIZE="64G"
DEFAULT_RAM_SIZE="4G"
DEFAULT_CPU_CORES="2"

# --- Port Settings ---
DEFAULT_WEB_PORT=8006 # For web viewer
DEFAULT_RDP_PORT=3389 # For Remote Desktop

# --- Other Docker Settings ---
DEFAULT_RESTART_POLICY="unless-stopped"
DEFAULT_STOP_TIMEOUT="120" # 2 minutes in seconds

# ──[ Helper Functions ]─────────────────────────
ensure_dir() {
    if [ ! -d "$1" ]; then
        echo -e "${CYAN}Ensuring directory exists on host: $1${NC}"
        mkdir -p "$1"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Error: Failed to create directory: $1${NC}"
            echo -e "${YELLOW}Please check permissions or create it manually.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Directory created: $1${NC}"
    else
        echo -e "${GREEN}✅ Directory already exists on host: $1${NC}"
    fi
}

prompt_yes_no() {
    local prompt_message=$1
    local default_value=$2
    local response

    while true; do
        read -r -p "$prompt_message [$default_value]: " response
        response="${response:-$default_value}" # Set to default if empty
        if [[ "$response" =~ ^[Yy]$ ]]; then
            REPLY="Y" # Set REPLY for the caller to check
            return 0
        elif [[ "$response" =~ ^[Nn]$ ]]; then
            REPLY="N"
            return 0
        else
            echo -e "${YELLOW}Invalid input. Please enter 'y' or 'n'.${NC}"
        fi
    done
}

# ──[ Check for Existing Container ]───────────────
echo
read -e -p "$(echo -e ${BOLD}"Enter a name for your Windows container [${DEFAULT_CONTAINER_NAME}]: "${NC})" user_container_name
CONTAINER_NAME="${user_container_name:-$DEFAULT_CONTAINER_NAME}"

EXISTS=$(docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$")

# ──[ Installation Logic ]─────────────────────────
if $EXISTS; then
    echo -e "${YELLOW}A container named '${CONTAINER_NAME}' already exists.${NC}"
    echo -e "If you proceed, this script will attempt to start it if stopped, or show info."
    echo -e "To create a new instance with different settings, please remove the existing one first"
    echo -e "(${CYAN}docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME${NC}) and re-run this script."
    echo
    docker ps -a --filter "name=^${CONTAINER_NAME}$"
    exit 0
fi

echo -e "${BOLD}Starting setup for Windows container '$CONTAINER_NAME'.${NC}"

# ──[ Prompt for Basic Configuration ]─────────────
echo
echo -e "${BOLD}Select Windows Version:${NC}"
options=()
# Get sorted keys for display
sorted_keys=($(for k in "${!WINDOWS_VERSIONS[@]}"; do echo "$k"; done | sort))

for i in "${!sorted_keys[@]}"; do
    key="${sorted_keys[$i]}"
    # Highlight default
    if [[ "${WINDOWS_VERSIONS[$key]}" == "$DEFAULT_WINDOWS_VERSION_CODE" ]]; then
        echo -e "  $(($i+1))) ${GREEN}${key}${NC}"
        default_choice_num=$(($i+1))
    else
        echo "  $(($i+1))) ${key}"
    fi
    options+=("${WINDOWS_VERSIONS[$key]}")
done
read -p "Enter number for Windows version [Default: Windows 11 Pro]: " choice
choice_index=$(($choice-1))

if [[ -n "$choice" && "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]]; then
    SELECTED_VERSION_CODE="${options[$choice_index]}"
else
    SELECTED_VERSION_CODE="$DEFAULT_WINDOWS_VERSION_CODE"
    echo -e "${CYAN}Using default: Windows 11 Pro${NC}"
fi
ENV_VERSION_VALUE="$SELECTED_VERSION_CODE" # This will be used for -e VERSION=

CUSTOM_ISO_PATH=""
if [[ "$SELECTED_VERSION_CODE" == "CUSTOM_URL" ]]; then
    read -e -p "Enter custom ISO URL: " CUSTOM_ISO_URL
    ENV_VERSION_VALUE="$CUSTOM_ISO_URL"
elif [[ "$SELECTED_VERSION_CODE" == "CUSTOM_LOCAL_ISO" ]]; then
    read -e -p "Enter full path to local ISO file: " custom_iso_input
    if [ -f "$custom_iso_input" ]; then
        CUSTOM_ISO_PATH="$custom_iso_input"
        echo -e "${CYAN}Using local ISO: $CUSTOM_ISO_PATH. The 'VERSION' environment variable will be ignored.${NC}"
        # VERSION env might be ignored by dockurr/windows if /boot.iso is mounted
        ENV_VERSION_VALUE="" # Clear it or set to a placeholder if needed
    else
        echo -e "${RED}✖ Error: Local ISO file not found at '$custom_iso_input'. Exiting.${NC}"
        exit 1
    fi
fi

echo
read -e -p "$(echo -e ${BOLD}"Enter host directory for Windows persistent storage [${BLUE_BOLD}${DEFAULT_HOST_STORAGE_DIR}${NC}]: "${NC})" user_storage_input
HOST_STORAGE_DIR="${user_storage_input:-$DEFAULT_HOST_STORAGE_DIR}"
ensure_dir "$HOST_STORAGE_DIR"

echo
read -p "$(echo -e ${BOLD}"Enter disk size (e.g., 128G, 256G) [${DEFAULT_DISK_SIZE}]: "${NC})" user_disk_size
DISK_SIZE="${user_disk_size:-$DEFAULT_DISK_SIZE}"

read -p "$(echo -e ${BOLD}"Enter RAM size (e.g., 8G, 16G) [${DEFAULT_RAM_SIZE}]: "${NC})" user_ram_size
RAM_SIZE="${user_ram_size:-$DEFAULT_RAM_SIZE}"

read -p "$(echo -e ${BOLD}"Enter number of CPU cores (e.g., 4, 8) [${DEFAULT_CPU_CORES}]: "${NC})" user_cpu_cores
CPU_CORES="${user_cpu_cores:-$DEFAULT_CPU_CORES}"

# ──[ Prompt for Port Configuration ]─────────────
echo
read -p "$(echo -e ${BOLD}"Enter host port for Web Viewer (for installation) [${DEFAULT_WEB_PORT}]: "${NC})" user_web_port
WEB_PORT="${user_web_port:-$DEFAULT_WEB_PORT}"

read -p "$(echo -e ${BOLD}"Enter host port for RDP (TCP/UDP) [${DEFAULT_RDP_PORT}]: "${NC})" user_rdp_port
RDP_PORT="${user_rdp_port:-$DEFAULT_RDP_PORT}"

# ──[ Advanced Configuration (Optional) ]──────────
echo
prompt_yes_no "$(echo -e ${BOLD}"Configure advanced options (username, language, shared folder, etc.)?"${NC})" "n"
if [[ "$REPLY" == "Y" ]]; then
    echo
    read -p "$(echo -e ${BOLD}"Windows Username (affects new installs only) [Docker]: "${NC})" user_username
    WINDOWS_USERNAME="${user_username:-}" # Empty means default Docker

    read -p "$(echo -e ${BOLD}"Windows Password (affects new installs only) [admin]: "${NC})" user_password
    WINDOWS_PASSWORD="${user_password:-}" # Empty means default admin

    read -p "$(echo -e ${BOLD}"Windows Language (e.g., French, German; affects new installs only) [English]: "${NC})" user_language
    WINDOWS_LANGUAGE="${user_language:-}" # Empty means default English

    prompt_yes_no "$(echo -e ${BOLD}"Share a folder from host to Windows ( \\\\host.lan\\Data )?"${NC})" "n"
    if [[ "$REPLY" == "Y" ]]; then
        DEFAULT_HOST_SHARE_DIR="${PWD}/windows_share"
        read -e -p "$(echo -e ${BOLD}"Enter host directory to share [${BLUE_BOLD}${DEFAULT_HOST_SHARE_DIR}${NC}]: "${NC})" user_share_dir
        HOST_SHARE_DIR="${user_share_dir:-$DEFAULT_HOST_SHARE_DIR}"
        ensure_dir "$HOST_SHARE_DIR"
    fi
fi

# ──[ Build Docker Command ]─────────────────────
DOCKER_CMD="docker run -it" # -it for interactive install, consider -d for long running
DOCKER_CMD+=" --name \"$CONTAINER_NAME\""
DOCKER_CMD+=" --stop-timeout $DEFAULT_STOP_TIMEOUT"
DOCKER_CMD+=" --restart $DEFAULT_RESTART_POLICY"

# Ports
DOCKER_CMD+=" -p ${WEB_PORT}:8006"
DOCKER_CMD+=" -p ${RDP_PORT}:3389/tcp -p ${RDP_PORT}:3389/udp"

# Devices & Capabilities
DOCKER_CMD+=" --device=/dev/kvm --device=/dev/net/tun"
DOCKER_CMD+=" --cap-add NET_ADMIN"

# Volumes
DOCKER_CMD+=" -v \"$HOST_STORAGE_DIR\":\"$WINDOWS_CONTAINER_STORAGE_DIR\""
if [[ -n "$CUSTOM_ISO_PATH" ]]; then
    DOCKER_CMD+=" -v \"$CUSTOM_ISO_PATH:/boot.iso:ro\"" # Mount ISO as read-only
fi
if [[ -n "$HOST_SHARE_DIR" ]]; then
    DOCKER_CMD+=" -v \"$HOST_SHARE_DIR:/data\""
fi

# Environment Variables
if [[ -n "$ENV_VERSION_VALUE" && "$SELECTED_VERSION_CODE" != "CUSTOM_LOCAL_ISO" ]]; then
    DOCKER_CMD+=" -e VERSION=\"$ENV_VERSION_VALUE\""
fi
if [[ "$DISK_SIZE" != "$DEFAULT_DISK_SIZE" ]]; then
    DOCKER_CMD+=" -e DISK_SIZE=\"$DISK_SIZE\""
fi
if [[ "$RAM_SIZE" != "$DEFAULT_RAM_SIZE" ]]; then
    DOCKER_CMD+=" -e RAM_SIZE=\"$RAM_SIZE\""
fi
if [[ "$CPU_CORES" != "$DEFAULT_CPU_CORES" ]]; then
    DOCKER_CMD+=" -e CPU_CORES=\"$CPU_CORES\""
fi
if [[ -n "$WINDOWS_USERNAME" ]]; then
    DOCKER_CMD+=" -e USERNAME=\"$WINDOWS_USERNAME\""
fi
if [[ -n "$WINDOWS_PASSWORD" ]]; then
    DOCKER_CMD+=" -e PASSWORD=\"$WINDOWS_PASSWORD\""
fi
if [[ -n "$WINDOWS_LANGUAGE" ]]; then
    DOCKER_CMD+=" -e LANGUAGE=\"$WINDOWS_LANGUAGE\""
fi
# Add other environment variables from FAQ as needed (e.g. REGION, KEYBOARD, EDITION, MANUAL, DHCP, ARGUMENTS for USB)

DOCKER_CMD+=" $DOCKURR_IMAGE"

echo
echo -e "${BOLD}The following Docker command will be executed:${NC}"
echo -e "${YELLOW}$DOCKER_CMD${NC}"
echo
prompt_yes_no "$(echo -e ${BOLD}"Proceed with running this command?"${NC})" "y"
if [[ "$REPLY" == "N" ]]; then
    echo -e "${CYAN}Aborted by user.${NC}"
    exit 0
fi

# ──[ Pull Image & Run Container ]──────────────────
echo -e "${CYAN}Pulling latest ${DOCKURR_IMAGE} image (if not present)...${NC}"
docker pull ${DOCKURR_IMAGE}
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Failed to pull ${DOCKURR_IMAGE}. Check your internet connection and Docker setup.${NC}"
    exit 1
fi

echo -e "${CYAN}Starting Windows container '$CONTAINER_NAME'...${NC}"
echo -e "${YELLOW}This will start the automated Windows installation. Monitor the container logs or the web UI.${NC}"
eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths and variables

if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Failed to start Windows container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
    echo -e "${RED}   Make sure KVM is properly configured and accessible.${NC}"
    echo -e "${RED}   If you suspect permission issues with /dev/kvm, you might need to adjust group memberships"
    echo -e "${RED}   or, as a last resort for testing, run Docker with 'sudo' or add '--privileged' to the command (use with caution).${NC}"
    exit 1
fi

# ──[ Post-Setup Info (Always Shown) ]─────────────
echo
echo -e "${GREEN}✓ Windows container '$CONTAINER_NAME' should be starting the installation process!${NC}"
echo
echo -e "${BOLD}📍 Windows Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Host directory for storage: ${CYAN}$HOST_STORAGE_DIR${NC} (mapped to ${YELLOW}$WINDOWS_CONTAINER_STORAGE_DIR${NC} inside)"
if [[ -n "$HOST_SHARE_DIR" ]]; then
    echo -e "- Host shared folder: ${CYAN}$HOST_SHARE_DIR${NC} (available at ${YELLOW}\\\\host.lan\\Data${NC} inside Windows)"
fi
echo -e "- Web Viewer (for installation): ${YELLOW}http://${HOST_IP}:${WEB_PORT}${NC} or ${YELLOW}http://localhost:${WEB_PORT}${NC}"
echo -e "- RDP Access (after setup): Connect to ${CYAN}${HOST_IP}:${RDP_PORT}${NC} (or ${CYAN}localhost:${RDP_PORT}${NC})"
echo -e "  Default credentials (if not changed before first install): User: ${CYAN}Docker${NC}, Pass: ${CYAN}admin${NC}"
if [[ -n "$WINDOWS_USERNAME" || -n "$WINDOWS_PASSWORD" ]]; then
    echo -e "  Configured credentials (for this install): User: ${CYAN}${WINDOWS_USERNAME:-Docker}${NC}, Pass: ${CYAN}${WINDOWS_PASSWORD:-admin}${NC}"
fi

echo
echo -e "${BOLD}⚙️ Installation Steps:${NC}"
echo -e "  1. Open the Web Viewer: ${YELLOW}http://${HOST_IP}:${WEB_PORT}${NC}"
echo -e "  2. The installation will be performed automatically. Sit back and relax."
echo -e "  3. Once you see the Windows desktop, your installation is ready."
echo -e "  4. For better performance and features (audio, clipboard), connect using a Microsoft Remote Desktop client after setup."

echo
echo -e "${BOLD}🔧 Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}          - View container logs (useful during installation)"
echo -e "  ${CYAN}docker stop $CONTAINER_NAME${NC}             - Stop the Windows container"
echo -e "  ${CYAN}docker start $CONTAINER_NAME${NC}            - Start the Windows container"
echo -e "  ${CYAN}docker restart $CONTAINER_NAME${NC}          - Restart the Windows container"
echo -e "  ${CYAN}docker rm $CONTAINER_NAME${NC}               - Remove the container (Data in ${BLUE_BOLD}$HOST_STORAGE_DIR${NC} is preserved unless you delete the folder)"
echo
echo -e "${BOLD}💡 Tip:${NC} Environment variables like USERNAME, PASSWORD, and LANGUAGE only take effect during the *initial* automated installation. Changing them later requires a fresh setup (delete container and storage, then rerun script)."
echo

exit 0
