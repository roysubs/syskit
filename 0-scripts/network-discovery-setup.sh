#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-02
# Improved version with critical fixes
# Preserves configs and doesn't reinstall unnecessarily

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logging setup
LOG_FILE="/var/log/network-discovery-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Setup started at $(date) ==="

### Dependency check
check_dependencies() {
    local deps=(python3 systemctl sed grep awk)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required commands: ${missing[*]}${NC}"
        echo "Please install these packages and try again."
        exit 1
    fi
}

echo "🔍 Checking dependencies..."
check_dependencies
echo "✅ All dependencies present"

### Introduction
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Linux Network Discovery Setup Script v4 (Enhanced)       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This script will:${NC}"
echo "  1. Set a custom hostname for this machine"
echo "  2. Configure Avahi (mDNS) for .local name resolution"
echo "  3. SAFELY update Samba for Windows network browsing"
echo "  4. Enable WSDD (Web Service Discovery) for Windows 10/11"
echo "  5. Set up proper firewall rules if needed"
echo ""
echo -e "${GREEN}✅ NO unnecessary package reinstalls${NC}"
echo -e "${GREEN}✅ PRESERVES all existing Samba shares${NC}"
echo -e "${GREEN}✅ Only updates what's actually needed${NC}"
echo -e "${GREEN}✅ Logs everything to: $LOG_FILE${NC}"
echo ""
echo -e "${BLUE}ℹ️  Service Overview:${NC}"
echo "  • Avahi: Discovery for macOS/Linux/iOS (hostname.local)"
echo "  • WSDD: Discovery for Windows 10/11 (Network Explorer)"
echo "  • Samba: File sharing + legacy Windows discovery"
echo ""
read -rp "$(echo -e ${GREEN})Do you want to continue? [y/N]: $(echo -e ${NC})" continue_choice
if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
  echo "❌ Setup cancelled by user"
  exit 0
fi

### Hostname setup
echo ""
read -rp "📛 Enter desired hostname for this system (no spaces): " new_hostname
if [[ -z "$new_hostname" ]]; then
  echo "❌ Hostname cannot be empty"
  exit 1
fi

if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "❌ Hostname can only contain letters, numbers, and hyphens"
  exit 1
fi

echo ""
echo -e "${GREEN}🔧 Setting hostname to '$new_hostname'...${NC}"
sudo hostnamectl set-hostname "$new_hostname"

### Update /etc/hosts
echo "🔁 Updating /etc/hosts..."
sudo sed -i.bak "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts 2>/dev/null || true
if ! grep -q "127.0.1.1" /etc/hosts; then
  echo -e "127.0.1.1\t$new_hostname" | sudo tee -a /etc/hosts > /dev/null
fi

### Avahi - SMART installation
echo ""
if dpkg -l 2>/dev/null | grep -q "^ii  avahi-daemon"; then
  echo "✅ Avahi is already installed - skipping installation"
else
  echo "📦 Installing avahi-daemon (mDNS responder)..."
  sudo apt-get update -qq
  pkg_install avahi-daemon avahi-utils libnss-mdns
  echo "✅ Avahi installed"
fi

echo "🔧 Configuring Avahi..."
sudo tee /etc/avahi/avahi-daemon.conf > /dev/null <<EOF
[server]
host-name=$new_hostname
domain-name=local
use-ipv4=yes
use-ipv6=yes
allow-interfaces=
deny-interfaces=
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes

[reflector]
enable-reflector=no

[rlimits]
EOF

sudo systemctl enable avahi-daemon 2>/dev/null || true
sudo systemctl restart avahi-daemon
echo "✅ Avahi configured and running"

### Samba - SMART handling with ROBUST detection
echo ""
samba_installed=false
has_custom_shares=false

# FIXED: Multiple detection methods - belt and suspenders approach
samba_detected=false

# Method 1: Check if smbd binary exists
if command -v smbd &> /dev/null; then
  samba_detected=true
fi

# Method 2: Check if package is installed (try multiple methods)
if dpkg -l samba 2>/dev/null | grep -q "^ii"; then
  samba_detected=true
fi

# Method 3: Check if config file exists
if [ -f /etc/samba/smb.conf ]; then
  samba_detected=true
