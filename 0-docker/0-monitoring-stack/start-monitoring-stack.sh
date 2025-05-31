#!/bin/bash
# Author: Roy Wiseman 2025-03

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
NC='\033[0m' # No Color

# --- Configuration ---
CONFIG_ROOT_APP="$HOME/.config/monitoring-stack" # App-specific config root (e.g., for future Grafana files not in volumes)
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose-monitoring.yaml"
PROMETHEUS_CONFIG_DIR_HOST="./prometheus" # Relative to script location
PROMETHEUS_CONFIG_FILE_HOST="${PROMETHEUS_CONFIG_DIR_HOST}/prometheus.yml"
# Optional, for Grafana provisioning later:
# GRAFANA_PROVISIONING_DIR_HOST="./grafana/provisioning"

# --- Helper Functions ---
log_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}WARN:${NC} $1"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# --- Pre-flight Checks & Setup ---

# Check if docker is installed (simplified from your script)
if [ -f "./docker-setup-deb-variants.sh" ]; then
    log_info "Found docker-setup-deb-variants.sh. Running it..."
    # Ensure it's executable if it exists
    chmod +x ./docker-setup-deb-variants.sh
    "./docker-setup-deb-variants.sh"
fi

set -e # Exit immediately if a command exits with a non-zero status.

# Ensure mikefarah/yq is installed
if ! command -v yq &>/dev/null || ! yq --version 2>&1 | grep -q "mikefarah/yq"; then
    log_info "Installing mikefarah/yq..."
    YQ_ARCH=$(uname -m)
    case "${YQ_ARCH}" in
        x86_64) YQ_BINARY="yq_linux_amd64";;
        aarch64) YQ_BINARY="yq_linux_arm64";;
        *) log_error "Unsupported architecture for yq: ${YQ_ARCH}"; exit 1;;
    esac
    if sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/${YQ_BINARY}" -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq; then
        log_info "yq installed successfully."
    else
        log_error "Failed to install yq. Please install it manually (github.com/mikefarah/yq)."
        exit 1
    fi
else
    log_info "mikefarah/yq is already installed."
fi

log_info "🔍 Parsing ${DOCKER_COMPOSE_FILE}..."

# Extract container names, image names, and host ports
CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
IMAGES=($(yq -r '.services.*.image' "$DOCKER_COMPOSE_FILE"))
PORTS=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" | cut -d: -f1 | grep -E '^[0-9]+$' | sort -u))

if [ "${#CONTAINER_NAMES[@]}" -ne "${#IMAGES[@]}" ]; then
    log_warn "The number of extracted container names (${#CONTAINER_NAMES[@]}) does not match the number of images (${#IMAGES[@]}). Output might be misaligned."
fi

echo
log_info "Containers (and their images) to be used:"
for i in "${!CONTAINER_NAMES[@]}"; do
    name="${CONTAINER_NAMES[$i]}"
    image="${IMAGES[$i]:-N/A}"
    echo "- ${name} (${image})"
done

echo
log_info "Host ports to be used:"
if [ "${#PORTS[@]}" -eq 0 ]; then
    echo "- No host ports exposed."
else
    for port in "${PORTS[@]}"; do
        echo "- ${port}"
    done
fi
echo

# --- Conflict Checks ---
container_conflict_found=false
log_info "🔎 Checking for existing container name conflicts..."
for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
        log_error "A container named \"${name}\" already exists. Remove it with: docker rm -f ${name}"
        container_conflict_found=true
    fi
done
if [ "$container_conflict_found" = true ]; then
    log_error "One or more container name conflicts found. Please resolve them."
    exit 1
fi
log_info "✅ No conflicting container names found."

port_conflict_found=false
log_info "🔎 Checking for port conflicts..."
for port in "${PORTS[@]}"; do
    if ss -tuln | grep -q ":${port} "; then # Checks TCP and UDP listening ports
        log_error "Port ${port} is already in use. Stop the service or change ${DOCKER_COMPOSE_FILE}."
        port_conflict_found=true
    fi
done
if [ "$port_conflict_found" = true ]; then
    log_error "One or more port conflicts found. Please resolve them."
    exit 1
fi
log_info "✅ No conflicting ports found."

log_info "✅ All conflict checks passed."

# --- System Checks & Prerequisite Installation ---
log_info "🛠️ Performing system checks and prerequisite setup..."

# Check Docker
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Attempting to install..."
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        log_warn "Docker installed. Please log out and back in, or run 'newgrp docker' in your current terminal for group changes to take effect BEFORE running this script again."
        exit 1 # Exit to ensure user re-logs or runs newgrp
    else
        log_error "Failed to install Docker. Please install it manually."
        exit 1
    fi
else
    log_info "Docker is already installed."
fi

