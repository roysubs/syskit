#!/bin/bash
# Author: Gemini (Final Simplified Version)
#
# Simple Nginx Web Server deployed for local network access only.
# Hosts content from ~/.config/docker-nginx/html on host port 9090.
# The site will be accessible at http://<Your Host IP>:9090
#
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
DEFAULT_HOST_PORT="9090"
DEFAULT_CONTAINER_PORT="80"
DEFAULT_CONFIG_DIR="$HOME/.config/docker-nginx"
DEFAULT_HTML_DIR="$DEFAULT_CONFIG_DIR/html"
NGINX_CONTAINER_NAME="popdesk-local-nginx"

# Set file paths
COMPOSE_FILE="$DEFAULT_CONFIG_DIR/docker-compose-local.yml"
NGINX_CONF_DIR="$DEFAULT_CONFIG_DIR/nginx-conf"
NGINX_CONF_FILE="$NGINX_CONF_DIR/default.conf"

# ───[ Helper Functions ]──────────────────────────────────────────
check_dependencies() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}   Nginx Local-Only Web Server Setup${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}[1/5] Checking dependencies...${NC}"

    if ! command -v docker &> /dev/null || ! command -v docker compose &> /dev/null; then
        echo -e "${RED}❌ Docker or Docker Compose not found. Please install both.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ All dependencies met.${NC}"
    echo
}

check_existing_installation() {
    echo -e "${CYAN}[2/5] Checking for existing installation...${NC}"

    if [ -f "$COMPOSE_FILE" ]; then
        echo -e "${YELLOW}⚠️  Existing container detected. Stopping and removing...${NC}"
        cd "$DEFAULT_CONFIG_DIR" && docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
        echo -e "${GREEN}✅ Cleaned up old container.${NC}"
    else
        echo -e "${GREEN}✅ No existing installation found.${NC}"
    fi
    echo
}

gather_configuration() {
    echo -e "${CYAN}[3/5] Gathering configuration...${NC}"
    
    # Create required directories
    mkdir -p "$DEFAULT_HTML_DIR"
    mkdir -p "$NGINX_CONF_DIR"

    # Create index.html if missing
    if [ ! -f "$DEFAULT_HTML_DIR/index.html" ]; then
        echo -e "${YELLOW}⚠️  index.html not found. Creating placeholder.${NC}"
        cat > "$DEFAULT_HTML_DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Popdesk Local Host</title>
</head>
<body>
    <h1>Welcome to Popdesk!</h1>
    <p>This page is hosted successfully via Nginx Docker container on port ${DEFAULT_HOST_PORT}.</p>
    <p>Place your actual index.html file here: ${DEFAULT_HTML_DIR}/index.html</p>
</body>
</html>
EOF
        echo -e "${GREEN}✅ Placeholder index.html created.${NC}"
    fi
    echo
}

create_docker_compose() {
    echo -e "${CYAN}[4/5] Creating Docker Compose configuration...${NC}"

    cat > "$COMPOSE_FILE" << EOF
version: '3.8'
services:
  # ───[ Local Web Server (Nginx) ]──────────────────────────
  nginx-web:
    image: nginx:alpine
    container_name: ${NGINX_CONTAINER_NAME}
    restart: unless-stopped
    ports:
      # Expose the container's port 80 to the host's port 9090
      - "${DEFAULT_HOST_PORT}:${DEFAULT_CONTAINER_PORT}" 
    volumes:
      - ${DEFAULT_HTML_DIR}:/usr/share/nginx/html:ro
      - ${NGINX_CONF_FILE}:/etc/nginx/conf.d/default.conf:ro
    # No external network dependency needed!
EOF

    echo -e "${GREEN}✅ Docker Compose file created.${NC}"
    echo
}

launch_container() {
    echo -e "${CYAN}[5/5] Launching the Nginx container...${NC}"
    cd "$DEFAULT_CONFIG_DIR"
    
    # Launch only the Nginx service
    docker compose -f "$COMPOSE_FILE" up -d

    if [ $? -eq 0 ] && docker ps --format '{{.Names}}' | grep -q "${NGINX_CONTAINER_NAME}"; then
        echo -e "${GREEN}✅ Nginx container launched successfully and is running.${NC}"
    else
        echo -e "${RED}❌ Failed to launch container. Check Docker logs: docker logs ${NGINX_CONTAINER_NAME}${NC}"
        exit 1
    fi
    echo
}

show_final_instructions() {
    # Dynamically get the host's IP address (assuming it's running on the same machine)
    LOCAL_IP=$(hostname -I | awk '{print $1}')

    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    🎉 Local Site Setup Complete! 🎉${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    
    echo -e "${BOLD}1. Place Your Index.html:${NC}"
    echo -e "Copy your Popdesk ${BOLD}index.html${NC} file here:"
    echo -e "    ${CYAN}${DEFAULT_HTML_DIR}/index.html${NC}"
    
    echo -e "${BOLD}2. Access the Site (LOCAL NETWORK):${NC}"
    echo -e "Your site is now available at the following addresses:"
    echo -e "    🌐 ${YELLOW}http://localhost:${DEFAULT_HOST_PORT}${NC}"
    echo -e "    🌐 ${YELLOW}http://${LOCAL_IP}:${DEFAULT_HOST_PORT}${NC}"
    
    echo -e "${BOLD}3. Next Steps (Optional - External Access):${NC}"
    echo -e "If you wish to access this site externally via ${CYAN}yorwise.duckdns.org${NC}, you must:"
    echo -e "  • Set up **Port Forwarding** on your router for TCP port ${DEFAULT_HOST_PORT} to your host machine's IP."
    echo -e "  • You can then access it externally via: ${YELLOW}http://yorwise.duckdns.org:${DEFAULT_HOST_PORT}${NC}"
    echo

    echo -e "${BOLD}🛠  Management:${NC}"
    echo -e "  To restart Nginx after content updates: ${YELLOW}cd ${DEFAULT_CONFIG_DIR} && docker compose -f ${COMPOSE_FILE} restart${NC}"
    echo -e "  View Nginx logs: ${YELLOW}docker logs ${NGINX_CONTAINER_NAME} -f${NC}"
    echo
}

# ───[ Main Execution ]────────────────────────────────────────────
main() {
    check_dependencies
    check_existing_installation
    gather_configuration
    create_docker_compose
    launch_container
    show_final_instructions
}

main "$@"
