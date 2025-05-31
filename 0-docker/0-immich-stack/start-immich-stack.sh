#!/bin/bash
# Author: Roy Wiseman 2025-03

# Color Codes
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\033[0m' # No Color

# --- Script Configuration ---
IMMICH_VERSION="release" # You can pin this to a specific version like "v1.107.0" if desired

# --- Helper Functions ---

# Function to display a section header
header() {
    echo -e "\n${BOLD}${BLUE}=====================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}=====================================================${NC}\n"
}

# Function to ask a question with a default value
ask() {
    local prompt default_value
    prompt="$1"
    default_value="$2"
    if [ -n "$default_value" ]; then
        read -p "$(echo -e "${CYAN}${prompt} [default: ${YELLOW}${default_value}${NC}${CYAN}]: ${NC}")" input_value
        REPLY="${input_value:-$default_value}"
    else
        read -p "$(echo -e "${CYAN}${prompt}: ${NC}")" input_value
        REPLY="$input_value"
    fi
}

# Function to ask a yes/no question
ask_yes_no() {
    local prompt default_answer
    prompt="$1"
    default_answer="$2" # Should be "Y" or "N"

    while true; do
        if [ "$default_answer" == "Y" ]; then
            read -p "$(echo -e "${CYAN}${prompt} (Y/n): ${NC}")" yn
            yn=${yn:-Y}
        elif [ "$default_answer" == "N" ]; then
            read -p "$(echo -e "${CYAN}${prompt} (y/N): ${NC}")" yn
            yn=${yn:-N}
        else
            read -p "$(echo -e "${CYAN}${prompt} (y/n): ${NC}")" yn
        fi

        case $yn in
            [Yy]* ) REPLY="Y"; return 0;;
            [Nn]* ) REPLY="N"; return 0;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}

# Function to generate a random string (for passwords/secrets)
generate_secret() {
    openssl rand -hex 32
}

# Function to check if a port is in use
# Uses ss if available (preferred), otherwise falls back to netstat
check_port() {
    local port_to_check=$1
    local tool_output
    if command -v ss &> /dev/null; then
        tool_output=$(ss -tulnp 2>/dev/null)
    elif command -v netstat &> /dev/null; then
        tool_output=$(netstat -tulnp 2>/dev/null)
    else
        echo -e "${YELLOW}⚠️  Cannot check port availability: neither 'ss' nor 'netstat' command found. Assuming port is free.${NC}"
        return 1 # Assume free if tools are missing
    fi

    if echo "$tool_output" | grep -q ":${port_to_check}[[:space:]]"; then
        return 0 # Port is in use
    else
        return 1 # Port is free
    fi
}

# Function to validate a directory path and create if it doesn't exist
validate_and_create_dir() {
    local dir_path_prompt dir_path default_dir_path owner_puid owner_pgid
    dir_path_prompt="$1"
    default_dir_path="$2"
    owner_puid="$3"
    owner_pgid="$4"

    while true; do
        ask "$dir_path_prompt" "$default_dir_path"
        dir_path="$REPLY"
        # Expand tilde
        dir_path_expanded="${dir_path/#\~/$HOME}"

        if [ -z "$dir_path_expanded" ]; then
            echo -e "${RED}Path cannot be empty.${NC}"
            continue
        fi

        if [ ! -d "$dir_path_expanded" ]; then
            echo -e "${YELLOW}Directory '${dir_path_expanded}' does not exist.${NC}"
            ask_yes_no "Create it now?" "Y"
            if [ "$REPLY" == "Y" ]; then
                # Create directory and set permissions
                if mkdir -p "$dir_path_expanded" && chown "${owner_puid}:${owner_pgid}" "$dir_path_expanded"; then
                    echo -e "${GREEN}Directory '$dir_path_expanded' created and ownership set to ${owner_puid}:${owner_pgid}.${NC}"
                    REPLY="$dir_path_expanded" # Return the expanded path
                    return 0
                else
                    echo -e "${RED}❌ Failed to create directory '$dir_path_expanded}' or set permissions.${NC}"
                    echo -e "${YELLOW}Please check your permissions or create it manually with correct ownership:${NC}"
                    echo -e "${YELLOW}mkdir -p \"${dir_path_expanded}\" && sudo chown ${owner_puid}:${owner_pgid} \"${dir_path_expanded}\"${NC}"
                    # Ask to retry or enter a new path
                    ask_yes_no "Do you want to try a different path or re-enter?" "Y"
                    if [ "$REPLY" == "N" ]; then
                        echo -e "${RED}Aborting directory setup.${NC}"
                        return 1
                    fi
                    # Loop will continue for new input
                fi
            else
                echo -e "${YELLOW}Please create the directory manually or choose an existing one.${NC}"
                # Loop will continue for new input
            fi
        elif ! [ -w "$dir_path_expanded" ] || ! [ -r "$dir_path_expanded" ] ; then
             echo -e "${YELLOW}Warning: Current user may not have read/write permissions for $dir_path_expanded.${NC}"
             echo -e "${YELLOW}Ensure the directory is accessible by PUID ${owner_puid} and PGID ${owner_pgid}.${NC}"
             ask_yes_no "Continue anyway?" "N"
             if [[ "$REPLY" == "Y" ]]; then
                REPLY="$dir_path_expanded" # Return the expanded path
                return 0
             fi
             # Loop will continue for new input
        else
            echo -e "${GREEN}Using existing directory: '$dir_path_expanded'. Ensure PUID/PGID ${owner_puid}:${owner_pgid} has access.${NC}"
            REPLY="$dir_path_expanded" # Return the expanded path
            return 0
        fi
    done
}


