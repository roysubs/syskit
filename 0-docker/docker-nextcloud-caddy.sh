#!/bin/bash
# Author: Roy Wiseman (template style), Claude (Nextcloud+Caddy implementation) 2025-10
#
# Nextcloud + Caddy Docker automated deployment script.
# Creates a complete, secure personal cloud with automatic HTTPS.
# Supports both DuckDNS (free) and custom domains.
# IDEMPOTENT: Safe to run multiple times!
# https://docs.nextcloud.com/
# https://caddyserver.com/
# ────────────────────────────────────────────────────────────────

set -e  # Exit on error

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
DEFAULT_CONFIG_DIR="$HOME/.config/nextcloud-stack"
DEFAULT_DATA_DIR="$HOME/nextcloud-data"
# Store compose and env files in config directory to keep repo clean
COMPOSE_FILE=""  # Will be set after CONFIG_DIR is determined
ENV_FILE=""      # Will be set after CONFIG_DIR is determined

# ───[ Helper Functions ]──────────────────────────────────────────
check_dependencies() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}   Nextcloud + Caddy Personal Cloud Setup${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}[1/10] Checking dependencies...${NC}"
    
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
    echo -e "${CYAN}[2/10] Checking for existing installation...${NC}"
    
    # Check if containers exist
    if docker ps -a --format '{{.Names}}' | grep -E '^(nextcloud|caddy|nextcloud-postgres|nextcloud-redis)$' &>/dev/null; then
        echo -e "${YELLOW}⚠️  Existing Nextcloud installation detected!${NC}"
        echo
        docker ps -a --filter "name=nextcloud" --filter "name=caddy" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
        echo -e "${BOLD}What would you like to do?${NC}"
        echo -e "  ${CYAN}1)${NC} Keep existing installation and exit"
        echo -e "  ${CYAN}2)${NC} Rebuild containers (preserves data and config)"
        echo -e "  ${CYAN}3)${NC} Complete teardown and fresh install (KEEPS data/config files)"
        echo -e "  ${CYAN}4)${NC} Nuclear option: Delete EVERYTHING including data (⚠️  DANGER!)"
        echo
        read -p "Enter choice [1-4]: " rebuild_choice
        
        case $rebuild_choice in
            1)
                echo -e "${GREEN}✅ Keeping existing installation. Exiting.${NC}"
                exit 0
                ;;
            2)
                echo -e "${YELLOW}🔄 Rebuilding containers (preserving data)...${NC}"
                # Stop using docker-compose from config dir if it exists
                if [ -f "$DEFAULT_CONFIG_DIR/docker-compose.yml" ]; then
                    cd "$DEFAULT_CONFIG_DIR" && docker compose down --remove-orphans 2>/dev/null || true
                fi
                docker stop nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                docker rm nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                REBUILD_MODE="rebuild"
                ;;
            3)
                echo -e "${YELLOW}🔄 Complete teardown (preserving data/config)...${NC}"
                if [ -f "$DEFAULT_CONFIG_DIR/docker-compose.yml" ]; then
                    cd "$DEFAULT_CONFIG_DIR" && docker compose down --remove-orphans 2>/dev/null || true
                fi
                docker stop nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                docker rm nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                
                # Clean postgres data to force fresh database
                if [ -d "$DEFAULT_CONFIG_DIR/postgres" ]; then
                    echo -e "${YELLOW}Removing old database files for fresh start...${NC}"
                    sudo rm -rf "$DEFAULT_CONFIG_DIR/postgres"/*
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
                    docker stop nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                    docker rm nextcloud caddy nextcloud-postgres nextcloud-redis duckdns-updater 2>/dev/null || true
                    sudo rm -rf "$DEFAULT_CONFIG_DIR"
                    sudo rm -rf "$DEFAULT_DATA_DIR"
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
    echo -e "${CYAN}[3/10] Detecting environment...${NC}"
    
    # Detect local IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        echo -e "${YELLOW}⚠️  Could not detect local IP. Using 'localhost'.${NC}"
        LOCAL_IP="localhost"
    else
        echo -e "${GREEN}✅ Detected local IP: ${LOCAL_IP}${NC}"
    fi

    # Detect timezone
    if command -v timedatectl &> /dev/null; then
        TIMEZONE=$(timedatectl show --value -p Timezone)
    else
        TIMEZONE="Europe/Amsterdam"
        echo -e "${YELLOW}⚠️  Could not detect timezone. Using default: ${TIMEZONE}${NC}"
    fi
    echo -e "${GREEN}✅ Timezone: ${TIMEZONE}${NC}"

    # Get PUID/PGID
    PUID=$(id -u)
    PGID=$(id -g)
    echo -e "${GREEN}✅ User permissions: PUID=${PUID}, PGID=${PGID}${NC}"
    echo
}

find_available_port() {
    echo -e "${CYAN}[4/10] Finding available port for direct access...${NC}"
    
    # Try ports 8081-8089
    for port in {8081..8089}; do
        # Check if port is used by Docker containers
        if docker ps --format '{{.Ports}}' | grep -q "0.0.0.0:${port}"; then
            echo -e "${YELLOW}⚠️  Port ${port} is in use by Docker, trying next...${NC}"
            continue
        fi
        
        # Check if port is used by system (netstat or ss)
        if command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
                echo -e "${YELLOW}⚠️  Port ${port} is in use by system, trying next...${NC}"
                continue
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":${port} "; then
                echo -e "${YELLOW}⚠️  Port ${port} is in use by system, trying next...${NC}"
                continue
            fi
        fi
        
        # Port is available!
        NEXTCLOUD_PORT=$port
        echo -e "${GREEN}✅ Found available port: ${NEXTCLOUD_PORT}${NC}"
        return 0
    done
    
    echo -e "${RED}❌ No available ports found between 8081-8089!${NC}"
    echo -e "${YELLOW}Please free up a port or stop conflicting services.${NC}"
    docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "808[1-9]"
    exit 1
}

setup_domain() {
    echo -e "${CYAN}[5/10] Configuring domain settings...${NC}"
    
    echo -e "${BOLD}Domain Configuration:${NC}"
    echo -e "You can use either:"
    echo -e "  ${CYAN}1)${NC} Your own custom domain (e.g., yourdomain.com)"
    echo -e "  ${CYAN}2)${NC} DuckDNS - Free dynamic DNS service"
    echo
    
    read -p "Do you have your own domain? (y/N): " has_domain
    
    if [[ "$has_domain" =~ ^[Yy]$ ]]; then
        # Custom domain
        echo
        read -p "Enter your domain (e.g., yourdomain.com): " CUSTOM_DOMAIN
        if [ -z "$CUSTOM_DOMAIN" ]; then
            echo -e "${RED}❌ Domain cannot be empty. Exiting.${NC}"
            exit 1
        fi
        
        USE_DUCKDNS="no"
        DOMAIN="$CUSTOM_DOMAIN"
        FULL_DOMAIN="cloud.${DOMAIN}"
        echo -e "${GREEN}✅ Using custom domain: ${FULL_DOMAIN}${NC}"
        DUCKDNS_TOKEN=""
        DUCKDNS_SUBDOMAIN=""
    else
        # Use DuckDNS
        echo
        echo -e "${CYAN}Setting up DuckDNS (free dynamic DNS)...${NC}"
        echo
        echo -e "${BOLD}DuckDNS Setup:${NC}"
        echo -e "1. Go to: ${CYAN}https://www.duckdns.org/${NC}"
        echo -e "2. Sign in with any social account (GitHub, Google, etc.)"
        echo -e "3. Create a subdomain (e.g., 'mycloud')"
        echo -e "4. Copy your token from the top of the page"
        echo
        
        read -p "Enter your DuckDNS subdomain (e.g., mycloud): " DUCKDNS_SUBDOMAIN
        if [ -z "$DUCKDNS_SUBDOMAIN" ]; then
            echo -e "${RED}❌ Subdomain cannot be empty. Exiting.${NC}"
            exit 1
        fi
        
        read -p "Enter your DuckDNS token: " DUCKDNS_TOKEN
        if [ -z "$DUCKDNS_TOKEN" ]; then
            echo -e "${RED}❌ Token cannot be empty. Exiting.${NC}"
            exit 1
        fi
        
        USE_DUCKDNS="yes"
        DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"
        FULL_DOMAIN="${DOMAIN}"
        echo -e "${GREEN}✅ DuckDNS configured: ${FULL_DOMAIN}${NC}"
    fi
    echo
}

gather_directories() {
    echo -e "${CYAN}[6/10] Configuring storage directories...${NC}"
    
    echo -e "${BOLD}Where should Nextcloud store its configuration and data?${NC}"
    echo -e "(This includes the database, user files, apps, etc.)"
    echo
    
    read -e -p "Config directory [${DEFAULT_CONFIG_DIR}]: " config_input
    CONFIG_DIR="${config_input:-$DEFAULT_CONFIG_DIR}"
    CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
    
    read -e -p "Data directory [${DEFAULT_DATA_DIR}]: " data_input
    DATA_DIR="${data_input:-$DEFAULT_DATA_DIR}"
    DATA_DIR="${DATA_DIR/#\~/$HOME}"
    
    # Set paths for compose and env files in config directory
    COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
    ENV_FILE="${CONFIG_DIR}/.env"
    
    echo -e "${GREEN}✅ Config: ${CONFIG_DIR}${NC}"
    echo -e "${GREEN}✅ Data: ${DATA_DIR}${NC}"
    echo -e "${GREEN}✅ Docker Compose: ${COMPOSE_FILE}${NC}"
    echo -e "${GREEN}✅ Environment: ${ENV_FILE}${NC}"
    
    # Create directories
    mkdir -p "$CONFIG_DIR"/{nextcloud,postgres,redis,caddy/data,caddy/config}
    mkdir -p "$DATA_DIR"
    
    # Fix postgres permissions
    sudo chown -R 999:999 "$CONFIG_DIR/postgres" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Directories created.${NC}"
    echo
}

generate_passwords() {
    echo -e "${CYAN}[7/10] Generating secure passwords...${NC}"
    
    # Generate random passwords
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    echo -e "${GREEN}✅ Secure passwords generated.${NC}"
    echo
}

create_env_file() {
    echo -e "${CYAN}[8/10] Creating environment configuration...${NC}"
    
    cat > "$ENV_FILE" << EOF
# Nextcloud + Caddy Stack Configuration
# Generated: $(date)

# Domain Configuration
DOMAIN=${FULL_DOMAIN}
USE_DUCKDNS=${USE_DUCKDNS}
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
DUCKDNS_SUBDOMAIN=${DUCKDNS_SUBDOMAIN:-}

# Directories
CONFIG_DIR=${CONFIG_DIR}
DATA_DIR=${DATA_DIR}

# Database
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=${DB_PASSWORD}

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}

# System
TZ=${TIMEZONE}
PUID=${PUID}
PGID=${PGID}

# Nextcloud Port (for direct access)
NEXTCLOUD_PORT=${NEXTCLOUD_PORT}
EOF

    echo -e "${GREEN}✅ Environment file created.${NC}"
    echo
}

create_docker_compose() {
    echo -e "${CYAN}[9/10] Creating Docker Compose configuration...${NC}"
    
    cat > "$COMPOSE_FILE" << 'EOF'
services:
  # ───[ PostgreSQL Database ]─────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    container_name: nextcloud-postgres
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - nextcloud-internal

  # ───[ Redis Cache ]─────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - nextcloud-internal

  # ───[ Nextcloud Application ]───────────────────────────────────
  nextcloud:
    image: nextcloud:30-apache
    container_name: nextcloud
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "${NEXTCLOUD_PORT}:80"
    volumes:
      - ${CONFIG_DIR}/nextcloud:/var/www/html
      - ${DATA_DIR}:/var/www/html/data
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - REDIS_HOST=redis
      - REDIS_HOST_PASSWORD=${REDIS_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${DOMAIN} localhost
      - OVERWRITEPROTOCOL=https
      - OVERWRITEHOST=${DOMAIN}
      - OVERWRITECLIURL=https://${DOMAIN}
      - TZ=${TZ}
    networks:
      - nextcloud-internal
      - caddy-network

  # ───[ Caddy Reverse Proxy ]─────────────────────────────────────
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    depends_on:
      - nextcloud
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${CONFIG_DIR}/caddy/data:/data
      - ${CONFIG_DIR}/caddy/config:/config
    environment:
      - DOMAIN=${DOMAIN}
      - DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
    networks:
      - caddy-network

  # ───[ DuckDNS Updater (Optional) ]──────────────────────────────
  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: duckdns-updater
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - SUBDOMAINS=${DUCKDNS_SUBDOMAIN}
      - TOKEN=${DUCKDNS_TOKEN}
      - LOG_FILE=false
    profiles:
      - duckdns
    networks:
      - caddy-network

networks:
  nextcloud-internal:
    driver: bridge
  caddy-network:
    driver: bridge
EOF

    echo -e "${GREEN}✅ Docker Compose file created.${NC}"
    echo
}

create_caddyfile() {
    echo -e "${CYAN}Creating Caddy configuration...${NC}"
    
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    email admin@${FULL_DOMAIN}
}

# HTTP with proper ACME challenge handling
http://${FULL_DOMAIN} {
    # Handle ACME HTTP-01 challenges (don't redirect these!)
    handle /.well-known/acme-challenge/* {
        root * /data
        file_server
    }
    
    # Redirect everything else to HTTPS
    redir https://{host}{uri} permanent
}

# HTTPS configuration
${FULL_DOMAIN} {
    reverse_proxy nextcloud:80
    
    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000;"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "no-referrer"
    }
    
    # Handle .well-known paths for Nextcloud
    redir /.well-known/carddav /remote.php/dav 301
    redir /.well-known/caldav /remote.php/dav 301
    
    # Logging
    log {
        output file /data/access.log
        format json
    }
}
EOF
    
    echo -e "${GREEN}✅ Caddyfile created.${NC}"
    echo
}

launch_stack() {
    echo -e "${CYAN}[10/10] Launching the cloud stack...${NC}"
    echo -e "${YELLOW}This may take a few minutes on first run...${NC}"
    echo
    
    # Change to config directory where docker-compose.yml and .env are located
    cd "$CONFIG_DIR"
    
    if [ "$USE_DUCKDNS" = "yes" ]; then
        # Launch with DuckDNS updater
        docker compose --env-file "$ENV_FILE" --profile duckdns up -d
    else
        # Launch without DuckDNS updater
        docker compose --env-file "$ENV_FILE" up -d
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Stack launched successfully!${NC}"
        echo -e "${CYAN}Waiting 20 seconds for services to initialize...${NC}"
        sleep 20
    else
        echo -e "${RED}❌ Failed to launch stack. Check Docker logs.${NC}"
        exit 1
    fi
    echo
    
    # Run Nextcloud upgrade
    echo -e "${CYAN}Running Nextcloud upgrade (if needed)...${NC}"
    docker exec -u www-data nextcloud php occ upgrade 2>&1 | tee /tmp/nextcloud-upgrade.log
    
    if grep -q "Nextcloud is already latest version" /tmp/nextcloud-upgrade.log; then
        echo -e "${GREEN}✅ Nextcloud is up to date${NC}"
    elif grep -q "Update successful" /tmp/nextcloud-upgrade.log; then
        echo -e "${GREEN}✅ Nextcloud upgraded successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Upgrade completed - check output above for details${NC}"
    fi
    echo
}

check_port_forwarding() {
    echo -e "${CYAN}Checking port forwarding status...${NC}"
    echo
    
    echo -e "${BOLD}Required port forwards on your router:${NC}"
    echo -e "  Port ${YELLOW}80${NC}  (HTTP)  → ${LOCAL_IP}:80"
    echo -e "  Port ${YELLOW}443${NC} (HTTPS) → ${LOCAL_IP}:443"
    echo
    
    echo -e "${CYAN}Testing external accessibility...${NC}"
    
    # Basic local checks
    if command -v nc &> /dev/null; then
        if nc -z -w5 localhost 80 2>/dev/null; then
            echo -e "${GREEN}✅ Port 80 is listening locally${NC}"
        else
            echo -e "${RED}⚠️  Port 80 not listening${NC}"
        fi
        
        if nc -z -w5 localhost 443 2>/dev/null; then
            echo -e "${GREEN}✅ Port 443 is listening locally${NC}"
        else
            echo -e "${RED}⚠️  Port 443 not listening${NC}"
        fi
    fi
    
    echo
    echo -e "${YELLOW}Note: External port testing requires the domain to propagate first.${NC}"
    echo -e "${YELLOW}Give it 5-10 minutes, then test: http://${FULL_DOMAIN}${NC}"
    echo
}

show_final_instructions() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    🎉 Setup Complete! 🎉${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    
    echo -e "${BOLD}🔐 First-Time Setup:${NC}"
    echo -e "1. Visit your Nextcloud URL (below)"
    echo -e "2. Create your admin account"
    echo -e "3. The database is pre-configured with PostgreSQL"
    echo -e "4. Complete the setup wizard"
    echo
    
    echo -e "${BOLD}🛠  Maintenance & Management:${NC}"
    echo
    echo -e "${CYAN}Update Nextcloud:${NC}"
    echo -e "  cd ${CONFIG_DIR}"
    echo -e "  docker compose pull nextcloud"
    echo -e "  docker compose up -d nextcloud"
    echo -e "  docker exec -u www-data nextcloud php occ upgrade"
    echo
    echo -e "${CYAN}Check for new Docker images:${NC}"
    echo -e "  Visit: ${YELLOW}https://hub.docker.com/_/nextcloud/tags${NC}"
    echo -e "  Or run: ${YELLOW}docker search nextcloud${NC}"
    echo
    echo -e "${CYAN}Repair Nextcloud (if issues occur):${NC}"
    echo -e "  docker exec -u www-data nextcloud php occ maintenance:repair"
    echo
    echo -e "${CYAN}View logs:${NC}"
    echo -e "  docker logs nextcloud -f"
    echo -e "  docker logs caddy -f"
    echo -e "  cd ${CONFIG_DIR} && docker compose logs -f"
    echo
    echo -e "${CYAN}Manage containers:${NC}"
    echo -e "  cd ${CONFIG_DIR}"
    echo -e "  docker compose stop"
    echo -e "  docker compose start"
    echo -e "  docker compose restart"
    echo -e "  docker compose down"
    echo
    echo -e "${CYAN}Re-run this setup script:${NC}"
    echo -e "  ${SCRIPT_DIR}/$(basename "$0")"
    echo -e "  ${YELLOW}(Idempotent - safe to run multiple times!)${NC}"
    echo
    
    echo -e "${BOLD}📁 Important Directories:${NC}"
    echo -e "  Config: ${CYAN}${CONFIG_DIR}${NC}"
    echo -e "  Data:   ${CYAN}${DATA_DIR}${NC}"
    echo
    
    if [ "$USE_DUCKDNS" = "yes" ]; then
        echo -e "${BOLD}🦆 DuckDNS:${NC}"
        echo -e "  Your domain updates automatically every 5 minutes"
        echo -e "  If your IP changes, the domain follows automatically"
        echo
    fi
    
    echo -e "${BOLD}🔒 Security:${NC}"
    echo -e "  ✅ HTTPS with automatic SSL (via Let's Encrypt + Caddy)"
    echo -e "  ✅ Database passwords in ${CYAN}${ENV_FILE}${NC}"
    echo -e "  ✅ Enable 2FA in: Nextcloud → Settings → Security"
    echo
    
    echo -e "${BOLD}🚀 Adding More Services:${NC}"
    echo -e "  Edit: ${CYAN}${CONFIG_DIR}/caddy/Caddyfile${NC}"
    echo -e "  Add new service blocks, then: ${CYAN}docker compose restart caddy${NC}"
    echo
    
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    📍 Connect to Your Cloud${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}🌐 Web Access:${NC}"
    echo -e "  ${YELLOW}https://${FULL_DOMAIN}${NC}"
    echo -e "  ${CYAN}http://${LOCAL_IP}:${NEXTCLOUD_PORT}${NC} (local network only)"
    echo
    echo -e "${BOLD}💻 Desktop Apps:${NC}"
    echo -e "  Download from: ${CYAN}https://nextcloud.com/install/#install-clients${NC}"
    echo -e "  Available for: Windows, macOS, Linux"
    echo
    echo -e "${BOLD}📱 Mobile Apps:${NC}"
    echo -e "  iOS:     Search 'Nextcloud' in App Store"
    echo -e "  Android: Search 'Nextcloud' in Play Store"
    echo
    echo -e "${BOLD}👥 Sharing with Friends:${NC}"
    echo -e "  • Create accounts: Settings → Users"
    echo -e "  • Share links: Right-click any file → Share"
    echo
    echo -e "${GREEN}${BOLD}Welcome to your personal cloud! 🌥️${NC}"
    echo
}

# ───[ Main Execution ]────────────────────────────────────────────
main() {
    check_dependencies
    check_existing_installation
    detect_environment
    find_available_port
    setup_domain
    gather_directories
    generate_passwords
    create_env_file
    create_caddyfile
    create_docker_compose
    launch_stack
    check_port_forwarding
    show_final_instructions
}

main "$@"