fi

# Method 4: Check if service exists
if systemctl list-unit-files smbd.service 2>/dev/null | grep -q smbd.service; then
  samba_detected=true
fi

if [ "$samba_detected" = true ]; then
  echo "✅ Samba is already installed - skipping installation"
  samba_installed=true

  # FIXED: Better custom share detection
  if [ -f /etc/samba/smb.conf ]; then
    # Check for share definitions beyond default ones
    if grep '^\[.*\]' /etc/samba/smb.conf | grep -vE '^\[(global|homes|printers|print\$)\]' | grep -q .; then
      has_custom_shares=true
      echo "✅ Existing custom Samba shares detected - will preserve them"
    fi
  fi
else
  read -rp "📁 Install Samba for file sharing and NetBIOS discovery? [Y/n]: " samba_opt
  if [[ ! "$samba_opt" =~ ^[Nn]$ ]]; then
    echo "📦 Installing Samba..."
    pkg_install samba smbclient
    samba_installed=true
    echo "✅ Samba installed"
  fi
fi

### Configure Samba PROPERLY
if [ "$samba_installed" = true ]; then
  echo "🔧 Configuring Samba for network discovery..."

  # ALWAYS backup with timestamp
  if [ -f /etc/samba/smb.conf ]; then
    backup_file="/etc/samba/smb.conf.bak.$(date +%Y%m%d-%H%M%S)"
    sudo cp /etc/samba/smb.conf "$backup_file"
    echo "📦 Backed up existing config to: $backup_file"
  fi

  if [ "$has_custom_shares" = true ]; then
    # SAFE MODE: Update only [global] section settings
    echo "🔧 Updating [global] section while preserving all shares..."

    # FIXED: Pass hostname to Python script
    sudo python3 - "$new_hostname" <<'PYTHON_SCRIPT'
import re
import sys

config_file = '/etc/samba/smb.conf'
hostname = sys.argv[1] if len(sys.argv) > 1 else 'localhost'

# Settings to add/update
settings = {
    'netbios name': hostname,
    'local master': 'yes',
    'preferred master': 'yes',
    'os level': '35',
    'wins support': 'no',
    'dns proxy': 'yes',
    'name resolve order': 'bcast host lmhosts wins',
}

try:
    with open(config_file, 'r') as f:
        lines = f.readlines()

    # Find [global] section
    in_global = False
    result_lines = []
    settings_added = {k: False for k in settings.keys()}

    for i, line in enumerate(lines):
        # Check if we're entering [global] section
        if re.match(r'^\s*\[global\]\s*$', line, re.IGNORECASE):
            in_global = True
            result_lines.append(line)
            continue

        # Check if we're leaving [global] section (entering another section)
        if in_global and re.match(r'^\s*\[.+\]\s*$', line):
            # We've reached the end of [global], add any missing settings
            for key, value in settings.items():
                if not settings_added[key]:
                    result_lines.append(f'   {key} = {value}\n')
                    settings_added[key] = True
            in_global = False

        # If we're in global section, check if this line is one of our settings
        if in_global:
            matched = False
            for key in settings.keys():
                # Match both active and commented lines
                if re.match(rf'^\s*;?\s*{re.escape(key)}\s*=', line, re.IGNORECASE):
                    # Replace with our setting
                    result_lines.append(f'   {key} = {settings[key]}\n')
                    settings_added[key] = True
                    matched = True
                    break

            if not matched:
                result_lines.append(line)
        else:
            result_lines.append(line)

    # If [global] section extends to end of file, add missing settings
    if in_global:
        for key, value in settings.items():
            if not settings_added[key]:
                result_lines.append(f'   {key} = {value}\n')

    # Write back
    with open(config_file, 'w') as f:
        f.writelines(result_lines)

    print("✅ Network discovery settings updated in [global] section")

