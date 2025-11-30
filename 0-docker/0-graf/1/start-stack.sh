#!/bin/bash
# Author: Roy Wiseman 2025-01

# Monitoring Stack Setup Script (Prometheus, Grafana, Node Exporter setup instructions)

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration Variables ---
CONFIG_ROOT="$HOME/.config/monitoring-stack" # Base directory for config files
ENV_FILE=".env-monitoring" # Environment file for docker compose
DOCKER_COMPOSE_FILE="docker-compose.yaml" # The compose file name

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
    exit 1
fi

# --- Ensure yq is installed ---
if ! command -v yq &> /dev/null; then
    echo "yq command not found. Installing yq..."
    YQ_BINARY="yq_linux_amd64"
    case $(uname -m) in
        x86_64) YQ_BINARY="yq_linux_amd64";;
        aarch64) YQ_BINARY="yq_linux_arm64";;
        *) echo "Unsupported architecture for yq: $(uname -m). Please install yq manually."; exit 1;;
    esac

    if curl -L "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -o /usr/local/bin/yq; then
        sudo chmod +x /usr/local/bin/yq
        echo "yq installed successfully to /usr/local/bin."
    else
        echo "❌ Failed to download or install yq. Please install yq manually (e.g., via snap 'sudo snap install yq')."
        exit 1
    fi
fi

echo "🔍 Parsing $DOCKER_COMPOSE_FILE..."

# Extract container names and host ports using yq
CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
# Note: We don't need images for the main checks here, focusing on names and ports
PORTS=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" | cut -d: -f1 | grep -E '^[0-9]+$' | sort -u))

echo
echo "Container names:"
if [ "${#CONTAINER_NAMES[@]}" -eq 0 ]; then
    echo "- No services defined in compose file?"
else
    for name in "${CONTAINER_NAMES[@]}"; do
        echo "- $name"
    done
fi

echo "" # Add a blank line for separation

echo "Host ports to be used:"
if [ "${#PORTS[@]}" -eq 0 ]; then
    echo "- No host ports exposed"
else
    for port in "${PORTS[@]}"; do
        echo "- $port"
    done
fi

echo "" # Add a blank line for separation

# --- Conflict Checks ---

# Check for container name conflicts
echo "🔎 Checking for existing containers that could conflict..."
container_conflict_found=false
for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
        echo "❌ A container named \"$name\" already exists. Remove it with:"
        echo "    docker rm -f $name"
        container_conflict_found=true
    fi
done
if [ "$container_conflict_found" = true ]; then
    echo "‼️ One or more container name conflicts were found. Please resolve them before proceeding."
    exit 1
fi
echo "✅ No conflicting container names found."

# Check for port conflicts
echo "🔎 Checking for port conflicts..."
port_conflict_found=false
for port in "${PORTS[@]}"; do
    # Check if the port is in use (TCP or UDP, listening)
    if ss -tuln | grep -q ":$port "; then
        echo "❌ Port $port is already in use. Please stop the service using it or change the docker-compose config."
        port_conflict_found=true
    fi
done
if [ "$port_conflict_found" = true ]; then
    echo "‼️ One or more port conflicts were found. Please resolve them before proceeding."
    exit 1
fi
echo "✅ No conflicting ports found."

# Note: Image conflict check is less critical for standard images like prom/prometheus or grafana/grafana
# compared to custom or actively developed images, so skipping it for simplicity.


# --- If reach here, all critical checks passed, so proceed with system checks and setup ---
echo "✅ All conflict checks passed. Proceeding with system checks and setup..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo "Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'."
        exit 1 # Exit to ensure user relogs for group changes
    else
        echo "❌ Failed to install Docker."
        exit 1
    fi
else
    echo "Docker is already installed."
fi

# Check Docker Compose plugin
if ! docker compose version &>/dev/null; then
    echo "Docker Compose plugin not found. Installing..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins" || { echo "❌ Failed to create Docker config directory."; exit 1; }
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if curl -SL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
      -o "$DOCKER_CONFIG/cli-plugins/docker-compose"; then
      chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose" || { echo "❌ Failed to set execute permissions on docker-compose plugin."; exit 1; }
      echo "Docker Compose plugin installed successfully."
    else
      echo "❌ Failed to download Docker Compose plugin."
      exit 1
    fi
