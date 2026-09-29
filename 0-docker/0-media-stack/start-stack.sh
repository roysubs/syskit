#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-09
# Media Stack Start Script with Pre-flight Component Check & Idempotency

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}              Media Stack - Pre-flight & Startup Manager           ${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"

# Check Docker prerequisites
if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker CLI is not installed or not in PATH.${NC}"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running or current user lacks docker permissions.${NC}"
    exit 1
fi

# Locate Compose File
COMPOSE_FILE=""
for f in "docker-compose.yaml" "docker-compose.yml" "docker-compose-full.yaml"; do
    if [[ -f "$f" ]]; then
        COMPOSE_FILE="$f"
        break
    fi
done

if [[ -z "$COMPOSE_FILE" ]]; then
    echo -e "${RED}❌ No docker-compose.yaml found in $SCRIPT_DIR.${NC}"
    exit 1
fi

echo -e "${CYAN}📁 Working Directory:${NC} $SCRIPT_DIR"
echo -e "${CYAN}📄 Compose File:     ${NC} $COMPOSE_FILE"

# Check & Source .env file
if [[ -f ".env" ]]; then
    echo -e "${CYAN}⚙️  Configuration:    ${NC} Loaded .env"
    set -a
    # shellcheck disable=SC1091
    source <(grep -v '^\s*#' .env | grep -v '^\s*$') 2>/dev/null || true
    set +a
else
    echo -e "${YELLOW}⚠️  Note: .env file not found. Sourcing system environment & defaults.${NC}"
fi

# Set safe defaults for compose interpolation if not set
export PUID="${PUID:-$(id -u 2>/dev/null || echo 1000)}"
export PGID="${PGID:-$(id -g 2>/dev/null || echo 1000)}"
export TZ="${TZ:-Etc/UTC}"
export CONFIG_PATH="${CONFIG_PATH:-$HOME/.config/media-stack/qbittorrent}"
export CONFIG_ROOT="${CONFIG_ROOT:-$HOME/.config/media-stack}"
export MEDIA_PATH="${MEDIA_PATH:-$HOME/Downloads}"
export VPN_ENABLED="${VPN_ENABLED:-no}"
export VPN_CLIENT="${VPN_CLIENT:-wireguard}"
export VPN_PROV="${VPN_PROV:-custom}"
export LAN_NETWORK="${LAN_NETWORK:-192.168.1.0/24}"

# Component Pre-flight Check
echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  🔍 Pre-flight Component & Service Inspection                      ${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Extract all services defined in compose file
mapfile -t SERVICES < <(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)

if [[ ${#SERVICES[@]} -eq 0 ]]; then
    # Fallback to parsing YAML directly if config --services fails
    mapfile -t SERVICES < <(grep -E '^[[:space:]]{2}[a-zA-Z0-9_-]+:' "$COMPOSE_FILE" | grep -v 'services:' | sed 's/://g' | xargs -n1)
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ Could not parse any services from $COMPOSE_FILE.${NC}"
    exit 1
fi

TOTAL_SERVICES=${#SERVICES[@]}
RUNNING_SERVICES=()
STOPPED_SERVICES=()
UNCREATED_SERVICES=()

for svc in "${SERVICES[@]}"; do
    cid=$(docker compose -f "$COMPOSE_FILE" ps -a -q "$svc" 2>/dev/null)
    if [[ -n "$cid" ]]; then
        status=$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null)
        if [[ "$status" == "running" ]]; then
            RUNNING_SERVICES+=("$svc")
        else
            STOPPED_SERVICES+=("$svc ($status)")
        fi
    else
        UNCREATED_SERVICES+=("$svc")
    fi
done

echo -e "Total Components Defined: ${BOLD}$TOTAL_SERVICES${NC}"
echo -e "  🟢 Currently Running:    ${#RUNNING_SERVICES[@]} (${RUNNING_SERVICES[*]:-none})"
echo -e "  🟡 Stopped/Exited:       ${#STOPPED_SERVICES[@]} (${STOPPED_SERVICES[*]:-none})"
echo -e "  ⚪ Not Yet Created:      ${#UNCREATED_SERVICES[@]} (${UNCREATED_SERVICES[*]:-none})"

# Check if ALREADY fully running
if [[ ${#RUNNING_SERVICES[@]} -eq $TOTAL_SERVICES ]]; then
    echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  ✅ All components of the media stack are ALREADY running!          ${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}Active Services & Status:${NC}"
    docker compose -f "$COMPOSE_FILE" ps
    
    echo -e "\n${CYAN}Current Resource Consumption:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}"
    
    echo -e "\n${DIM}Nothing to start. Use stop-stack.sh if you wish to halt the stack.${NC}"
    exit 0
fi

# Starting Required Components
echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  🚀 Starting Media Stack                                           ${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}The following Docker command will now be executed:${NC}"
echo -e "${BOLD}${GREEN}+ docker compose -f $COMPOSE_FILE up -d${NC}\n"

docker compose -f "$COMPOSE_FILE" up -d

# Initialization grace period (3 seconds)
echo -e "\n${CYAN}⏳ Waiting for services to initialize...${NC}"
for ((i=3; i>=1; i--)); do
    printf "\r${DIM}Inspecting service health in %d seconds...${NC}" "$i"
    sleep 1
done
echo -e "\r                                                    "

# Post-Startup Verification
echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  📊 Post-Startup Status & Web UI Access                            ${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

docker compose -f "$COMPOSE_FILE" ps

# Detect Host IP for convenient URL links
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_IP="${HOST_IP:-localhost}"

echo -e "\n${BOLD}Service Access URLs:${NC}"
for svc in "${SERVICES[@]}"; do
    case "$svc" in
        *qbittorrent*)
            echo -e "  📥 ${BOLD}qBittorrent Web UI:${NC} http://${HOST_IP}:8080 (or http://localhost:8080)"
            ;;
        *radarr*)
            echo -e "  🎬 ${BOLD}Radarr Web UI:     ${NC} http://${HOST_IP}:7878"
            ;;
        *sonarr*)
            echo -e "  📺 ${BOLD}Sonarr Web UI:     ${NC} http://${HOST_IP}:8989"
            ;;
        *prowlarr*)
            echo -e "  🔍 ${BOLD}Prowlarr Web UI:   ${NC} http://${HOST_IP}:9696"
            ;;
        *lidarr*)
            echo -e "  🎵 ${BOLD}Lidarr Web UI:     ${NC} http://${HOST_IP}:8686"
            ;;
        *readarr*)
            echo -e "  📚 ${BOLD}Readarr Web UI:    ${NC} http://${HOST_IP}:8787"
            ;;
        *bazarr*)
            echo -e "  💬 ${BOLD}Bazarr Web UI:     ${NC} http://${HOST_IP}:6767"
            ;;
        *)
            echo -e "  📦 ${BOLD}${svc}:${NC} Active"
            ;;
    esac
done

echo -e "\n${CYAN}Initial Resource Baseline:${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null || true

echo -e "\n${GREEN}🚀 Media stack startup sequence complete!${NC}"
