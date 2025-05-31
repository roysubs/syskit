#!/bin/bash
# Author: Roy Wiseman 2025-01

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
IMMICH_NETWORK_NAME="immich_network" # Docker network for Immich services

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

# Function to validate a directory path and handle permissions
validate_and_create_dir() {
    local dir_path_prompt dir_path default_dir_path owner_puid owner_pgid
    dir_path_prompt="$1"
    default_dir_path="$2"
    owner_puid="$3"
    owner_pgid="$4"

    while true; do
        ask "$dir_path_prompt" "$default_dir_path"
        dir_path="$REPLY"
        dir_path_expanded="${dir_path/#\~/$HOME}" # Expand tilde

        if [ -z "$dir_path_expanded" ]; then
            echo -e "${RED}Path cannot be empty.${NC}"
            continue
        fi

        if [ ! -d "$dir_path_expanded" ]; then
            echo -e "${YELLOW}Directory '${dir_path_expanded}' does not exist.${NC}"
            ask_yes_no "Create it now?" "Y"
            if [ "$REPLY" == "Y" ]; then
                echo -e "${CYAN}Attempting to create directory and set ownership... (may require sudo password)${NC}"
                if mkdir -p "$dir_path_expanded"; then
                    echo -e "${GREEN}Directory created: '$dir_path_expanded'.${NC}"
                    if sudo chown "${owner_puid}:${owner_pgid}" "$dir_path_expanded"; then
                        echo -e "${GREEN}Ownership of '$dir_path_expanded' set to ${owner_puid}:${owner_pgid}.${NC}"
                        REPLY="$dir_path_expanded"; return 0
                    else
                        echo -e "${RED}❌ Failed to set ownership for '$dir_path_expanded'. Please ensure you have sudo privileges and the PUID/PGID are valid.${NC}"
                        echo -e "${YELLOW}You may need to set ownership manually: sudo chown ${owner_puid}:${owner_pgid} \"${dir_path_expanded}\"${NC}"
                        return 1 # Critical failure
                    fi
                else
                    echo -e "${RED}❌ Failed to create directory '$dir_path_expanded}'. Check permissions.${NC}"
                    return 1 # Critical failure
                fi
            else
                echo -e "${YELLOW}Directory creation skipped. Please ensure the path exists and has correct permissions before proceeding or choose a different path.${NC}"
                # Loop will continue for new input or user can exit script
            fi
        else # Directory exists
            echo -e "${GREEN}Directory '${dir_path_expanded}' already exists.${NC}"
            current_owner_uid=$(stat -c "%u" "$dir_path_expanded" 2>/dev/null)
            current_owner_gid=$(stat -c "%g" "$dir_path_expanded" 2>/dev/null)

            if [ -z "$current_owner_uid" ] || [ -z "$current_owner_gid" ]; then
                 echo -e "${RED}Could not determine current ownership of '$dir_path_expanded'. Check permissions or path.${NC}"
                 ask_yes_no "Continue anyway assuming permissions are correct?" "N"
                 if [ "$REPLY" == "Y" ]; then REPLY="$dir_path_expanded"; return 0; else return 1; fi
            fi

            if [ "$current_owner_uid" != "$owner_puid" ] || [ "$current_owner_gid" != "$owner_pgid" ]; then
                echo -e "${YELLOW}Warning: Ownership of '${dir_path_expanded}' is currently ${current_owner_uid}:${current_owner_gid}, not the target ${owner_puid}:${owner_pgid}.${NC}"
                ask_yes_no "Attempt to set correct ownership using sudo (sudo chown ${owner_puid}:${owner_pgid} \"${dir_path_expanded}\")?" "Y"
                if [ "$REPLY" == "Y" ]; then
                    echo -e "${CYAN}Attempting to set ownership... (may require sudo password)${NC}"
                    if sudo chown "${owner_puid}:${owner_pgid}" "$dir_path_expanded"; then
                        echo -e "${GREEN}Ownership of '$dir_path_expanded' set to ${owner_puid}:${owner_pgid}.${NC}"
                        REPLY="$dir_path_expanded"; return 0
                    else
                        echo -e "${RED}❌ Failed to set ownership for '$dir_path_expanded'.${NC}"
                        echo -e "${YELLOW}Please ensure correct ownership manually: sudo chown ${owner_puid}:${owner_pgid} \"${dir_path_expanded}\"${NC}"
                        ask_yes_no "Continue anyway (not recommended if ownership failed)?" "N"
                        if [ "$REPLY" == "Y" ]; then REPLY="$dir_path_expanded"; return 0; else return 1; fi
                    fi
                else
                    echo -e "${YELLOW}Ownership not changed. Ensure PUID/PGID ${owner_puid}:${owner_pgid} has appropriate access to '${dir_path_expanded}'.${NC}"
                    REPLY="$dir_path_expanded"; return 0 # Proceed with existing (potentially incorrect) ownership at user's choice
                fi
            else
                echo -e "${GREEN}Ownership of '${dir_path_expanded}' is already correctly set to ${owner_puid}:${owner_pgid}.${NC}"
                REPLY="$dir_path_expanded"; return 0
            fi
        fi
    done
}


