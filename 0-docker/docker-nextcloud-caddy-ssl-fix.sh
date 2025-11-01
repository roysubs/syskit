#!/bin/bash
# Quick SSL Certificate Fix for Nextcloud
# This forces Caddy to retry certificate acquisition

set -e

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="$HOME/.config/nextcloud-stack"

echo -e "${CYAN}SSL Certificate Fix Script${NC}"
echo "============================"
echo

# Check if config exists
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}Config directory not found: $CONFIG_DIR${NC}"
    exit 1
fi

cd "$CONFIG_DIR"

# Load environment
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}.env file not found!${NC}"
    exit 1
fi

echo -e "${CYAN}Domain: ${DOMAIN}${NC}"
echo

# Step 1: Check if there's a backed up docker-compose.yml
if [ -f docker-compose.yml.backup ]; then
    echo -e "${YELLOW}Restoring docker-compose.yml from backup...${NC}"
    cp docker-compose.yml.backup docker-compose.yml
fi

# Step 2: Remove any existing (failed) certificates
echo -e "${CYAN}Clearing old certificate data...${NC}"
docker compose down
sudo rm -rf "$CONFIG_DIR/caddy/data/caddy/certificates" 2>/dev/null || true
sudo rm -rf "$CONFIG_DIR/caddy/data/caddy/locks" 2>/dev/null || true

# Step 3: Create a working Caddyfile
echo -e "${CYAN}Creating optimized Caddyfile...${NC}"

cat > caddy/Caddyfile << EOF
{
    email admin@${DOMAIN}
}

${DOMAIN} {
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
    }
}
EOF

echo -e "${GREEN}✅ Caddyfile updated${NC}"

# Step 4: Restart everything
echo -e "${CYAN}Starting containers...${NC}"
docker compose up -d

echo -e "${GREEN}✅ Containers started${NC}"
echo

# Step 5: Watch Caddy logs for certificate acquisition
echo -e "${CYAN}Watching Caddy logs for certificate acquisition...${NC}"
echo -e "${YELLOW}(Press Ctrl+C to stop watching)${NC}"
echo
echo -e "${BOLD}Look for these messages:${NC}"
echo -e "  ${GREEN}✓ 'certificate obtained'${NC} = Success!"
echo -e "  ${RED}✗ 'timeout' or 'connection' errors${NC} = Port 80 is blocked"
echo
sleep 3

docker logs caddy -f
EOF
