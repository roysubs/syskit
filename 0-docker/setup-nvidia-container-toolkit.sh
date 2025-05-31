#!/bin/bash
# Author: Roy Wiseman 2025-05

# This script installs and configures the NVIDIA Container Toolkit on a Debian host.
# This toolkit is required for Docker containers (like linuxserver/webtop with GPU passthrough)
# to access and utilize NVIDIA GPUs for better performance.
# Based on official NVIDIA Container Toolkit documentation for Debian 12 (Bookworm).
# ───────────────────────────────────────────────────────────────

# ───[ Styling ]─────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ───[ Prerequisites Check ]─────────────────────────────────────
# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script with sudo.${NC}"
  echo -e "Example: ${CYAN}sudo ./docker-nvidia-toolkit.sh${NC}"
  exit 1
fi

# Check if Docker is installed (Toolkit depends on it)
if ! command -v docker &> /dev/null
then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    echo -e "Please install Docker first and then rerun this script."
    echo -e "See instructions: https://docs.docker.com/engine/install/debian/"
    exit 1
fi

echo -e "${BOLD}NVIDIA Container Toolkit Installation Script for Debian${NC}"
echo "--------------------------------------------------"

# ───[ Installation Steps ]────────────────────────────────────
echo -e "${CYAN}Step 1: Updating package list...${NC}"
if ! apt update; then
  echo -e "${RED}✖ Error: Failed to update package list. Check your internet connection and sources.list.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Package list updated.${NC}"

echo -e "\n${CYAN}Step 2: Installing necessary packages (software-properties-common, apt-transport-https, ca-certificates, curl)...${NC}"
if ! apt install -y software-properties-common apt-transport-https ca-certificates curl; then
  echo -e "${RED}✖ Error: Failed to install necessary packages.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Necessary packages installed.${NC}"

echo -e "\n${CYAN}Step 3: Adding the NVIDIA repository GPG key...${NC}"
# Use curl to fetch the key and gpg to dearmor and save it
if ! curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
  echo -e "${RED}✖ Error: Failed to add the NVIDIA repository GPG key.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ NVIDIA repository GPG key added.${NC}"

echo -e "\n${CYAN}Step 4: Adding the NVIDIA repository to your sources list (using unified Debian path)...${NC}"
# Use the unified Debian path for the repository list file
if ! curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null; then # Added > /dev/null to suppress tee output
  echo -e "${RED}✖ Error: Failed to add the NVIDIA repository list.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ NVIDIA repository added.${NC}"

echo -e "\n${CYAN}Step 5: Updating package list again with the new repository...${NC}"
if ! apt update; then
  echo -e "${RED}✖ Error: Failed to update package list after adding NVIDIA repository.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Package list updated.${NC}"

echo -e "\n${CYAN}Step 6: Installing the NVIDIA Container Toolkit...${NC}"
if ! apt install -y nvidia-container-toolkit; then
  echo -e "${RED}✖ Error: Failed to install nvidia-container-toolkit.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ NVIDIA Container Toolkit installed.${NC}"

echo -e "\n${CYAN}Step 7: Configuring the Docker daemon to use the NVIDIA runtime...${NC}"
# This command modifies the Docker daemon configuration file
if ! nvidia-ctk runtime configure --runtime=docker; then
  echo -e "${RED}✖ Error: Failed to configure Docker daemon.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Docker daemon configured for NVIDIA runtime.${NC}"

echo -e "\n${CYAN}Step 8: Restarting the Docker daemon to apply changes...${NC}"
if ! systemctl restart docker; then
  echo -e "${RED}✖ Error: Failed to restart Docker service. You may need to do this manually.${NC}"
  echo -e "${RED}  Try: ${CYAN}sudo systemctl status docker${RED} and ${CYAN}sudo systemctl start docker${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Docker daemon restarted.${NC}"

# ───[ Verification and Next Steps ]───────────────────────────
echo -e "\n--------------------------------------------------"
echo -e "${GREEN}${BOLD}NVIDIA Container Toolkit installation and configuration complete!${NC}"
echo -e "\n${BOLD}Verification:${NC}"
echo -e "You can verify the installation by running a test container:"
echo -e "${CYAN}docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi${NC}"
echo -e "This should print information about your GPU(s) inside a container."

echo -e "\n${BOLD}Next Steps:${NC}"
echo -e "Now that the NVIDIA runtime is configured for Docker, you should be able to"
echo -e "run your Webtop container script (e.g. ./docker-webtop-debian-mate-3012.sh)"
echo -e "Make sure to set ${BOLD}ENABLE_GRAPHICS_PASSTHROUGH=true${NC} for this to work."
echo -e "This switch allows the ${BOLD}--runtime=nvidia${NC} flag to be recognized."
echo -e "${YELLOW}Remember to stop and remove any previous failed container attempts first:${NC}"
echo -e "${CYAN}docker stop webtop-debian-mate > /dev/null 2>&1 || true${NC}"
echo -e "${CYAN}docker rm webtop-debian-mate > /dev/null 2>&1 || true${NC}"
echo -e "Then re-run: ${CYAN}./docker-webtop-debian-mate-3012.sh${NC}"