# Function to stop and remove a container if it exists
cleanup_container() {
    local container_name="$1"
    if [ "$(docker ps -aq -f name=^${container_name}$)" ]; then
        echo -e "${YELLOW}Attempting to stop and remove existing container: ${container_name}...${NC}"
        docker stop "$container_name" >/dev/null 2>&1
        docker rm "$container_name" >/dev/null 2>&1
        echo -e "${GREEN}Cleaned up existing container: ${container_name}.${NC}"
    fi
}


# --- Main Script Logic ---
clear
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "${BOLD}${GREEN}   Immich Docker 'run' Script & Compose Generator  ${NC}"
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "\nThis script will guide you through setting up Immich using individual 'docker run' commands."
echo -e "It will then generate a 'docker-compose.yml' file in the current directory as a record."

# Check if Docker is installed and running
header "Docker Sanity Checks"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"; exit 1
fi
if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"; exit 1
fi
if ! command -v sudo &> /dev/null; then
    echo -e "${RED}❌ 'sudo' command not found. This script requires sudo for directory permission management.${NC}"; exit 1
fi
echo -e "${GREEN}✅ Docker is installed and running. 'sudo' is available.${NC}"

# --- Collect User Input ---

header "User and Permissions Configuration"
default_puid=$(id -u)
default_pgid=$(id -g)
ask "Enter PUID (User ID for file permissions)" "$default_puid"; PUID="$REPLY"
ask "Enter PGID (Group ID for file permissions)" "$default_pgid"; PGID="$REPLY"

header "Timezone Configuration"
default_tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
ask "Enter Timezone (e.g., America/New_York)" "$default_tz"; TZ_CONFIG="$REPLY"

header "Immich Data Paths Configuration"
echo -e "${YELLOW}IMPORTANT: Choose paths on a reliable, local filesystem (SSD recommended for database).${NC}"
echo -e "${YELLOW}The script will attempt to set correct ownership using 'sudo' if needed.${NC}"

validate_and_create_dir "Enter host path for Photos/Videos (UPLOAD_LOCATION)" "$HOME/immich-photos" "$PUID" "$PGID"
if [ $? -ne 0 ]; then echo -e "${RED}Path setup failed. Aborting.${NC}"; exit 1; fi; UPLOAD_LOCATION="$REPLY"

validate_and_create_dir "Enter host path for Immich Database data (DB_DATA_LOCATION)" "$HOME/immich-dbdata" "$PUID" "$PGID"
if [ $? -ne 0 ]; then echo -e "${RED}Path setup failed. Aborting.${NC}"; exit 1; fi; DB_DATA_LOCATION="$REPLY"

validate_and_create_dir "Enter host path for Machine Learning model cache (MODEL_CACHE_LOCATION)" "$HOME/immich-cache" "$PUID" "$PGID"
if [ $? -ne 0 ]; then echo -e "${RED}Path setup failed. Aborting.${NC}"; exit 1; fi; MODEL_CACHE_LOCATION="$REPLY"

TYPESENSE_DATA_PATH_BASE="$PWD" # Base directory for Typesense data
TYPESENSE_DATA_SUBDIR="immich-tsdata"
TYPESENSE_DATA_PATH="${TYPESENSE_DATA_PATH_BASE}/${TYPESENSE_DATA_SUBDIR}"

echo -e "${CYAN}Typesense data will be stored in: ${TYPESENSE_DATA_PATH}${NC}"
# Use validate_and_create_dir for Typesense data path as well
validate_and_create_dir "Confirm or change Typesense data path" "$TYPESENSE_DATA_PATH" "$PUID" "$PGID"
if [ $? -ne 0 ]; then echo -e "${RED}Typesense path setup failed. Aborting.${NC}"; exit 1; fi; TYPESENSE_DATA_PATH="$REPLY"