# --- Main Script Logic ---
clear
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "${BOLD}${GREEN}         Immich Docker Stack Setup Script          ${NC}"
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "\nThis script will guide you through setting up Immich using Docker Compose."
echo -e "It will generate a 'docker-compose.yml' and an '.env' file for your configuration."

# Check if Docker is installed and running
header "Docker Sanity Checks"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    echo -e "${YELLOW}You can try: curl -fsSL https://get.docker.com | sh${NC}"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    if command -v systemctl &> /dev/null && ! systemctl is-active docker --quiet; then
        echo -e "${YELLOW}Attempting to start Docker service...${NC}"
        sudo systemctl start docker
        sleep 3
        if ! docker info &>/dev/null; then
            echo -e "${RED}❌ Failed to start Docker daemon.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Docker daemon started successfully.${NC}"
    else
        exit 1
    fi
fi
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null ; then
    echo -e "${RED}❌ Docker Compose not found. Please install it.${NC}"
    echo -e "${YELLOW}See: https://docs.docker.com/compose/install/${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker and Docker Compose are installed and running.${NC}"

# --- Collect User Input ---

header "User and Permissions Configuration"
default_puid=$(id -u)
default_pgid=$(id -g)
ask "Enter PUID (User ID for file permissions)" "$default_puid"
PUID="$REPLY"
ask "Enter PGID (Group ID for file permissions)" "$default_pgid"
PGID="$REPLY"

header "Timezone Configuration"
default_tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
ask "Enter Timezone (e.g., America/New_York, Europe/Amsterdam)" "$default_tz"
TZ_CONFIG="$REPLY"

header "Immich Data Paths Configuration"
echo -e "${YELLOW}IMPORTANT: Choose paths on a reliable, local filesystem (SSD recommended for database).${NC}"
echo -e "${YELLOW}Do NOT use network shares (NFS, SMB) for the 'DB_DATA_LOCATION'.${NC}"

validate_and_create_dir "Enter host path for your Photos/Videos (UPLOAD_LOCATION)" "$HOME/immich-photos" "$PUID" "$PGID"
if [ $? -ne 0 ]; then exit 1; fi
UPLOAD_LOCATION="$REPLY"

validate_and_create_dir "Enter host path for Immich Database data (DB_DATA_LOCATION)" "$HOME/immich-dbdata" "$PUID" "$PGID"
if [ $? -ne 0 ]; then exit 1; fi
DB_DATA_LOCATION="$REPLY"

validate_and_create_dir "Enter host path for Immich Machine Learning model cache (MODEL_CACHE_LOCATION)" "$HOME/immich-cache" "$PUID" "$PGID"
if [ $? -ne 0 ]; then exit 1; fi
MODEL_CACHE_LOCATION="$REPLY"


