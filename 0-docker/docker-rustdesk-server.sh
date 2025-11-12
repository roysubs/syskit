#!/bin/bash
# Author: Roy Wiseman (template style), Gemini (RustDesk implementation) 2025-11
#
# RustDesk Server Docker automated deployment script.
# Creates a complete, private, self-hosted remote desktop relay.
# IDEMPOTENT: Safe to run multiple times!
# https://rustdesk.com/docs/en/self-host/
# ────────────────────────────────────────────────────────────────

set -e # Exit on error

# ───[ Styling ]───────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ───[ Configuration ]─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_DIR="$HOME/.config/rustdesk-server"
# Store compose and env files in config directory
COMPOSE_FILE="" # Will be set after CONFIG_DIR is determined
ENV_FILE=""     # Will be set after CONFIG_DIR is determined
DATA_DIR=""     # Will be set after CONFIG_DIR is determined

# ───[ Helper Functions ]──────────────────────────────────────────
check_dependencies() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}     RustDesk Self-Hosted Server Setup${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}[1/9] Checking dependencies...${NC}"

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker not found. Please install Docker to continue.${NC}"
        echo "You can usually install it with: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
        exit 1
    fi

    if ! command -v docker compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose not found. Please install Docker Compose.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ All dependencies met.${NC}"
    echo
}