header "Network Port Configuration"
DEFAULT_IMMICH_PORT=2283
while true; do
    ask "Enter host port for Immich Web UI" "$DEFAULT_IMMICH_PORT"; IMMICH_HOST_PORT="$REPLY"
    if [[ ! "$IMMICH_HOST_PORT" =~ ^[0-9]+$ ]] || [ "$IMMICH_HOST_PORT" -lt 1 ] || [ "$IMMICH_HOST_PORT" -gt 65535 ]; then
        echo -e "${RED}Invalid port.${NC}"; continue
    fi
    if check_port "$IMMICH_HOST_PORT"; then
        echo -e "${YELLOW}⚠️ Port ${IMMICH_HOST_PORT} appears to be in use.${NC}"
        ask_yes_no "Try a different port?" "Y"
        if [ "$REPLY" == "N" ]; then echo -e "${RED}Aborting.${NC}"; exit 1; fi
    else
        echo -e "${GREEN}✅ Port ${IMMICH_HOST_PORT} for Immich Web UI is free.${NC}"; break
    fi
done
IMMICH_INTERNAL_SERVER_PORT="3001" # Immich server container listens on 3001

ask_yes_no "Do you want to expose the PostgreSQL port (5432) on the host? (Not for typical use)" "N"; EXPOSE_POSTGRES_PORT="$REPLY"
POSTGRES_HOST_MAPPED_PORT="5432"
if [ "$EXPOSE_POSTGRES_PORT" == "Y" ]; then
    ask "Enter host port for PostgreSQL (if exposing)" "5432"; POSTGRES_HOST_MAPPED_PORT="$REPLY"
fi

header "Database Credentials (will be auto-generated if left blank)"
ask "Enter PostgreSQL Database Name" "immich"; DB_DATABASE_NAME="$REPLY"
ask "Enter PostgreSQL Username" "immich"; DB_USERNAME="$REPLY"
ask "Enter PostgreSQL Password (leave blank to auto-generate)"; DB_PASSWORD="$REPLY"
if [ -z "$DB_PASSWORD" ]; then DB_PASSWORD=$(generate_secret); echo -e "${GREEN}Generated PostgreSQL password.${NC}"; fi

header "Security Secrets (will be auto-generated)"
JWT_SECRET=$(generate_secret); echo -e "${GREEN}Generated JWT_SECRET.${NC}"
TYPESENSE_API_KEY=$(generate_secret); echo -e "${GREEN}Generated TYPESENSE_API_KEY.${NC}"

# URLs for inter-container communication
DATABASE_URL_INTERNAL="postgres://${DB_USERNAME}:${DB_PASSWORD}@immich_postgres:5432/${DB_DATABASE_NAME}"
REDIS_URL_INTERNAL="redis://immich_redis:6379"
MACHINE_LEARNING_URL_INTERNAL="http://immich_machine_learning:3003"
SERVER_URL_INTERNAL="http://immich_server:${IMMICH_INTERNAL_SERVER_PORT}" # For web to server


# --- Docker Network Setup ---
header "Docker Network Setup"
if ! docker network inspect "$IMMICH_NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "${CYAN}Creating Docker network: ${IMMICH_NETWORK_NAME}...${NC}"
    if docker network create "$IMMICH_NETWORK_NAME"; then
        echo -e "${GREEN}✅ Network '${IMMICH_NETWORK_NAME}' created successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to create network '${IMMICH_NETWORK_NAME}'. Aborting.${NC}"; exit 1
    fi
else
    echo -e "${YELLOW}Network '${IMMICH_NETWORK_NAME}' already exists. Reusing.${NC}"
fi

# --- Optional Reverse Proxy Network ---
REVERSE_PROXY_DOCKER_NETWORK_NAME=""
ask_yes_no "Are you using an existing reverse proxy (e.g., Nginx Proxy Manager) on a separate Docker network?" "N"
if [ "$REPLY" == "Y" ]; then
    ask "Enter the name of your existing reverse proxy Docker network" "proxy"
    REVERSE_PROXY_DOCKER_NETWORK_NAME="$REPLY"
    if ! docker network inspect "$REVERSE_PROXY_DOCKER_NETWORK_NAME" >/dev/null 2>&1; then
        echo -e "${RED}❌ Reverse proxy network '${REVERSE_PROXY_DOCKER_NETWORK_NAME}' not found. Please create it or ensure the name is correct.${NC}"
        ask_yes_no "Continue without attaching to reverse proxy network?" "Y"
        if [ "$REPLY" == "N" ]; then echo "${RED}Aborting.${NC}"; exit 1; fi
        REVERSE_PROXY_DOCKER_NETWORK_NAME="" # Reset if user wants to continue without
    else
        echo -e "${GREEN}✅ Will attach Immich Server to '${REVERSE_PROXY_DOCKER_NETWORK_NAME}'.${NC}"
    fi