# Check Docker Compose plugin
if ! docker compose version &>/dev/null; then
    log_info "Docker Compose plugin not found. Attempting to install..."
    DOCKER_CONFIG_PATH=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG_PATH/cli-plugins" || { log_error "Failed to create Docker config directory: $DOCKER_CONFIG_PATH/cli-plugins"; exit 1; }
    # Try to get latest version using yq if curl response is JSON
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | yq -r '.tag_name' 2>/dev/null)
    if [ -z "$LATEST_COMPOSE_VERSION" ] || [[ "$LATEST_COMPOSE_VERSION" == "null" ]]; then # Check if yq failed or returned null
        # Fallback to grep if yq failed or API response wasn't as expected
        LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    if [ -z "$LATEST_COMPOSE_VERSION" ]; then
        log_warn "Could not fetch latest Docker Compose version automatically. Using a recent default: v2.27.1"
        LATEST_COMPOSE_VERSION="v2.27.1" # Fallback version
    else
        log_info "Latest Docker Compose version found: ${LATEST_COMPOSE_VERSION}"
    fi

    log_info "Attempting to download Docker Compose ${LATEST_COMPOSE_VERSION} for $(uname -m)..."
    COMPOSE_URL="https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)"
    if curl -SL "$COMPOSE_URL" -o "$DOCKER_CONFIG_PATH/cli-plugins/docker-compose"; then
        chmod +x "$DOCKER_CONFIG_PATH/cli-plugins/docker-compose" || { log_error "Failed to set execute permissions on docker-compose plugin."; exit 1; }
        log_info "Docker Compose plugin installed successfully."
    else
        log_error "Failed to download Docker Compose plugin from $COMPOSE_URL. Please install it manually."
        exit 1
    fi
else
    log_info "Docker Compose plugin is already installed."
fi


# --- Configuration File and Directory Setup ---
log_info "⚙️ Setting up configuration files and directories..."

# Detect TimeZone, PUID, PGID
TZ=$(timedatectl show --value -p Timezone || echo "Etc/UTC") # Default to Etc/UTC if timedatectl fails
PUID=$(id -u)
PGID=$(id -g)

log_info "Using PUID=${PUID}, PGID=${PGID}, TZ=${TZ}"

# Ensure Prometheus host config directory exists (script creates it if not, but good check)
if [ ! -d "${PROMETHEUS_CONFIG_DIR_HOST}" ]; then
    log_info "Creating Prometheus config directory: ${PROMETHEUS_CONFIG_DIR_HOST}"
    mkdir -p "${PROMETHEUS_CONFIG_DIR_HOST}" || { log_error "Failed to create ${PROMETHEUS_CONFIG_DIR_HOST}"; exit 1; }
fi

# Create a default prometheus.yml if it doesn't exist
if [ ! -f "${PROMETHEUS_CONFIG_FILE_HOST}" ]; then
    log_info "Creating default Prometheus configuration: ${PROMETHEUS_CONFIG_FILE_HOST}"
    cat <<EOF > "${PROMETHEUS_CONFIG_FILE_HOST}"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  # Add more scrape configs here later (e.g., for node_exporter, cadvisor)
EOF
    log_info "Default ${PROMETHEUS_CONFIG_FILE_HOST} created."
else
    log_info "${PROMETHEUS_CONFIG_FILE_HOST} already exists. Skipping creation."
fi

# Create the main application config root directory (defined by CONFIG_ROOT_APP)
# This isn't directly used for volumes in this simple compose file, but good for consistency.
mkdir -p "$CONFIG_ROOT_APP" || { log_error "Error creating base application config directory: $CONFIG_ROOT_APP"; exit 1; }

# --- Create .env file ---
log_info "📝 Creating .env file..."
cat <<EOF > "$ENV_FILE"
# Environment variables for the monitoring stack
TZ=${TZ}
PUID=${PUID}
PGID=${PGID}
CONFIG_ROOT_APP=${CONFIG_ROOT_APP} # Path for any host-based app configs (if not using Docker volumes exclusively)

# Grafana Admin Credentials (CHANGE THESE FOR PRODUCTION!)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin # For production, use a stronger password or manage via Grafana UI/API after first login

# Prometheus data path (internal to container, managed by Docker volume)
# PROMETHEUS_DATA_PATH=/prometheus

# Grafana data path (internal to container, managed by Docker volume)
# GRAFANA_DATA_PATH=/var/lib/grafana
EOF

log_info ".env file created with the following content:"
cat "$ENV_FILE"
echo

# --- Launch Stack ---
log_info "🚀 Launching the Docker monitoring stack with 'docker compose up -d'..."
if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
    log_info "✅ Docker monitoring stack launched successfully!"
else
    log_error "❌ Failed to launch Docker monitoring stack. Check logs above and run 'docker compose logs' for details."
    exit 1
fi

# --- Post-Launch Information ---
echo # Add a blank line for spacing

log_info "🎉 Monitoring Stack Setup Complete! 🎉"
echo # Add a blank line

echo -e "${GREEN}--- How to Get Started ---${NC}"
echo