fi

# Detect UID and GID
PUID=$(id -u)
PGID=$(id -g)
echo "Using UID=$PUID and GID=$PGID for volume permissions."

# --- Monitoring Configuration Setup ---
echo
echo "--- Monitoring Target Configuration ---"
DEFAULT_TARGET_IPS="192.168.1.140,192.168.1.29"
DEFAULT_EXPORTER_PORT="9100" # Default port for Node Exporter

read -p "Enter comma-separated IP addresses of machines to monitor [default: $DEFAULT_TARGET_IPS]: " TARGET_IPS_INPUT
TARGET_IPS="${TARGET_IPS_INPUT:-$DEFAULT_TARGET_IPS}"

read -p "Enter the Node Exporter port on target machines [default: $DEFAULT_EXPORTER_PORT]: " EXPORTER_PORT_INPUT
NODE_EXPORTER_PORT="${EXPORTER_PORT_INPUT:-$DEFAULT_EXPORTER_PORT}"

echo "Monitoring targets: $TARGET_IPS"
echo "Node Exporter port: $NODE_EXPORTER_PORT"

# Create config directories
echo "Creating necessary config directories..."
mkdir -p "$CONFIG_ROOT"/prometheus "$CONFIG_ROOT"/grafana || { echo "❌ Error creating config directories"; exit 1; }
# Ensure data sub-directories are created if needed by compose file volume definitions
mkdir -p "$CONFIG_ROOT"/prometheus/data "$CONFIG_ROOT"/grafana/data || { echo "❌ Error creating data subdirectories"; exit 1; }

# Set ownership on config directories for the PUID/PGID user that containers will run as
# This ensures containers can write to the config volumes.
echo "Setting ownership on $CONFIG_ROOT to $PUID:$PGID..."
if ! sudo chown -R "$PUID:$PGID" "$CONFIG_ROOT"; then
    echo "❌ Warning: Error setting ownership on $CONFIG_ROOT. Volume write permissions might fail."
    echo "Proceeding, but you may need to manually run: sudo chown -R $PUID:$PGID $CONFIG_ROOT"
    # Decided not to exit here, let docker compose potentially fail first.
fi


# --- Generate Prometheus Configuration File (prometheus.yml) ---
PROM_CONFIG_FILE="$CONFIG_ROOT/prometheus/prometheus.yml"
echo "Generating Prometheus configuration file: $PROM_CONFIG_FILE"

# Split the comma-separated IPs and format them for the targets list
# Example: "192.168.1.140,192.168.1.29" becomes "['192.168.1.140:9100', '192.168.1.29:9100']"
TARGET_LIST=""
IFS=',' read -ra ADDR <<< "$TARGET_IPS"
for ip in "${ADDR[@]}"; do
    # Trim whitespace from IP
    trimmed_ip=$(echo "$ip" | xargs)
    if [ -n "$trimmed_ip" ]; then # Check if IP is not empty
        TARGET_LIST+="'${trimmed_ip}:${NODE_EXPORTER_PORT}', "
    fi
done
# Remove the trailing comma and space
TARGET_LIST=$(echo "$TARGET_LIST" | sed 's/, $//')

# Write the prometheus.yml file using a heredoc
cat << EOF > "$PROM_CONFIG_FILE"
global:
  scrape_interval: 15s # How frequently to scrape targets (e.g., every 15 seconds)
  evaluation_interval: 15s # Evaluate rules every 15 seconds (if you add rules)
  # scrape_timeout is default to the same as the global scrape_interval.

# Alerting configuration (optional for basic setup)
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets: ['localhost:9093'] # If running Alertmanager

# Load rules once and periodically evaluate them (optional)
# rule_files:
#   - "alert.rules"