fi


# --- Container Deployment ---
header "Deploying Immich Containers via 'docker run'"
echo -e "${YELLOW}The script will now attempt to stop and remove any existing containers with the same names before starting new ones.${NC}"
echo -e "${YELLOW}This might take a few minutes as images are pulled.${NC}"
sleep 3

# Common docker run options
RESTART_POLICY="--restart unless-stopped"
COMMON_ENV_VARS=(
    -e "TZ=${TZ_CONFIG}"
    -e "PUID=${PUID}"
    -e "PGID=${PGID}"
    -e "LOG_LEVEL=error"
)

# 1. PostgreSQL
CONTAINER_NAME_POSTGRES="immich_postgres"
cleanup_container "$CONTAINER_NAME_POSTGRES"
echo -e "${CYAN}Starting ${CONTAINER_NAME_POSTGRES}...${NC}"
POSTGRES_PORTS_MAPPING=""
if [ "$EXPOSE_POSTGRES_PORT" == "Y" ]; then
    POSTGRES_PORTS_MAPPING="-p ${POSTGRES_HOST_MAPPED_PORT}:5432"
fi
if docker run -d \
    --name "$CONTAINER_NAME_POSTGRES" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    -e "POSTGRES_USER=${DB_USERNAME}" \
    -e "POSTGRES_PASSWORD=${DB_PASSWORD}" \
    -e "POSTGRES_DB=${DB_DATABASE_NAME}" \
    -v "${DB_DATA_LOCATION}:/var/lib/postgresql/data" \
    -v "/etc/localtime:/etc/localtime:ro" \
    ${POSTGRES_PORTS_MAPPING} \
    tensorchord/pgvecto-rs:pg16-v0.2.0; then
    echo -e "${GREEN}✅ ${CONTAINER_NAME_POSTGRES} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_POSTGRES}. Check logs: docker logs ${CONTAINER_NAME_POSTGRES}${NC}"; exit 1
fi
sleep 5 # Give DB time to initialize

# 2. Redis
CONTAINER_NAME_REDIS="immich_redis"
cleanup_container "$CONTAINER_NAME_REDIS"
echo -e "${CYAN}Starting ${CONTAINER_NAME_REDIS}...${NC}"
if docker run -d \
    --name "$CONTAINER_NAME_REDIS" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    redis:6.2-alpine; then # SHA256 digest removed
    echo -e "${GREEN}✅ ${CONTAINER_NAME_REDIS} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_REDIS}. Check logs: docker logs ${CONTAINER_NAME_REDIS}${NC}"; exit 1
fi
sleep 2

# 3. Typesense
CONTAINER_NAME_TYPESENSE="immich_typesense"
cleanup_container "$CONTAINER_NAME_TYPESENSE"
echo -e "${CYAN}Starting ${CONTAINER_NAME_TYPESENSE}...${NC}"
if docker run -d \
    --name "$CONTAINER_NAME_TYPESENSE" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    -e "TYPESENSE_API_KEY=${TYPESENSE_API_KEY}" \
    -e "TYPESENSE_DATA_DIR=/data" \
    -v "${TYPESENSE_DATA_PATH}:/data" \
    -v "/etc/localtime:/etc/localtime:ro" \
    typesense/typesense:0.25.2; then # SHA256 digest removed
    echo -e "${GREEN}✅ ${CONTAINER_NAME_TYPESENSE} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_TYPESENSE}. Check logs: docker logs ${CONTAINER_NAME_TYPESENSE}${NC}"; exit 1
fi
sleep 2

# 4. Immich Machine Learning
CONTAINER_NAME_ML="immich_machine_learning"
cleanup_container "$CONTAINER_NAME_ML"
echo -e "${CYAN}Starting ${CONTAINER_NAME_ML}...${NC}"
if docker run -d \
    --name "$CONTAINER_NAME_ML" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    "${COMMON_ENV_VARS[@]}" \
    -e "DATABASE_URL=${DATABASE_URL_INTERNAL}" \
    -e "REDIS_URL=${REDIS_URL_INTERNAL}" \
    -e "TYPESENSE_URL=http://${CONTAINER_NAME_TYPESENSE}:8108" \
    -e "TYPESENSE_API_KEY=${TYPESENSE_API_KEY}" \
    -e "IMMICH_MACHINE_LEARNING_WORKERS=1" \
    -v "${MODEL_CACHE_LOCATION}:/cache" \
    -v "/etc/localtime:/etc/localtime:ro" \
    ghcr.io/immich-app/immich-machine-learning:"${IMMICH_VERSION}"; then
    echo -e "${GREEN}✅ ${CONTAINER_NAME_ML} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_ML}. Check logs: docker logs ${CONTAINER_NAME_ML}${NC}"; exit 1