header "Network Port Configuration"
DEFAULT_IMMICH_PORT=2283
while true; do
    ask "Enter host port for Immich Web UI" "$DEFAULT_IMMICH_PORT"
    IMMICH_PORT="$REPLY"
    if [[ ! "$IMMICH_PORT" =~ ^[0-9]+$ ]] || [ "$IMMICH_PORT" -lt 1 ] || [ "$IMMICH_PORT" -gt 65535 ]; then
        echo -e "${RED}Invalid port. Please enter a number between 1 and 65535.${NC}"
        continue
    fi
    if check_port "$IMMICH_PORT"; then
        echo -e "${YELLOW}⚠️ Port ${IMMICH_PORT} appears to be in use.${NC}"
        ask_yes_no "Try a different port?" "Y"
        if [ "$REPLY" == "N" ]; then
            echo -e "${RED}Cannot proceed without an available port for Immich. Aborting.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Port ${IMMICH_PORT} for Immich Web UI appears to be free.${NC}"
        break
    fi
done

ask_yes_no "Do you want to expose the PostgreSQL port (5432) on the host? (Not recommended unless you need external access)" "N"
EXPOSE_POSTGRES_PORT="$REPLY"
POSTGRES_HOST_PORT="5432"
if [ "$EXPOSE_POSTGRES_PORT" == "Y" ]; then
    while true; do
        ask "Enter host port for PostgreSQL (if exposing)" "5432"
        POSTGRES_HOST_PORT="$REPLY"
        if [[ ! "$POSTGRES_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$POSTGRES_HOST_PORT" -lt 1 ] || [ "$POSTGRES_HOST_PORT" -gt 65535 ]; then
            echo -e "${RED}Invalid port. Please enter a number between 1 and 65535.${NC}"
            continue
        fi
        if [ "$POSTGRES_HOST_PORT" != "5432" ] && check_port "$POSTGRES_HOST_PORT"; then # Don't warn if it's the default, might be internal
            echo -e "${YELLOW}⚠️ Port ${POSTGRES_HOST_PORT} appears to be in use.${NC}"
            ask_yes_no "Try a different port?" "Y"
            if [ "$REPLY" == "N" ]; then EXPOSE_POSTGRES_PORT="N"; echo -e "${YELLOW}PostgreSQL port will not be exposed.${NC}"; break; fi
        else
            echo -e "${GREEN}✅ Host port for PostgreSQL set to ${POSTGRES_HOST_PORT}.${NC}"
            break
        fi
    done
fi


header "Database Credentials (will be auto-generated if left blank)"
ask "Enter PostgreSQL Database Name" "immich"
DB_DATABASE_NAME="$REPLY"
ask "Enter PostgreSQL Username" "immich"
DB_USERNAME="$REPLY"
ask "Enter PostgreSQL Password (leave blank to auto-generate a strong one)"
DB_PASSWORD="$REPLY"
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(generate_secret)
    echo -e "${GREEN}Generated strong PostgreSQL password.${NC}"
fi

header "Security Secrets (will be auto-generated)"
echo -e "${YELLOW}These will be used by Immich for session management and search functionality.${NC}"
JWT_SECRET=$(generate_secret)
echo -e "${GREEN}Generated JWT_SECRET.${NC}"
TYPESENSE_API_KEY=$(generate_secret)
echo -e "${GREEN}Generated TYPESENSE_API_KEY.${NC}"


header "Optional: Reverse Proxy Setup"
ask_yes_no "Do you plan to use a reverse proxy (e.g., Nginx Proxy Manager, Traefik, Caddy) to access Immich with a domain name and HTTPS?" "Y"
SETUP_REVERSE_PROXY="$REPLY"
REVERSE_PROXY_DOMAIN=""
if [ "$SETUP_REVERSE_PROXY" == "Y" ]; then
    ask "Enter the domain name you will use for Immich (e.g., photos.example.com)" "immich.localhost"
    REVERSE_PROXY_DOMAIN="$REPLY"
fi


# --- Prepare Directory and Files ---
TIMESTAMP=$(date +"%Y%m%d-%H%M")
STACK_DIR="immich-stack-${TIMESTAMP}"
mkdir -p "$STACK_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create directory ${STACK_DIR}. Aborting.${NC}"
    exit 1
fi
echo -e "${GREEN}Created directory: ${STACK_DIR}${NC}"

ENV_FILE="${STACK_DIR}/.env"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"

# --- Generate .env file ---
echo -e "${CYAN}Generating .env file at ${ENV_FILE}...${NC}"
cat << EOF > "$ENV_FILE"
# .env file for Immich Docker Stack
# Generated by script on $(date)

# General Settings
TZ=${TZ_CONFIG}
PUID=${PUID}
PGID=${PGID}

# Immich Specific URLs (handled by docker-compose, do not change unless you know what you're doing)
IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning:3003
IMMICH_SERVER_URL=http://immich-server:${IMMICH_PORT} # Internal server port, host port is mapped in compose
REDIS_URL=redis://immich-redis:6379
DATABASE_URL=postgres://${DB_USERNAME}:${DB_PASSWORD}@immich-postgres:5432/${DB_DATABASE_NAME}

# Database Credentials
DB_HOSTNAME=immich-postgres
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_DATABASE_NAME=${DB_DATABASE_NAME}
# DB_DATA_LOCATION is mounted as a volume, not set as env var for postgres container

# Redis
REDIS_HOSTNAME=immich-redis
# REDIS_PASSWORD= # Optional: if you set one in the redis service

# JWT Secret (Important for security)
JWT_SECRET=${JWT_SECRET}

# Typesense API Key (Important for search)
TYPESENSE_API_KEY=${TYPESENSE_API_KEY}

# Upload Location (mounted as a volume, also referenced here for Immich to know)
UPLOAD_LOCATION=/usr/src/app/upload
# The actual host path ${UPLOAD_LOCATION} is mapped to this in docker-compose.yml

# Logging (optional: 'verbose', 'debug', 'log', 'warn', 'error')
LOG_LEVEL=error

# Immich Version to use
IMMICH_VERSION=${IMMICH_VERSION}

# Optional: Reverse Proxy (if you set one up)
# PUBLIC_LOGIN_PAGE_MESSAGE="Access via Reverse Proxy at https://${REVERSE_PROXY_DOMAIN}"
# IMMICH_TRUSTED_PROXY_IP= # If your reverse proxy is on a different Docker network or host, list its IP here. Example: 172.16.0.0/12
# For Traefik, often no IP needed. For NPM, often Docker network gateway (e.g. 172.x.0.1)
EOF
echo -e "${GREEN}✅ .env file generated.${NC}"


# --- Generate docker-compose.yml file ---
echo -e "${CYAN}Generating docker-compose.yml file at ${COMPOSE_FILE}...${NC}"

# Determine PostgreSQL port mapping
POSTGRES_PORT_MAPPING=""
if [ "$EXPOSE_POSTGRES_PORT" == "Y" ]; then
    POSTGRES_PORT_MAPPING="    ports:
      - \"${POSTGRES_HOST_PORT}:5432\""
fi

# Reverse Proxy Network (optional)
REVERSE_PROXY_NETWORK_DEFINITION=""
REVERSE_PROXY_SERVICE_NETWORK=""
if [ "$SETUP_REVERSE_PROXY" == "Y" ]; then
    ask "Enter the name of your existing reverse proxy Docker network (e.g., nginx-proxy-manager_default, traefik_proxy). Leave blank if unsure or not created yet." "proxy"
    REVERSE_PROXY_DOCKER_NETWORK_NAME="$REPLY"
    if [ -n "$REVERSE_PROXY_DOCKER_NETWORK_NAME" ]; then
        REVERSE_PROXY_NETWORK_DEFINITION="networks:
  ${REVERSE_PROXY_DOCKER_NETWORK_NAME}:
    external: true
  immich_internal:
    driver: bridge"
        REVERSE_PROXY_SERVICE_NETWORK="networks:
      - immich_internal
      - ${REVERSE_PROXY_DOCKER_NETWORK_NAME}"
    else
      REVERSE_PROXY_NETWORK_DEFINITION="networks:
  immich_internal:
    driver: bridge"
      REVERSE_PROXY_SERVICE_NETWORK="networks:
      - immich_internal"
    fi
else
    REVERSE_PROXY_NETWORK_DEFINITION="networks:
  immich_internal:
    driver: bridge"
    REVERSE_PROXY_SERVICE_NETWORK="networks:
      - immich_internal"
fi

cat << EOF > "$COMPOSE_FILE"
# Docker Compose file for Immich
# Generated by script on $(date)
# Navigate to this directory ('${STACK_DIR}') and run:
# docker-compose up -d
# To stop: docker-compose down
# To update: docker-compose pull && docker-compose up -d

version: '3.8'

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:\${IMMICH_VERSION:-release}
    command: [ "start.sh", "immich" ]
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload # Actual photos/videos path
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - "${IMMICH_PORT}:3001" # Host port : Container port for Immich server
    depends_on:
      - immich-redis
      - immich-database
      - immich-typesense
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-microservices:
    container_name: immich_microservices
    image: ghcr.io/immich-app/immich-server:\${IMMICH_VERSION:-release}
    # extends: # Omitted for script simplicity, using command directly
    #  file: docker-compose.yml # Assuming this file is this one
    #  service: immich-server
    command: [ "start.sh", "microservices" ]
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    depends_on:
      - immich-redis
      - immich-database
      - immich-typesense
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:\${IMMICH_VERSION:-release}
    volumes:
      - ${MODEL_CACHE_LOCATION}:/cache # Model cache path
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports: # Only expose if you have a specific need, usually not required
      # - "3003:3003"
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-web:
    container_name: immich_web
    image: ghcr.io/immich-app/immich-web:\${IMMICH_VERSION:-release}
    env_file:
      - .env
    ports: # This service is usually proxied by immich-server or a reverse proxy
      # If not using a reverse proxy directly in front of immich-server,
      # you might map this if you were accessing it directly, but it's uncommon.
      # The main access point is immich-server's port ${IMMICH_PORT}.
      # Example: - "8080:8080" # If you wanted to expose it separately for some reason.
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-database:
    container_name: immich_postgres
    image: tensorchord/pgvecto-rs:pg16-v0.2.0 # Or use timescale/timescaledb-ha:pg16-ts2.13-latest for TimescaleDB
    environment:
      POSTGRES_USER: \${DB_USERNAME}
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_DB: \${DB_DATABASE_NAME}
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data # Database data persistence
      - /etc/localtime:/etc/localtime:ro
${POSTGRES_PORT_MAPPING}
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-redis:
    container_name: immich_redis
    image: redis:6.2-alpine@sha256:84882e231368784030570d5ac099015308c25366910948504065975721f58781
    # environment: # If you want to set a password for Redis
    #   - REDIS_PASSWORD=yoursecurepassword
    # command: ["redis-server", "--requirepass", "\${REDIS_PASSWORD}"]
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

  immich-typesense:
    container_name: immich_typesense
    image: typesense/typesense:0.25.2@sha256:963f4353851f47c4c17802082a4029576035605a6c0957127d4f87f8256538a8
    environment:
      TYPESENSE_API_KEY: "\${TYPESENSE_API_KEY}"
      TYPESENSE_DATA_DIR: /data
      # GLOG_minloglevel: 0 # Uncomment for more verbose logging if needed
    volumes:
      - ./tsdata:/data # Typesense data persistence
      - /etc/localtime:/etc/localtime:ro
    restart: always
    ${REVERSE_PROXY_SERVICE_NETWORK}

${REVERSE_PROXY_NETWORK_DEFINITION}

volumes: # Define named volumes if not using host paths for everything
  # pgdata: # This is handled by DB_DATA_LOCATION bind mount
  tsdata: # Typesense data, created as a named volume within the stack directory context
  # model-cache: # This is handled by MODEL_CACHE_LOCATION bind mount
EOF

# Set permissions for tsdata if it's going to be created by Docker inside STACK_DIR
# This isn't strictly necessary if 'tsdata' is a named volume as Docker manages its permissions.
# If it were a bind mount, `mkdir -p ${STACK_DIR}/tsdata && sudo chown ${PUID}:${PGID} ${STACK_DIR}/tsdata` would be good.
# For simplicity, we'll let Docker handle the named volume 'tsdata'.

echo -e "${GREEN}✅ docker-compose.yml file generated.${NC}"

# --- Final Instructions ---
header "🎉 Immich Stack Configuration Complete! 🎉"
echo -e "Your Immich Docker Compose configuration has been saved in the directory:"
echo -e "${BOLD}${YELLOW}${STACK_DIR}${NC}"
echo
echo -e "${BOLD}${CYAN}To start your Immich stack:${NC}"
echo -e "1. Navigate to the directory: ${GREEN}cd ${STACK_DIR}${NC}"
echo -e "2. Run Docker Compose:      ${GREEN}docker-compose up -d${NC}"
echo
echo -e "${YELLOW}It might take a few minutes for all services to start up, especially on the first run as images are downloaded.${NC}"
echo -e "You can monitor the logs using: ${GREEN}docker-compose logs -f${NC}"
echo
echo -e "${BOLD}${CYAN}Once started, you should be able to access Immich at:${NC}"
if [ "$SETUP_REVERSE_PROXY" == "Y" ] && [ -n "$REVERSE_PROXY_DOMAIN" ]; then
    echo -e "   ${GREEN}http://${IMMICH_HOST_IP:-<your_server_ip>}:${IMMICH_PORT}${NC} (locally, before reverse proxy is fully set up)"
    echo -e "   ${GREEN}https://${REVERSE_PROXY_DOMAIN}${NC} (once your reverse proxy is configured)"
else
    echo -e "   ${GREEN}http://${IMMICH_HOST_IP:-<your_server_ip>}:${IMMICH_PORT}${NC}"
fi
echo -e "   (Replace ${YELLOW}<your_server_ip>${NC} with your server's actual IP address if accessing from another device on your network)"
echo
echo -e "${BOLD}${CYAN}Database Password (if auto-generated or you forgot):${NC}"
echo -e "   Username: ${YELLOW}${DB_USERNAME}${NC}"
echo -e "   Password: ${YELLOW}${DB_PASSWORD}${NC} (store this safely!)"
echo

# --- Immich Usage Information ---
header "🚀 Getting Started with Immich 🚀"
echo -e "${BOLD}1. Initial Admin User Setup:${NC}"
echo -e "   - When you first access Immich via the web UI, it will prompt you to create an admin account."
echo -e "   - Follow the on-screen instructions to set up your email and password."
echo
echo -e "${BOLD}2. Mobile App Setup:${NC}"
echo -e "   - Download the Immich mobile app for iOS or Android."
echo -e "   - In the app, when asked for the 'Server Endpoint URL', enter:"
if [ "$SETUP_REVERSE_PROXY" == "Y" ] && [ -n "$REVERSE_PROXY_DOMAIN" ]; then
    echo -e "     ${GREEN}https://${REVERSE_PROXY_DOMAIN}${NC} (if your reverse proxy is set up and working)"
    echo -e "     ${YELLOW}If the above doesn't work yet, or for local testing, try:${NC}"
    echo -e "     ${GREEN}http://<your_server_ip>:${IMMICH_PORT}${NC} (replace <your_server_ip> with your server's IP address on your local network)"
else
    echo -e "     ${GREEN}http://<your_server_ip>:${IMMICH_PORT}${NC} (replace <your_server_ip> with your server's IP address on your local network)"
fi
echo -e "   - Log in with the admin credentials you created."
echo
echo -e "${BOLD}3. Uploading Photos & Videos:${NC}"
echo -e "   - ${YELLOW}Mobile App:${NC} This is the primary way to back up photos from your phone. Configure background backup in the app's settings."
echo -e "   - ${YELLOW}Web UI:${NC} You can upload photos and videos directly through the web interface."
echo -e "   - ${YELLOW}Immich CLI:${NC} For bulk importing existing libraries, the Immich CLI (Command Line Interface) is highly recommended. "
echo -e "     Search for 'Immich CLI' documentation for setup and usage. This is often run from your host machine or another container."
echo -e "     Example: \`immich upload --key <your_api_key> --server <your_server_endpoint_url> /path/to/your/photos\`"
echo
echo -e "${BOLD}4. Key Features to Explore:${NC}"
echo -e "   - ${CYAN}Albums:${NC} Create and manage albums."
echo -e "   - ${CYAN}Sharing:${NC} Share photos or albums with other Immich users or via public links."
echo -e "   - ${CYAN}Explore Page:${NC} Discover photos by people (facial recognition), places, and things (object detection)."
echo -e "     (Machine learning tasks run in the background, so these features populate over time)."
echo -e "   - ${CYAN}Map View:${NC} See your photos on a world map (if they have GPS data)."
echo -e "   - ${CYAN}Memory Lane:${NC} Rediscover past moments."
echo
echo -e "${BOLD}5. Tips & Tricks:${NC}"
echo -e "   - ${YELLOW}Reverse Proxy is Highly Recommended:${NC}"
echo -e "     For secure external access (e.g., from your phone when not on Wi-Fi) and HTTPS, a reverse proxy is essential."
echo -e "     Popular choices: Nginx Proxy Manager (NPM), Traefik, Caddy."
if [ "$SETUP_REVERSE_PROXY" == "Y" ]; then
    echo -e "     ${GREEN}You indicated you plan to use one! Here's a general idea for Nginx Proxy Manager (NPM):${NC}"
    echo -e "       1. Ensure NPM is running and accessible."
    echo -e "       2. Add a new Proxy Host in NPM:"
    echo -e "          - Domain Name(s): ${YELLOW}${REVERSE_PROXY_DOMAIN}${NC}"
    echo -e "          - Scheme: ${YELLOW}http${NC}"
    echo -e "          - Forward Hostname / IP: ${YELLOW}immich_server${NC} (this is the Docker service name of the Immich server)"
    echo -e "          - Forward Port: ${YELLOW}3001${NC} (this is the internal port Immich server listens on)"
    echo -e "          - Enable 'Block Common Exploits'."
    echo -e "          - Go to the 'SSL' tab, request a new SSL certificate (Let's Encrypt), and force SSL."
    echo -e "     If you used a specific reverse proxy network ('${REVERSE_PROXY_DOCKER_NETWORK_NAME}'), ensure NPM is also connected to it."
    echo -e "     For other reverse proxies, consult their documentation for forwarding to a Docker service/port."
else
    echo -e "     Consider setting one up. Nginx Proxy Manager is user-friendly for beginners."
fi
echo -e "   - ${CYAN}User Management:${NC} You can create multiple user accounts from the admin settings in the web UI."
echo -e "   - ${CYAN}Storage Templates:${NC} Customize how Immich organizes your files on disk (Admin Settings -> Asset Upload Settings). Default is `library/{year}/{month}/{day}/{filename}.{ext}`."
echo -e "   - ${CYAN}Background Tasks:${NC} Thumbnail generation, metadata extraction, and machine learning take time, especially for large libraries. Be patient. You can monitor jobs in Admin Settings -> Jobs."
echo -e "   - ${CYAN}Backups are CRUCIAL:${NC} Your Immich stack contains your precious memories!"
echo -e "     - Back up the ${YELLOW}${UPLOAD_LOCATION}${NC} directory (your actual photo/video files)."
echo -e "     - Back up the ${YELLOW}${DB_DATA_LOCATION}${NC} directory (your PostgreSQL database)."
echo -e "     - Back up the generated ${YELLOW}${STACK_DIR}/.env${NC} file (contains your secrets)."
echo -e "     - Consider tools like Duplicati, BorgBackup, or rsync scripts for automated backups."
echo -e "   - ${CYAN}Updating Immich:${NC} Periodically, new versions are released."
echo -e "     1. Read the release notes for any breaking changes!"
echo -e "     2. `cd ${STACK_DIR}`"
echo -e "     3. `docker-compose pull` (pulls the latest images specified by IMMICH_VERSION in your .env)"
echo -e "     4. `docker-compose up -d` (recreates containers with the new images)"
echo -e "   - ${CYAN}Community Support:${NC} Join the Immich Discord or visit their GitHub for help and discussions: https://immich.app/docs/community"
echo

header "Troubleshooting & Next Steps"
echo -e "If Immich doesn't start:"
echo -e "  - Check logs: ${GREEN}docker-compose logs -f immich-server immich-microservices immich-database${NC} (in the ${STACK_DIR} directory)"
echo -e "  - Ensure ports are not conflicting with other services on your host."
echo -e "  - Verify directory permissions for your mounted volumes."
echo
echo -e "${BOLD}${GREEN}Enjoy your self-hosted photo and video management with Immich!${NC}"
echo

exit 0