echo -e "1. ${YELLOW}Prometheus Web UI:${NC}"
echo -e "   - Access it at: ${GREEN}http://localhost:9090${NC} (or http://<your_server_ip>:9090 if not on local machine)"
echo    "   - Here you can:"
echo    "     - Check target status (Status -> Targets). Initially, it should show the 'prometheus' job with one endpoint UP."
echo    "     - Explore metrics using the expression browser (e.g., type 'promhttp_metric_handler_requests_total' and Execute)."
echo -e "   - ${YELLOW}To monitor more services:${NC}"
echo    "     a. Run 'exporters' for those services (e.g., 'node_exporter' for host metrics, 'cAdvisor' for Docker container metrics)."
echo    "     b. Add new 'scrape_configs' sections to your '${PROMETHEUS_CONFIG_FILE_HOST}' file on your host machine."
echo -e "     c. After saving changes to '${PROMETHEUS_CONFIG_FILE_HOST}', restart Prometheus to apply them: ${GREEN}docker compose restart prometheus${NC}"
echo

# Safely extract Grafana user and password for display
GRAFANA_USER_DISPLAY=$(grep "^GRAFANA_ADMIN_USER=" "$ENV_FILE" | cut -d= -f2-)
GRAFANA_PASS_DISPLAY=$(grep "^GRAFANA_ADMIN_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)

echo -e "2. ${YELLOW}Grafana Web UI:${NC}"
echo -e "   - Access it at: ${GREEN}http://localhost:3000${NC} (or http://<your_server_ip>:3000)"
echo    "   - Default login (from .env file, change it after first login!):"
echo -e "     - Username: ${GREEN}${GRAFANA_USER_DISPLAY}${NC}"
echo -e "     - Password: ${GREEN}${GRAFANA_PASS_DISPLAY}${NC}"
echo -e "   - ${YELLOW}First steps in Grafana:${NC}"
echo -e "     a. ${GREEN}Add Prometheus as a Data Source:${NC}"
echo    "        - On first login, Grafana might prompt you. If not, click the gear icon (⚙️ Administration) on the left sidebar -> Data Sources."
echo    "        - Click 'Add data source'."
echo    "        - Select 'Prometheus' from the list."
echo    "        - Settings:"
echo    "          - Name: Prometheus (or any name you like)"
echo -e "          - HTTP URL: ${YELLOW}http://prometheus:9090${NC}"
echo    "            (Grafana can reach Prometheus using its service name 'prometheus' because they are on the same Docker network)."
echo    "          - Access: Server (default)"
echo    "        - Scroll down and click 'Save & Test'. You should see a green checkmark and 'Data source is working'."
echo -e "     b. ${GREEN}Import or Create a Dashboard:${NC}"
echo    "        - To quickly visualize Prometheus itself, import a pre-built dashboard:"
echo    "          - Click the 'Dashboards' icon (four squares) on the left sidebar."
echo    "          - Click 'New' in the top right, then 'Import'."
echo    "          - In the 'Import via grafana.com' field, enter the ID of a Prometheus dashboard. Good ones to start with:"
echo -e "            - ${YELLOW}3662${NC} (Prometheus 2.0 Overview by Vస్టefan Prodan)" # Note: special character might still be an issue depending on terminal
echo -e "            - ${YELLOW}15911${NC} (Prometheus by Fred)"
echo -e "            - ${YELLOW}1860${NC} (Node Exporter Full - if you set up node_exporter later)"
echo    "          - Click 'Load'. Review the options (e.g., select your 'Prometheus' data source if prompted)."
echo    "          - Click 'Import'."
echo    "        - Or, create your own dashboard:"
echo    "          - Click 'Dashboards' -> 'New' -> 'New Dashboard' -> 'Add visualization'."
echo    "          - Select your 'Prometheus' data source."
echo    "          - Use the 'Metrics browser' or write PromQL queries (e.g., 'rate(prometheus_http_requests_total[5m])') to build panels."
echo

echo -e "3. ${YELLOW}Stopping the stack:${NC}"
echo -e "   - To stop all services: ${GREEN}docker compose down${NC} (run from the '~/monitoring-stack' directory)"
echo -e "   - To stop and remove data volumes (all Prometheus/Grafana data will be lost!): ${GREEN}docker compose down -v${NC}"
echo

echo -e "4. ${YELLOW}Viewing logs:${NC}"
echo -e "   - For all services: ${GREEN}docker compose logs -f${NC}"
echo -e "   - For a specific service (e.g., grafana): ${GREEN}docker compose logs -f grafana${NC}"
echo
echo -e "4. ${YELLOW}Remember that both services are on HTTP and NOT on HTTPS:${NC}"
echo -e "   - ${YELLOW}http://192.168.1.140:3000${NC} for Grafana"
echo -e "   - ${YELLOW}http://192.168.1.140:9090${NC} for Prometheus"
echo
echo -e "${GREEN}Happy Monitoring! Remember to change default Grafana credentials for security.${NC}"