fi
sleep 2

# 5. Immich Microservices
CONTAINER_NAME_MICROSERVICES="immich_microservices"
cleanup_container "$CONTAINER_NAME_MICROSERVICES"
echo -e "${CYAN}Starting ${CONTAINER_NAME_MICROSERVICES}...${NC}"
if docker run -d \
    --name "$CONTAINER_NAME_MICROSERVICES" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    "${COMMON_ENV_VARS[@]}" \
    -e "JWT_SECRET=${JWT_SECRET}" \
    -e "DATABASE_URL=${DATABASE_URL_INTERNAL}" \
    -e "REDIS_URL=${REDIS_URL_INTERNAL}" \
    -e "IMMICH_MACHINE_LEARNING_URL=${MACHINE_LEARNING_URL_INTERNAL}" \
    -e "TYPESENSE_URL=http://${CONTAINER_NAME_TYPESENSE}:8108" \
    -e "TYPESENSE_API_KEY=${TYPESENSE_API_KEY}" \
    -v "${UPLOAD_LOCATION}:/usr/src/app/upload" \
    -v "/etc/localtime:/etc/localtime:ro" \
    ghcr.io/immich-app/immich-server:"${IMMICH_VERSION}" start.sh microservices; then
    echo -e "${GREEN}✅ ${CONTAINER_NAME_MICROSERVICES} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_MICROSERVICES}. Check logs: docker logs ${CONTAINER_NAME_MICROSERVICES}${NC}"; exit 1
fi
sleep 2

# 6. Immich Server
CONTAINER_NAME_SERVER="immich_server"
cleanup_container "$CONTAINER_NAME_SERVER"
echo -e "${CYAN}Starting ${CONTAINER_NAME_SERVER}...${NC}"

SERVER_NETWORKS="--network ${IMMICH_NETWORK_NAME}"
if [ -n "$REVERSE_PROXY_DOCKER_NETWORK_NAME" ]; then
    SERVER_NETWORKS="${SERVER_NETWORKS} --network ${REVERSE_PROXY_DOCKER_NETWORK_NAME}"
fi

if docker run -d \
    --name "$CONTAINER_NAME_SERVER" \
    ${SERVER_NETWORKS} \
    ${RESTART_POLICY} \
    "${COMMON_ENV_VARS[@]}" \
    -e "JWT_SECRET=${JWT_SECRET}" \
    -e "DATABASE_URL=${DATABASE_URL_INTERNAL}" \
    -e "REDIS_URL=${REDIS_URL_INTERNAL}" \
    -e "IMMICH_MACHINE_LEARNING_URL=${MACHINE_LEARNING_URL_INTERNAL}" \
    -e "TYPESENSE_URL=http://${CONTAINER_NAME_TYPESENSE}:8108" \
    -e "TYPESENSE_API_KEY=${TYPESENSE_API_KEY}" \
    -e "UPLOAD_LOCATION=/usr/src/app/upload" \
    -p "${IMMICH_HOST_PORT}:${IMMICH_INTERNAL_SERVER_PORT}" \
    -v "${UPLOAD_LOCATION}:/usr/src/app/upload" \
    -v "/etc/localtime:/etc/localtime:ro" \
    ghcr.io/immich-app/immich-server:"${IMMICH_VERSION}" start.sh immich; then
    echo -e "${GREEN}✅ ${CONTAINER_NAME_SERVER} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_SERVER}. Check logs: docker logs ${CONTAINER_NAME_SERVER}${NC}"; exit 1
fi
sleep 5 # Give server time to come up

# 7. Immich Web
CONTAINER_NAME_WEB="immich_web"
cleanup_container "$CONTAINER_NAME_WEB"
echo -e "${CYAN}Starting ${CONTAINER_NAME_WEB}...${NC}"
if docker run -d \
    --name "$CONTAINER_NAME_WEB" \
    --network "$IMMICH_NETWORK_NAME" \
    ${RESTART_POLICY} \
    "${COMMON_ENV_VARS[@]}" \
    -e "IMMICH_SERVER_URL=${SERVER_URL_INTERNAL}" \
    -e "TYPESENSE_URL=http://${CONTAINER_NAME_TYPESENSE}:8108" \
    -e "TYPESENSE_API_KEY=${TYPESENSE_API_KEY}" \
    ghcr.io/immich-app/immich-web:"${IMMICH_VERSION}"; then
    echo -e "${GREEN}✅ ${CONTAINER_NAME_WEB} started.${NC}"