except Exception as e:
    print(f"❌ Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT

    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Failed to update Samba configuration${NC}"
      if [ -n "${backup_file:-}" ]; then
        echo "Restoring backup..."
        sudo cp "$backup_file" /etc/samba/smb.conf
      fi
      exit 1
    fi

  else
    # No custom shares - safe to create new config
    echo "📝 Creating new Samba configuration (no custom shares detected)..."
    sudo tee /etc/samba/smb.conf > /dev/null <<EOF
[global]
   workgroup = WORKGROUP
   netbios name = $new_hostname
   server string = %h server (Samba, Linux)

   # Network discovery settings
   server role = standalone server
   local master = yes
   preferred master = yes
   os level = 35

   # Name resolution
   wins support = no
   dns proxy = yes
   name resolve order = bcast host lmhosts wins

   # Security settings
   security = user
   map to guest = bad user
   guest account = nobody

   # Compatibility
   server min protocol = SMB2
   client min protocol = SMB2

   # Logging
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file

# Example share (uncomment and customize as needed)
#[Public]
#   comment = Public Folder
#   path = /srv/samba/public
#   browseable = yes
#   writable = no
#   guest ok = yes
#   read only = yes
EOF
  fi

  # Test configuration
  echo "🧪 Testing Samba configuration..."
  if sudo testparm -s /etc/samba/smb.conf >/dev/null 2>&1; then
    echo "✅ Samba configuration is valid"
  else
    echo -e "${RED}⚠️  Samba configuration has errors. Running testparm:${NC}"
    sudo testparm -s /etc/samba/smb.conf
    read -rp "Continue anyway? [y/N]: " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
      if [ -n "${backup_file:-}" ]; then
        echo "Restoring backup..."
        sudo cp "$backup_file" /etc/samba/smb.conf
      fi
      exit 1
    fi
  fi

  echo "🔄 Restarting Samba services..."
  sudo systemctl enable smbd nmbd 2>/dev/null || true
  sudo systemctl restart smbd nmbd
  echo "✅ Samba services running"
fi

### WSDD - SMART installation with improved configuration
echo ""
if command -v wsdd &> /dev/null && [ -f /etc/systemd/system/wsdd.service ]; then
  echo "✅ WSDD is already installed - updating configuration..."
  # Update service file with workgroup
  sudo tee /etc/systemd/system/wsdd.service > /dev/null <<EOF
[Unit]
Description=Web Service Discovery host daemon
After=network.target avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wsdd --shortlog --workgroup WORKGROUP --hostname $new_hostname
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart wsdd 2>/dev/null || true
else
  echo "📦 Installing WSDD for Windows 10/11 discovery..."
  
  # Ensure git and python3 are available
  if ! command -v git &> /dev/null; then
    echo "Installing git..."
    pkg_install git
  fi
  if ! command -v python3 &> /dev/null; then
    echo "Installing python3..."
    pkg_install python3
  fi
  
  # FIXED: Add error handling for git clone
  cd /tmp
  if [ ! -d "wsdd" ]; then
    if ! git clone https://github.com/christgau/wsdd.git; then
      echo -e "${RED}❌ Failed to clone WSDD repository${NC}"
      echo "Please check your internet connection and try again"
      exit 1
    fi
  fi
  
  cd wsdd
  sudo cp src/wsdd.py /usr/local/bin/wsdd
  sudo chmod +x /usr/local/bin/wsdd

  # IMPROVED: Better service configuration with workgroup
  sudo tee /etc/systemd/system/wsdd.service > /dev/null <<EOF
[Unit]
Description=Web Service Discovery host daemon
After=network.target avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wsdd --shortlog --workgroup WORKGROUP --hostname $new_hostname
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable wsdd
  sudo systemctl start wsdd
  echo "✅ WSDD installed and started"
fi

### Firewall
echo ""
if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "🌐 Configuring ufw firewall..."
  sudo ufw allow 5353/udp comment "mDNS" 2>/dev/null || true

  if [ "$samba_installed" = true ]; then
    sudo ufw allow 137/udp comment "NetBIOS Name" 2>/dev/null || true
    sudo ufw allow 138/udp comment "NetBIOS Datagram" 2>/dev/null || true
    sudo ufw allow 139/tcp comment "NetBIOS Session" 2>/dev/null || true
    sudo ufw allow 445/tcp comment "SMB" 2>/dev/null || true
  fi

  sudo ufw allow 3702/udp comment "WSDD" 2>/dev/null || true
  sudo ufw allow 5357/tcp comment "WSDD HTTP" 2>/dev/null || true
  echo "✅ Firewall configured"
else
  echo "ℹ️  UFW not active - skipping firewall"
fi

### IMPROVED: Verify services with better output
echo ""
echo "🔍 Verifying services..."
services_ok=true

verify_service() {
    local service=$1
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "✅ ${GREEN}$service is running${NC}"
        return 0
    else
        echo -e "❌ ${RED}$service is not running${NC}"
        echo "   Last 10 log lines:"
        sudo journalctl -u "$service" -n 10 --no-pager | sed 's/^/   /'
        return 1
    fi
}

verify_service "avahi-daemon" || services_ok=false
verify_service "wsdd" || services_ok=false

if [ "$samba_installed" = true ]; then
  verify_service "smbd" || services_ok=false
  verify_service "nmbd" || services_ok=false
fi

### Show configured shares
if [ "$samba_installed" = true ]; then
  echo ""
  echo "📁 Your Samba shares:"
  sudo smbclient -L localhost -N 2>/dev/null | grep -A 100 "Sharename" | grep -E "^\s+[A-Za-z]" || echo "  (none configured yet)"
fi

### NEW: Basic connectivity tests
echo ""
echo "🧪 Running basic connectivity tests..."

# Test Avahi
if avahi-browse -a -t -p 2>/dev/null | grep -q "=.*IPv4.*$new_hostname"; then
  echo "✅ Avahi mDNS is broadcasting"
else
  echo -e "${YELLOW}⚠️  Avahi broadcast not detected (may take a moment)${NC}"
fi

# Test NetBIOS if Samba is installed
if [ "$samba_installed" = true ]; then
  if nmblookup "$new_hostname" 2>/dev/null | grep -q "$new_hostname"; then
    echo "✅ NetBIOS name resolution working"
  else
    echo -e "${YELLOW}⚠️  NetBIOS name not yet resolvable${NC}"
  fi
fi

### Success message
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 Setup Complete!                                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "This machine should now be discoverable as:"
echo -e "  ${BLUE}🔸 ${new_hostname}.local${NC}      (mDNS - macOS/Linux/iOS)"
if [ "$samba_installed" = true ]; then
  echo -e "  ${BLUE}🔸 ${new_hostname}${NC}            (Windows Network Explorer)"
fi
echo ""
echo -e "${YELLOW}🧪 Test from Windows:${NC}"
echo "  1. Open File Explorer → Network"
echo "  2. Look for '${new_hostname}'"
echo "  3. Or type: \\\\${new_hostname}"
echo ""
echo -e "${YELLOW}🧪 Test from macOS/Linux:${NC}"
echo "  ping ${new_hostname}.local"
echo "  avahi-browse -a"
echo ""
if [ "$has_custom_shares" = true ]; then
  echo -e "${GREEN}✅ Your existing Samba shares were preserved!${NC}"
  echo ""
fi
if [ "$samba_installed" = true ]; then
  echo -e "${YELLOW}📝 To set up file sharing:${NC}"
  echo "  1. Create a Samba user: sudo smbpasswd -a \$USER"
  echo "  2. Edit /etc/samba/smb.conf to add shares"
  echo "  3. Restart Samba: sudo systemctl restart smbd"
  echo ""
fi
echo -e "${YELLOW}💡 Important Notes:${NC}"
echo "  • Discovery can take 1-2 minutes to propagate"
echo "  • Ensure Windows network is set to 'Private'"
echo "  • A reboot may be needed for full hostname propagation"
if [ -n "${backup_file:-}" ]; then
  echo "  • Config backup saved: $backup_file"
fi
echo "  • Full setup log: $LOG_FILE"
echo ""

if [ "$services_ok" = false ]; then
  echo -e "${YELLOW}⚠️  Some services had issues. Check logs above or run:${NC}"
  echo "  sudo journalctl -u avahi-daemon -n 50"
  echo "  sudo journalctl -u smbd -n 50"
  echo "  sudo journalctl -u nmbd -n 50"
  echo "  sudo journalctl -u wsdd -n 50"
  echo ""
fi

echo "=== Setup completed at $(date) ==="
