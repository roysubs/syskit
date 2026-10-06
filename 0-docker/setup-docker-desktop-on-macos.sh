#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Installs Docker Desktop for macOS with Homebrew, starts it, and waits for the daemon.
# Docker Desktop runs containers in a Linux VM, so Linux-only features (/dev/kvm,
# network_mode: host) are not available. See the notes at the end.
# IDEMPOTENT: safe to run multiple times.

set -u

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

WAIT_SECONDS=180

if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}This script is for macOS. On Debian-family Linux use setup-docker-on-deb-variants.sh.${NC}" >&2
    exit 1
fi

echo -e "${BOLD}==> Docker Desktop setup for macOS ($(uname -m))${NC}"

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
    echo -e "${RED}Homebrew is not installed.${NC} Install it first, then re-run this script:" >&2
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
    exit 1
fi

# --- Docker Desktop app ---
if [[ -d "/Applications/Docker.app" ]]; then
    echo -e "${GREEN}✓ Docker Desktop is already installed.${NC}"
else
    echo -e "${CYAN}==> Installing Docker Desktop (Homebrew cask)...${NC}"
    if ! brew install --cask docker; then
        echo -e "${RED}✖ brew install --cask docker failed.${NC}" >&2
        exit 1
    fi
fi

# --- Start Docker Desktop if the daemon is not answering ---
if docker info &>/dev/null; then
    echo -e "${GREEN}✓ Docker daemon is already running.${NC}"
else
    echo -e "${CYAN}==> Starting Docker Desktop...${NC}"
    open -a Docker
    echo -n "    Waiting for the Docker daemon (up to ${WAIT_SECONDS}s)"
    waited=0
    until docker info &>/dev/null; do
        if (( waited >= WAIT_SECONDS )); then
            echo
            echo -e "${YELLOW}⚠ The daemon is not up yet.${NC}"
            echo "  On first start Docker Desktop asks you to accept its terms and may ask for"
            echo "  your password to install its helper. Finish those prompts, then re-run this script."
            exit 1
        fi
        sleep 3
        waited=$((waited + 3))
        echo -n "."
    done
    echo
    echo -e "${GREEN}✓ Docker daemon is running.${NC}"
fi

# --- Verify ---
echo
echo -e "${BOLD}==> Verification${NC}"
docker --version
docker compose version 2>/dev/null || echo -e "${YELLOW}⚠ docker compose plugin not found.${NC}"

echo
echo -e "${BOLD}Notes${NC}"
echo "  • Docker Desktop starts at login if you enable it in its settings."
echo "  • Services with network_mode: host do not reach your Mac's network; use port mappings instead."
echo "  • Linux-only images that need /dev/kvm (for example dockurr/windows) will not run here."
echo "  • Test: docker run --rm hello-world"
echo -e "${GREEN}==> Docker Desktop setup finished.${NC}"
