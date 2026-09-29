#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-09
# Media Stack Stop Script with 15-Second Diagnostics & Command Visibility

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
echo -e "${BOLD}${BLUE}               Media Stack - Graceful Stop & Diagnostics            ${NC}"
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

# Source .env if present
if [[ -f ".env" ]]; then
    echo -e "${CYAN}⚙️  Configuration:    ${NC} Loaded .env"
    set -a
    # shellcheck disable=SC1091
    source <(grep -v '^\s*#' .env | grep -v '^\s*$') 2>/dev/null || true
    set +a
fi

# Query stack containers
mapfile -t RUNNING_CONTAINERS < <(docker compose -f "$COMPOSE_FILE" ps --status running -q 2>/dev/null)
mapfile -t ALL_CONTAINERS < <(docker compose -f "$COMPOSE_FILE" ps -a -q 2>/dev/null)

if [[ ${#RUNNING_CONTAINERS[@]} -eq 0 ]]; then
    echo -e "\n${GREEN}ℹ️  The media stack is already stopped. No running containers found.${NC}"
    if [[ ${#ALL_CONTAINERS[@]} -gt 0 ]]; then
        echo -e "\n${DIM}Existing stopped containers:${NC}"
        docker compose -f "$COMPOSE_FILE" ps -a
    fi
    exit 0
fi

# Display currently running containers
echo -e "\n${YELLOW}Active running containers (${#RUNNING_CONTAINERS[@]} found):${NC}"
docker compose -f "$COMPOSE_FILE" ps --status running

# 15-Second Diagnostics Phase
echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  📊 15-Second Pre-Stop Diagnostics (CPU, RAM, Network, Disk I/O)    ${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${DIM}Capturing resource usage across active containers for 15 seconds...${NC}\n"

# Helper function to get stats snapshot
print_stats_snapshot() {
    local label="$1"
    echo -e "${BOLD}${YELLOW}── Snapshot: $label ──${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" "${RUNNING_CONTAINERS[@]}" 2>/dev/null
    echo ""
}

# Initial Snapshot (T = 0s)
print_stats_snapshot "T = 0s (Initial Reading)"

# Countdown loop with visual progress bar (15 seconds total)
for ((s=1; s<=15; s++)); do
    filled=$((s))
    empty=$((15 - s))
    bar=""
    for ((b=0; b<filled; b++)); do bar+="■"; done
    for ((b=0; b<empty; b++)); do bar+="□"; done
    
    printf "\r${CYAN}⏳ Monitoring: [${bar}] %2d/15s elapsed...${NC}" "$s"
    sleep 1
    
    # Midpoint Snapshot at 7s
    if [[ $s -eq 7 ]]; then
        echo -e "\r                                                               "
        print_stats_snapshot "T = 7s (Midpoint Reading)"
    fi
done

echo -e "\r                                                               "
print_stats_snapshot "T = 15s (Final Reading)"

# Show and Execute Stop Command
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  🛑 Executing Graceful Stop                                        ${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}The following Docker command will now be executed:${NC}"
echo -e "${BOLD}${GREEN}+ docker compose -f $COMPOSE_FILE stop${NC}\n"

docker compose -f "$COMPOSE_FILE" stop

# Verification Check
echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  🔍 Post-Stop Verification                                         ${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

mapfile -t STILL_RUNNING < <(docker compose -f "$COMPOSE_FILE" ps --status running -q 2>/dev/null)

if [[ ${#STILL_RUNNING[@]} -eq 0 ]]; then
    echo -e "${GREEN}✅ All media stack containers have cleanly stopped.${NC}"
    echo -e "${DIM}Container state and persistent configurations have been preserved.${NC}"
    docker compose -f "$COMPOSE_FILE" ps
else
    echo -e "${RED}⚠️  Warning: Some containers are still running:${NC}"
    docker compose -f "$COMPOSE_FILE" ps --status running
    echo -e "${YELLOW}You can force-stop them if needed with: docker compose -f $COMPOSE_FILE kill${NC}"
    exit 1
fi