# A list of scrape configurations.
scrape_configs:
  # Job for scraping Prometheus itself
  - job_name: 'prometheus'
    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.
    static_configs:
      - targets: ['localhost:9090'] # Prometheus monitors itself

  # Job for scraping Node Exporters on target machines
  - job_name: 'node_exporter'
    static_configs:
      - targets: [${TARGET_LIST}] # Targets specified by the user script
    # Optional: Add labels to the targets for easier filtering in Grafana/Prometheus
    # relabel_configs:
    #   - source_labels: [__address__]
    #     regex: '(.*):.*'
    #     target_label: instance_ip
    #   - source_labels: [__address__]
    #     target_label: instance # Keep original target string

EOF

echo "✅ Prometheus configuration file generated."
echo "--- End Monitoring Configuration Setup ---"


# --- Create .env file ---
echo "Creating .env file..."
env_content=""
env_content+="PUID=$PUID"$'\n'
env_content+="PGID=$PGID"$'\n'
env_content+="CONFIG_ROOT=${CONFIG_ROOT}"$'\n'
# We don't need TARGET_IPS or NODE_EXPORTER_PORT in the .env unless the compose
# file or containers explicitly used them (Prometheus uses the config file).
# Keep them for consistency, but note they aren't used by the current compose.
# env_content+="TARGET_IPS=\"${TARGET_IPS}\""$'\n'
# env_content+="NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT}"$'\n'
env_content+="TZ=$(cat /etc/timezone 2>/dev/null || echo 'Europe/Amsterdam')" # Attempt to get timezone
env_content+=$'\n' # Add a final newline

echo "$env_content" > "$ENV_FILE"

echo ".env file created with the following content:"
cat "$ENV_FILE"
echo # Add a newline


# --- Launch the stack ---
echo "Launching the Docker monitoring stack with docker compose..."
if docker compose --env-file "$ENV_FILE" -f "$DOCKER_COMPOSE_FILE" up -d; then
    echo "✅ Docker monitoring stack launched successfully!"
else
    echo "❌ Failed to launch Docker monitoring stack."
    # Keep the .env file and config for debugging
    exit 1
fi

echo "✅ Monitoring stack setup complete!"
echo

# --- Post-Setup Instructions ---

echo "--- Next Steps ---"
echo "1. Install Node Exporter on your target machines:"
echo "   - For 192.168.1.140"
echo "   - For 192.168.1.29"
echo "   You can usually install it via your distribution's package manager (e.g., 'sudo apt update && sudo apt install prometheus-node-exporter' on Debian/Ubuntu)"
echo "   or by running it as a Docker container on those hosts:"
echo "     docker run -d --name node_exporter --net=host --restart=unless-stopped prom/node-exporter"
echo "   Ensure Node Exporter is running and listening on port $NODE_EXPORTER_PORT."
echo
echo "2. Open firewall port $NODE_EXPORTER_PORT on the target machines:"
echo "   Ensure that the machine running Prometheus ($HOSTNAME) can connect to port $NODE_EXPORTER_PORT"
echo "   on 192.168.1.140 and 192.168.1.29."
echo "   Example (UFW): 'sudo ufw allow from <Prometheus_Server_IP> to any port $NODE_EXPORTER_PORT'"
echo
echo "3. Access the services:"
echo "   Prometheus Web UI: http://<Your_Server_IP>:9090"
echo "   Grafana Web UI:    http://<Your_Server_IP>:3000"
echo
echo "4. Configure Grafana:"
echo "   - Log in to Grafana (default user/pass: admin/admin). You will be prompted to change the password."
echo "   - Add a data source: Select 'Prometheus'. The URL will be 'http://prometheus:9090' (using the service name from docker-compose)."
echo "   - Import dashboards: Go to the Dashboards -> Import section."
echo "     - Search Grafana Labs for 'Node Exporter Full'. Common IDs are 1860, 11074, or 11075."
echo "     - Enter the ID and click 'Load'. Select your Prometheus data source."
echo "     - You should now see dashboards visualizing the metrics from your target machines!"
echo
echo "Monitoring stack is ready, Boss. Awaiting your command to proceed with Node Exporter installations on the targets."