check_existing_installation() {
    echo -e "${CYAN}[2/9] Checking for existing installation...${NC}"

    # Check if containers exist
    if docker ps -a --format '{{.Names}}' | grep -E '^(hbbs|hbbr)$' &>/dev/null; then
        echo -e "${YELLOW}⚠️  Existing RustDesk installation detected!${NC}"
        echo
        docker ps -a --filter "name=hbbs" --filter "name=hbbr" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
        echo -e "${BOLD}What would you like to do?${NC}"
        echo -e "  ${CYAN}1)${NC} Keep existing installation and exit"
        echo -e "  ${CYAN}2)${NC} Rebuild containers (pulls new images, preserves data/keys)"
        echo -e "  ${CYAN}3)${NC} Complete teardown and fresh install (KEEPS config files, DELETES keys)"
        echo -e "  ${CYAN}4)${NC} Nuclear option: Delete EVERYTHING including config/keys (⚠️  DANGER!)"
        echo
        read -p "Enter choice [1-4]: " rebuild_choice

        case $rebuild_choice in
            1)
                echo -e "${GREEN}✅ Keeping existing installation. Exiting.${NC}"
                exit 0
                ;;
            2)
                echo -e "${YELLOW}🔄 Rebuilding containers (preserving data/keys)...${NC}"
                # Stop using docker-compose from config dir if it exists
                if [ -f "$DEFAULT_CONFIG_DIR/docker-compose.yml" ]; then
                    cd "$DEFAULT_CONFIG_DIR" && docker compose down --remove-orphans 2>/dev/null || true
                fi
                docker stop hbbs hbbr 2>/dev/null || true
                docker rm hbbs hbbr 2>/dev/null || true
                REBUILD_MODE="rebuild"
                ;;
            3)
                echo -e "${YELLOW}🔄 Complete teardown (deleting keys for fresh start)...${NC}"
                if [ -f "$DEFAULT_CONFIG_DIR/docker-compose.yml" ]; then
                    cd "$DEFAULT_CONFIG_DIR" && docker compose down --remove-orphans 2>/dev/null || true
                fi
                docker stop hbbs hbbr 2>/dev/null || true
                docker rm hbbs hbbr 2>/dev/null || true

                # Clean key data to force regeneration
                if [ -d "$DEFAULT_CONFIG_DIR/data" ]; then
                    echo -e "${YELLOW}Removing old key files for fresh start...${NC}"
                    sudo rm -f "$DEFAULT_CONFIG_DIR/data"/*id_ed25519*
                fi
                REBUILD_MODE="fresh"
                ;;
            4)
                echo -e "${RED}⚠️  NUCLEAR OPTION: This will delete ALL data and config!${NC}"
                read -p "Are you ABSOLUTELY sure? Type 'DELETE EVERYTHING' to confirm: " confirm
                if [ "$confirm" = "DELETE EVERYTHING" ]; then
                    echo -e "${RED}💣 Deleting everything...${NC}"
                    if [ -f "$DEFAULT_CONFIG_DIR/docker-compose.yml" ]; then
                        cd "$DEFAULT_CONFIG_DIR" && docker compose down -v --remove-orphans 2>/dev/null || true
                    fi
                    docker stop hbbs hbbr 2>/dev/null || true
                    docker rm hbbs hbbr 2>/dev/null || true
                    sudo rm -rf "$DEFAULT_CONFIG_DIR"
                    REBUILD_MODE="nuclear"
                else
                    echo -e "${GREEN}Aborted. Exiting.${NC}"
                    exit 0
                fi
                ;;
            *)
                echo -e "${RED}Invalid choice. Exiting.${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}✅ No existing installation found. Proceeding with fresh install.${NC}"
        REBUILD_MODE="fresh"
    fi
    echo
}

detect_environment() {
    echo -e "${CYAN}[3/9] Detecting environment...${NC}"

    # Detect local IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        echo -e "${YELLOW}⚠️  Could not detect local IP. Using 'localhost'.${NC}"
        LOCAL_IP="localhost"
    else
        echo -e "${GREEN}✅ Detected local IP: ${LOCAL_IP}${NC}"
    fi
    echo
}

setup_domain() {
    echo -e "${CYAN}[4/9] Configuring domain...${NC}"

    echo -e "${BOLD}What public domain or IP will your clients use to connect?${NC}"
    echo -e "This server MUST be reachable on this address."
    echo -e "Example: ${CYAN}rustdesk.yourdomain.com${NC} or ${CYAN}1.2.3.4${NC}"
    echo
    echo -e "${YELLOW}💡 Yes, you can use your DuckDNS domain!${NC}"
    echo -e "Just enter it below (e.g., ${CYAN}my-nextcloud.duckdns.org${NC})"
    echo
    
    read -p "Enter your public domain or IP: " SERVER_DOMAIN
    if [ -z "$SERVER_DOMAIN" ]; then
        echo -e "${RED}❌ Domain/IP cannot be empty. Exiting.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Server address set to: ${SERVER_DOMAIN}${NC}"
    echo
}

gather_directories() {
    echo -e "${CYAN}[5/9] Configuring storage directories...${NC}"

    echo -e "${BOLD}Where should RustDesk store its configuration and keys?${NC}"
    echo

    read -e -p "Config directory [${DEFAULT_CONFIG_DIR}]: " config_input
    CONFIG_DIR="${config_input:-$DEFAULT_CONFIG_DIR}"
    CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
    DATA_DIR="${CONFIG_DIR}/data" # Data (keys) will live inside the config dir

    # Set paths for compose and env files
    COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
    ENV_FILE="${CONFIG_DIR}/.env"

    echo -e "${GREEN}✅ Config: ${CONFIG_DIR}${NC}"
    echo -e "${GREEN}✅ Data:   ${DATA_DIR}${NC}"

    # Create directories
    mkdir -p "$DATA_DIR"

    echo -e "${GREEN}✅ Directories created.${NC}"
    echo
}

setup_server_keys() {
    echo -e "${CYAN}[6/9] Configuring server keys (for High Availability)...${NC}"
    echo
    echo -e "${BOLD}Is this your first (primary) server or a secondary server?${NC}"
    echo -e "  ${CYAN}1)${NC} ${BOLD}Primary Server${NC} (This will generate NEW keys)"
    echo -e "  ${CYAN}2)${NC} ${BOLD}Secondary (HA) Server${NC} (This will IMPORT keys from your primary)"
    echo
    echo -e "For load balancing, all servers must use the ${BOLD}same${NC} key files."
    echo

    read -p "Enter choice [1-2]: " key_choice

    KEY_ACTION=""

    case $key_choice in
        1)
            echo -e "${GREEN}✅ Setting up as Primary Server.${NC}"
            echo -e "New keys will be generated in ${CYAN}${DATA_DIR}${NC} on first launch."
            KEY_ACTION="generated"
            ;;
        2)
            echo -e "${YELLOW}🔄 Setting up as Secondary (HA) Server.${NC}"
            echo -e "You must copy ${BOLD}id_ed25519${NC} and ${BOLD}id_ed25519.pub${NC} from your primary server."
            echo
            read -e -p "Enter full path to your primary 'id_ed25519' (private) key file: " KEY_FILE_PRIV
            read -e -p "Enter full path to your primary 'id_ed25519.pub' (public) key file: " KEY_FILE_PUB

            if [ ! -f "$KEY_FILE_PRIV" ] || [ ! -f "$KEY_FILE_PUB" ]; then
                echo -e "${RED}❌ Key files not found at specified paths. Exiting.${NC}"
                exit 1
            fi

            cp "$KEY_FILE_PRIV" "$DATA_DIR/id_ed25519"
            cp "$KEY_FILE_PUB" "$DATA_DIR/id_ed25519.pub"
            
            echo -e "${GREEN}✅ Existing keys imported successfully to ${DATA_DIR}${NC}"
            KEY_ACTION="imported"
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
    echo
}

create_env_file() {
    echo -e "${CYAN}[7/9] Creating environment configuration...${NC}"

    cat > "$ENV_FILE" << EOF
# RustDesk Server Configuration
# Generated: $(date)

# Public-facing domain or IP
SERVER_DOMAIN=${SERVER_DOMAIN}

# Directories
CONFIG_DIR=${CONFIG_DIR}
DATA_DIR=${DATA_DIR}

# Key setup action
KEY_ACTION=${KEY_ACTION}
EOF

    echo -e "${GREEN}✅ Environment file created.${NC}"
    echo
}

create_docker_compose() {
    echo -e "${CYAN}[8/9] Creating Docker Compose configuration...${NC}"

    cat > "$COMPOSE_FILE" << 'EOF'
version: '3'

services:
  # ───[ RustDesk ID/Signaling Server ]───────────────────────────
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs
    volumes:
      - ${DATA_DIR}:/root
    network_mode: "host" # Recommended for performance
    depends_on:
      - hbbr
    restart: unless-stopped

  # ───[ RustDesk Relay Server ]──────────────────────────────────
  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ${DATA_DIR}:/root
    network_mode: "host"
    restart: unless-stopped

# network_mode: "host" means the containers use the host's network
# stack directly. This is the simplest and most performant option.
# It uses ports 21115, 21116(tcp/udp), 21117, 21118, 21119.
EOF

    echo -e "${GREEN}✅ Docker Compose file created.${NC}"
    echo
}

launch_stack() {
    echo -e "${CYAN}[9/9] Launching the RustDesk server stack...${NC}"
    echo -e "${YELLOW}This may take a minute...${NC}"
    echo

    # Change to config directory where docker-compose.yml and .env are located
    cd "$CONFIG_DIR"

    # Pull new images if rebuilding
    if [ "$REBUILD_MODE" = "rebuild" ]; then
        echo -e "${CYAN}Pulling latest images...${NC}"
        docker compose --env-file "$ENV_FILE" pull
    fi

    docker compose --env-file "$ENV_FILE" up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Stack launched successfully!${NC}"
        if [ "$KEY_ACTION" = "generated" ]; then
            echo -e "${CYAN}Waiting 10 seconds for server to start and generate keys...${NC}"
            sleep 10
        else
            sleep 3
        fi
    else
        echo -e "${RED}❌ Failed to launch stack. Check Docker logs.${NC}"
        echo -e "${YELLOW}Common issue: Ports 21115-21119 are already in use by another service.${NC}"
        exit 1
    fi
    echo
}

show_final_instructions() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    🎉 Setup Complete! 🎉${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}YOUR SERVER IS NOW RUNNING.${NC}"
    echo

    KEY_FILE_PUB="${DATA_DIR}/id_ed25519.pub"
    
    if [ ! -f "$KEY_FILE_PUB" ]; then
        echo -e "${RED}❌ CRITICAL ERROR: Key file not found!${NC}"
        echo -e "${RED}Could not find public key at: ${KEY_FILE_PUB}${NC}"
        echo -e "Check 'docker logs hbbs' for errors."
        exit 1
    fi

    PUBLIC_KEY=$(cat "$KEY_FILE_PUB")

    echo -e "${BOLD}🔑 Client Configuration (MANDATORY):${NC}"
    echo -e "You must configure all your RustDesk clients to use this server."
    echo
    echo -e "1. Open RustDesk on your client computer."
    echo -e "2. Click the ${CYAN}Menu (…)${NC} button next to your ID."
    echo -e "3. Go to ${CYAN}Network${NC} -> ${CYAN}Unlock Network Settings${NC}."
    echo -e "4. Fill in these ${BOLD}TWO${NC} fields:"
    echo
    echo -e "   ${BOLD}ID Server:${NC} ${YELLOW}${SERVER_DOMAIN}${NC}"
    echo
    echo -e "   ${BOLD}Key:${NC}         ${YELLOW}${PUBLIC_KEY}${NC}"
    echo
    echo -e "5. Leave 'Relay Server' blank (it will use the ID Server setting)."
    echo -e "6. Click ${CYAN}Apply${NC}. You should see 'Ready' with a green dot."
    echo

    echo -e "${BOLD}🔒 Port Forwarding Check:${NC}"
    echo -e "For external access, ensure you have forwarded these ports on your router"
    echo -e "to this server's ${BOLD}LOCAL IP:${NC} ${CYAN}${LOCAL_IP}${NC}"
    echo -e "  •  TCP: ${YELLOW}21115, 21116, 21117, 21118, 21119${NC}"
    echo -e "  •  UDP: ${YELLOW}21116${NC}"
    echo

    echo -e "${BOLD}⚖️ High Availability / Load Balancing:${NC}"
    if [ "$KEY_ACTION" = "generated" ]; then
        echo -e "To add a second server, run this script on another machine and"
        echo -e "choose option ${CYAN}2 (Secondary Server)${NC}. You will need these key files:"
        echo -e "  •  Private: ${CYAN}${DATA_DIR}/id_ed25519${NC}"
        echo -e "  •  Public:  ${CYAN}${DATA_DIR}/id_ed25519.pub${NC}"
    else
        echo -e "✅ This server was set up as a Secondary (HA) server."
        echo -e "You can now add this server's IP (${CYAN}${LOCAL_IP}${NC}) to your load balancer."
    fi
    echo

    echo -e "${BOLD}🛠  Maintenance & Management:${NC}"
    echo
    echo -e "${CYAN}Manage containers:${NC}"
    echo -e "  cd ${CONFIG_DIR}"
    echo -e "  docker compose stop"
    echo -e "  docker compose start"
    echo -e "  docker compose restart"
    echo -e "  docker compose down"
    echo
    echo -e "${CYAN}Update RustDesk Server:${NC}"
    echo -e "  cd ${CONFIG_DIR}"
    echo -e "  docker compose pull"
    echo -e "  docker compose up -d"
    echo
    echo -e "${CYAN}View logs:${NC}"
    echo -e "  docker logs hbbs -f"
    echo -e "  docker logs hbbr -f"
    echo
    echo -e "${GREEN}${BOLD}Enjoy your private, nag-free remote desktop server! 🖥️${NC}"
    echo
}

# ───[ Main Execution ]────────────────────────────────────────────
main() {
    check_dependencies
    check_existing_installation
    detect_environment
    setup_domain
    gather_directories
    setup_server_keys
    create_env_file
    create_docker_compose
    launch_stack
    show_final_instructions
}

main "$@"