else
    echo -e "${RED}❌ Failed to start ${CONTAINER_NAME_WEB}. Check logs: docker logs ${CONTAINER_NAME_WEB}${NC}"; exit 1
fi


# --- Generate docker-compose.yml file as a record ---
TIMESTAMP=$(date +"%Y%m%d-%H%M")
COMPOSE_FILE="docker-immich-${TIMESTAMP}.yaml"

echo -e "\n${CYAN}Generating Docker Compose record file: ${COMPOSE_FILE}...${NC}"

YAML_POSTGRES_PORTS=""
if [ "$EXPOSE_POSTGRES_PORT" == "Y" ]; then
    YAML_POSTGRES_PORTS="
    ports:
      - \"${POSTGRES_HOST_MAPPED_PORT}:5432\""
fi

YAML_IMMICH_SERVER_PORTS="
    ports:
      - \"${IMMICH_HOST_PORT}:${IMMICH_INTERNAL_SERVER_PORT}\""

YAML_NETWORKS_DEFINITION="
networks:
  ${IMMICH_NETWORK_NAME}:
    name: ${IMMICH_NETWORK_NAME}
    external: true
"
YAML_SERVER_NETWORKS_LIST="- ${IMMICH_NETWORK_NAME}"

if [ -n "$REVERSE_PROXY_DOCKER_NETWORK_NAME" ]; then
    YAML_NETWORKS_DEFINITION="${YAML_NETWORKS_DEFINITION}
  ${REVERSE_PROXY_DOCKER_NETWORK_NAME}:
    name: ${REVERSE_PROXY_DOCKER_NETWORK_NAME}
    external: true
"
    YAML_SERVER_NETWORKS_LIST="${YAML_SERVER_NETWORKS_LIST}
      - ${REVERSE_PROXY_DOCKER_NETWORK_NAME}"
fi


cat << EOF > "$COMPOSE_FILE"
# Docker Compose file for Immich - RECORD ONLY
# Generated by script on $(date)
# This file reflects the 'docker run' commands executed by the script.
# It can be used for reference or to deploy the stack with 'docker-compose up -d'
# if you ensure the network '${IMMICH_NETWORK_NAME}' (and '${REVERSE_PROXY_DOCKER_NETWORK_NAME}' if used) exists.

version: '3.8'

