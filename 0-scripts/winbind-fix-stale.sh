#!/bin/bash

# --- fix-yor-stale-ip.sh ---
# Nuclear option to fix the stale IP issue for hostname "Yor"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

HOST="Yor"
OLD_IP="192.168.1.246"
CORRECT_IP="192.168.1.29"

print_header() {
    echo -e "\n${CYAN}${BOLD}========================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}========================================${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Re-executing with sudo...${NC}"
    exec sudo bash "$0" "$@"
fi

print_header "Diagnostic: Finding Stale IP Sources"

echo -e "${YELLOW}Checking where 192.168.1.246 is coming from...${NC}\n"

# 1. Check /etc/hosts
echo -e "${BOLD}1. Checking /etc/hosts:${NC}"
if grep -i "yor" /etc/hosts 2>/dev/null; then
    echo -e "${RED}   Found Yor in /etc/hosts!${NC}"
else
    echo -e "${GREEN}   No entry in /etc/hosts${NC}"
fi

# 2. Check systemd-resolved
echo -e "\n${BOLD}2. Checking systemd-resolved cache:${NC}"
if command -v resolvectl &>/dev/null; then
    echo -e "${GREEN}→ resolvectl query $HOST${NC}"
    resolvectl query "$HOST" 2>&1 || echo -e "${YELLOW}   No cached entry${NC}"
fi

# 3. Check Samba/Winbind cache
echo -e "\n${BOLD}3. Checking Samba/Winbind NetBIOS cache:${NC}"
if command -v nmblookup &>/dev/null; then
    echo -e "${GREEN}→ nmblookup $HOST${NC}"
    nmblookup "$HOST" 2>&1
fi

# 4. Check getent (NSS)
echo -e "\n${BOLD}4. Checking NSS resolution (getent):${NC}"
echo -e "${GREEN}→ getent hosts $HOST${NC}"
getent hosts "$HOST" 2>&1

# 5. Check ARP cache
echo -e "\n${BOLD}5. Checking ARP cache for old IP:${NC}"
echo -e "${GREEN}→ ip neigh show | grep $OLD_IP${NC}"
ip neigh show | grep "$OLD_IP" || echo -e "${GREEN}   No ARP entry for old IP${NC}"

# 6. Check nscd cache
echo -e "\n${BOLD}6. Checking nscd cache:${NC}"
if systemctl is-active --quiet nscd; then
    echo -e "${YELLOW}   nscd is running (might be caching)${NC}"
else
    echo -e "${GREEN}   nscd is not running${NC}"
fi

# 7. Check avahi/mDNS
echo -e "\n${BOLD}7. Checking Avahi/mDNS:${NC}"
if command -v avahi-resolve &>/dev/null; then
    echo -e "${GREEN}→ avahi-resolve -n $HOST.local${NC}"
    timeout 2 avahi-resolve -n "$HOST.local" 2>&1 || echo -e "${YELLOW}   No mDNS response${NC}"
fi

# 8. Check DNS
echo -e "\n${BOLD}8. Checking DNS resolution:${NC}"
echo -e "${GREEN}→ dig $HOST.home +short${NC}"
dig "$HOST.home" +short 2>&1 | head -5 || echo -e "${YELLOW}   No DNS response${NC}"

print_header "NUCLEAR FIX: Removing ALL Stale Entries"

read -p "Do you want to proceed with the nuclear fix? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "\n${YELLOW}Step 1: Removing any /etc/hosts entries for Yor...${NC}"
sed -i "/$HOST/d" /etc/hosts
echo -e "${GREEN}✓ Done${NC}"

echo -e "\n${YELLOW}Step 2: Adding correct entry to /etc/hosts...${NC}"
echo "$CORRECT_IP    $HOST $HOST.home" >> /etc/hosts
echo -e "${GREEN}✓ Added: $CORRECT_IP    $HOST $HOST.home${NC}"

echo -e "\n${YELLOW}Step 3: Stopping ALL name resolution services...${NC}"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl stop nscd 2>/dev/null || true
systemctl stop avahi-daemon 2>/dev/null || true
systemctl stop smbd nmbd winbind 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Services stopped${NC}"

echo -e "\n${YELLOW}Step 4: Killing any hanging processes...${NC}"
pkill -9 systemd-resolve 2>/dev/null || true
pkill -9 nscd 2>/dev/null || true
pkill -9 avahi-daemon 2>/dev/null || true
pkill -9 smbd 2>/dev/null || true
pkill -9 nmbd 2>/dev/null || true
pkill -9 winbindd 2>/dev/null || true
sleep 1
echo -e "${GREEN}✓ Processes killed${NC}"

echo -e "\n${YELLOW}Step 5: Clearing ALL caches...${NC}"

# Flush systemd-resolved
if [ -f /run/systemd/resolve/stub-resolv.conf ]; then
    echo -e "${GREEN}→ rm -f /run/systemd/resolve/stub-resolv.conf${NC}"
    rm -f /run/systemd/resolve/stub-resolv.conf
fi

# Clear nscd cache
if [ -d /var/cache/nscd ]; then
    echo -e "${GREEN}→ rm -rf /var/cache/nscd/*${NC}"
    rm -rf /var/cache/nscd/*
fi

# Clear Samba caches
if [ -d /var/cache/samba ]; then
    echo -e "${GREEN}→ rm -rf /var/cache/samba/*${NC}"
    rm -rf /var/cache/samba/*
fi

# Clear winbind cache
if [ -d /var/lib/samba ]; then
    echo -e "${GREEN}→ rm -f /var/lib/samba/*.tdb${NC}"
    rm -f /var/lib/samba/winbindd_cache.tdb 2>/dev/null || true
    rm -f /var/lib/samba/gencache*.tdb 2>/dev/null || true
fi

# Flush ARP cache
echo -e "${GREEN}→ ip neigh flush all${NC}"
ip neigh flush all

echo -e "${GREEN}✓ All caches cleared${NC}"

echo -e "\n${YELLOW}Step 6: Restarting services...${NC}"
systemctl start systemd-resolved 2>/dev/null || true
systemctl start nscd 2>/dev/null || true
systemctl start avahi-daemon 2>/dev/null || true
systemctl start smbd 2>/dev/null || true
systemctl start nmbd 2>/dev/null || true
systemctl start winbind 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Services restarted${NC}"

print_header "Verification"

echo -e "\n${BOLD}Check 1: /etc/hosts entry${NC}"
echo -e "${GREEN}→ grep -i yor /etc/hosts${NC}"
grep -i yor /etc/hosts

echo -e "\n${BOLD}Check 2: getent resolution${NC}"
echo -e "${GREEN}→ getent hosts $HOST${NC}"
getent hosts "$HOST"

echo -e "\n${BOLD}Check 3: Ping test${NC}"
echo -e "${GREEN}→ ping -c 3 $HOST${NC}"
if ping -c 3 -W 2 "$HOST" 2>&1 | grep -q "from $CORRECT_IP"; then
    echo -e "\n${GREEN}${BOLD}✓✓✓ SUCCESS! ✓✓✓${NC}"
    echo -e "${GREEN}Yor is now resolving to the correct IP: $CORRECT_IP${NC}"
else
    echo -e "\n${RED}${BOLD}Still failing...${NC}"
    echo -e "${YELLOW}The issue may be on the Windows side.${NC}"
    echo -e "\n${CYAN}On the Windows machine 'Yor', run PowerShell as Admin:${NC}"
    echo -e "${GREEN}ipconfig /flushdns${NC}"
    echo -e "${GREEN}nbtstat -RR${NC}"
    echo -e "${GREEN}netsh interface ip delete arpcache${NC}"
    echo -e "${GREEN}Restart-Computer${NC}"
fi

print_header "Complete"