services:
  immich-server:
    container_name: ${CONTAINER_NAME_SERVER}
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION}
    command: [ "start.sh", "immich" ]
    volumes:
      - "${UPLOAD_LOCATION}:/usr/src/app/upload"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      TZ: "${TZ_CONFIG}"
      PUID: "${PUID}"
      PGID: "${PGID}"
      LOG_LEVEL: "error"
      JWT_SECRET: "${JWT_SECRET}"
      DATABASE_URL: "${DATABASE_URL_INTERNAL}"
      REDIS_URL: "${REDIS_URL_INTERNAL}"
      IMMICH_MACHINE_LEARNING_URL: "${MACHINE_LEARNING_URL_INTERNAL}"
      TYPESENSE_URL: "http://${CONTAINER_NAME_TYPESENSE}:8108"
      TYPESENSE_API_KEY: "${TYPESENSE_API_KEY}"
      UPLOAD_LOCATION: "/usr/src/app/upload"
    ${YAML_IMMICH_SERVER_PORTS}
    depends_on:
      - ${CONTAINER_NAME_REDIS}
      - ${CONTAINER_NAME_POSTGRES}
      - ${CONTAINER_NAME_TYPESENSE}
    restart: unless-stopped
    networks:
      ${YAML_SERVER_NETWORKS_LIST}

  immich-microservices:
    container_name: ${CONTAINER_NAME_MICROSERVICES}
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION}
    command: [ "start.sh", "microservices" ]
    volumes:
      - "${UPLOAD_LOCATION}:/usr/src/app/upload"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      TZ: "${TZ_CONFIG}"
      PUID: "${PUID}"
      PGID: "${PGID}"
      LOG_LEVEL: "error"
      JWT_SECRET: "${JWT_SECRET}"
      DATABASE_URL: "${DATABASE_URL_INTERNAL}"
      REDIS_URL: "${REDIS_URL_INTERNAL}"
      IMMICH_MACHINE_LEARNING_URL: "${MACHINE_LEARNING_URL_INTERNAL}"
      TYPESENSE_URL: "http://${CONTAINER_NAME_TYPESENSE}:8108"
      TYPESENSE_API_KEY: "${TYPESENSE_API_KEY}"
    depends_on:
      - ${CONTAINER_NAME_REDIS}
      - ${CONTAINER_NAME_POSTGRES}
      - ${CONTAINER_NAME_TYPESENSE}
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

  immich-machine-learning:
    container_name: ${CONTAINER_NAME_ML}
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION}
    volumes:
      - "${MODEL_CACHE_LOCATION}:/cache"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      TZ: "${TZ_CONFIG}"
      PUID: "${PUID}"
      PGID: "${PGID}"
      LOG_LEVEL: "error"
      DATABASE_URL: "${DATABASE_URL_INTERNAL}"
      REDIS_URL: "${REDIS_URL_INTERNAL}"
      TYPESENSE_URL: "http://${CONTAINER_NAME_TYPESENSE}:8108"
      TYPESENSE_API_KEY: "${TYPESENSE_API_KEY}"
      IMMICH_MACHINE_LEARNING_WORKERS: "1"
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

  immich-web:
    container_name: ${CONTAINER_NAME_WEB}
    image: ghcr.io/immich-app/immich-web:${IMMICH_VERSION}
    environment:
      TZ: "${TZ_CONFIG}"
      PUID: "${PUID}"
      PGID: "${PGID}"
      LOG_LEVEL: "error"
      IMMICH_SERVER_URL: "${SERVER_URL_INTERNAL}"
      TYPESENSE_URL: "http://${CONTAINER_NAME_TYPESENSE}:8108"
      TYPESENSE_API_KEY: "${TYPESENSE_API_KEY}"
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

  ${CONTAINER_NAME_POSTGRES}:
    container_name: ${CONTAINER_NAME_POSTGRES}
    image: tensorchord/pgvecto-rs:pg16-v0.2.0
    environment:
      POSTGRES_USER: "${DB_USERNAME}"
      POSTGRES_PASSWORD: "${DB_PASSWORD}"
      POSTGRES_DB: "${DB_DATABASE_NAME}"
    volumes:
      - "${DB_DATA_LOCATION}:/var/lib/postgresql/data"
      - "/etc/localtime:/etc/localtime:ro"
    ${YAML_POSTGRES_PORTS}
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

  ${CONTAINER_NAME_REDIS}:
    container_name: ${CONTAINER_NAME_REDIS}
    image: redis:6.2-alpine # SHA256 removed
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

  ${CONTAINER_NAME_TYPESENSE}:
    container_name: ${CONTAINER_NAME_TYPESENSE}
    image: typesense/typesense:0.25.2 # SHA256 removed
    environment:
      TYPESENSE_API_KEY: "${TYPESENSE_API_KEY}"
      TYPESENSE_DATA_DIR: "/data"
    volumes:
      - "${TYPESENSE_DATA_PATH}:/data"
      - "/etc/localtime:/etc/localtime:ro"
    restart: unless-stopped
    networks:
      - ${IMMICH_NETWORK_NAME}

${YAML_NETWORKS_DEFINITION}
EOF
echo -e "${GREEN}✅ Docker Compose record file '${COMPOSE_FILE}' generated.${NC}"


# --- Final Instructions ---
header "🎉 Immich Stack Deployed via 'docker run'! 🎉"
echo -e "Your Immich containers have been started using individual 'docker run' commands."
echo -e "A Docker Compose YAML file named ${BOLD}${YELLOW}${COMPOSE_FILE}${NC} has been generated in the current directory"
echo -e "as a record of this deployment."
echo
echo -e "${BOLD}${CYAN}Access Immich at:${NC}"
IMMICH_ACCESS_IP_SUGGESTION="${HOSTNAME_IP:-<your_server_ip>}"
if [ -z "$IMMICH_ACCESS_IP_SUGGESTION" ] || [ "$IMMICH_ACCESS_IP_SUGGESTION" == "<your_server_ip>" ]; then
    # Attempt to get a local IP
    IP_GUESS=$(hostname -I | awk '{print $1}')
    if [ -n "$IP_GUESS" ]; then
        IMMICH_ACCESS_IP_SUGGESTION="$IP_GUESS"
    else
        IMMICH_ACCESS_IP_SUGGESTION="<your_server_ip>"
    fi
fi

REVERSE_PROXY_DOMAIN_ACCESS_MSG=""
if [ -n "$REVERSE_PROXY_DOCKER_NETWORK_NAME" ]; then
    ask "Enter the domain name you will use for Immich via reverse proxy (e.g., photos.example.com)" "immich.localhost"
    REVERSE_PROXY_DOMAIN_ACCESS="$REPLY"
    REVERSE_PROXY_DOMAIN_ACCESS_MSG="   ${GREEN}https://${REVERSE_PROXY_DOMAIN_ACCESS}${NC} (once your reverse proxy is configured for ${CONTAINER_NAME_SERVER} on port ${IMMICH_INTERNAL_SERVER_PORT})"
    echo "$REVERSE_PROXY_DOMAIN_ACCESS_MSG"
    echo -e "   For initial access/testing or if reverse proxy isn't set up yet: ${GREEN}http://${IMMICH_ACCESS_IP_SUGGESTION}:${IMMICH_HOST_PORT}${NC}"
else
    echo -e "   ${GREEN}http://${IMMICH_ACCESS_IP_SUGGESTION}:${IMMICH_HOST_PORT}${NC}"
fi
echo -e "   (Replace ${YELLOW}${IMMICH_ACCESS_IP_SUGGESTION}${NC} with your server's actual IP address if needed, or use localhost if running on your desktop)"
echo
echo -e "${BOLD}${CYAN}Database Password (if auto-generated or you forgot):${NC}"
echo -e "   Username: ${YELLOW}${DB_USERNAME}${NC}"
echo -e "   Password: ${YELLOW}${DB_PASSWORD}${NC} (store this safely!)"
echo
echo -e "${BOLD}${CYAN}Managing Containers:${NC}"
echo -e "   View logs: ${GREEN}docker logs <container_name>${NC}"
echo -e "   Stop a container: ${GREEN}docker stop <container_name>${NC}"
echo -e "   Start a container: ${GREEN}docker start <container_name>${NC}"
echo -e "   Stop all Immich containers:"
echo -e "     ${GREEN}docker stop ${CONTAINER_NAME_WEB} ${CONTAINER_NAME_SERVER} ${CONTAINER_NAME_MICROSERVICES} ${CONTAINER_NAME_ML} ${CONTAINER_NAME_TYPESENSE} ${CONTAINER_NAME_REDIS} ${CONTAINER_NAME_POSTGRES}${NC}"
echo -e "   Remove all Immich containers (after stopping):"
echo -e "     ${GREEN}docker rm ${CONTAINER_NAME_WEB} ${CONTAINER_NAME_SERVER} ${CONTAINER_NAME_MICROSERVICES} ${CONTAINER_NAME_ML} ${CONTAINER_NAME_TYPESENSE} ${CONTAINER_NAME_REDIS} ${CONTAINER_NAME_POSTGRES}${NC}"
echo

header "🚀 Getting Started with Immich 🚀"
echo -e "${BOLD}1. Initial Admin User Setup:${NC}"
echo -e "   - When you first access Immich via the web UI, it will prompt you to create an admin account."
echo
echo -e "${BOLD}2. Mobile App Setup:${NC}"
echo -e "   - Download the Immich mobile app."
if [ -n "$REVERSE_PROXY_DOMAIN_ACCESS_MSG" ]; then
    echo -e "   - Server Endpoint URL: Try ${GREEN}https://${REVERSE_PROXY_DOMAIN_ACCESS}${NC} first (if reverse proxy configured)."
    echo -e "     Otherwise, use ${GREEN}http://${IMMICH_ACCESS_IP_SUGGESTION}:${IMMICH_HOST_PORT}${NC}"
else
    echo -e "   - Server Endpoint URL: ${GREEN}http://${IMMICH_ACCESS_IP_SUGGESTION}:${IMMICH_HOST_PORT}${NC}"
fi
echo
echo -e "${BOLD}3. Uploading, Key Features, Tips & Tricks, Backups, Updates:${NC}"
echo -e "   Please refer to the Immich documentation (https://immich.app) and community resources."
echo -e "   ${YELLOW}Backups are CRUCIAL:${NC} Remember to back up:"
echo -e "     - Your photos/videos folder: ${YELLOW}${UPLOAD_LOCATION}${NC}"
echo -e "     - Your PostgreSQL data folder: ${YELLOW}${DB_DATA_LOCATION}${NC}"
echo -e "     - Your Typesense data folder: ${YELLOW}${TYPESENSE_DATA_PATH}${NC}"
echo -e "     - Your ML model cache (optional but saves re-download): ${YELLOW}${MODEL_CACHE_LOCATION}${NC}"
echo -e "     - The generated '${COMPOSE_FILE}' (contains your configuration)."
echo
echo -e "${BOLD}${GREEN}Enjoy your self-hosted photo and video management with Immich!${NC}"
echo

exit 0
