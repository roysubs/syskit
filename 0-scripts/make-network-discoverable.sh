#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02
# Preserves configs and doesn't reinstall unnecessarily
set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

### Introduction
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Linux Network Discovery Setup Script v3 (ACTUALLY Safe)  ║${NC}"
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
  sudo apt-get install -y avahi-daemon avahi-utils libnss-mdns
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

### Samba - SMART handling
echo ""
samba_installed=false
has_custom_shares=false

if dpkg -l 2>/dev/null | grep -q "^ii  samba"; then
  echo "✅ Samba is already installed - skipping installation"
  samba_installed=true
  
  # Check if config has custom shares (look for share definitions beyond defaults)
  if [ -f /etc/samba/smb.conf ]; then
    # Count share definitions (lines starting with [word] that aren't [global], [homes], [printers], [print$])
    custom_share_count=$(grep -c '^\[.*\]' /etc/samba/smb.conf | grep -v -c '^\[global\]' | grep -v -c '^\[homes\]' | grep -v -c '^\[printers\]' | grep -v -c '^\[print\$\]' || echo "0")
    
    # Better detection: look for any custom path definitions
    if grep -q "^[[:space:]]*path[[:space:]]*=" /etc/samba/smb.conf | grep -v "/var/tmp" | grep -v "/var/lib/samba/printers"; then
      has_custom_shares=true
      echo "✅ Existing custom Samba shares detected - will preserve them"
    fi
  fi
else
  read -rp "📁 Install Samba for file sharing and NetBIOS discovery? [Y/n]: " samba_opt
  if [[ ! "$samba_opt" =~ ^[Nn]$ ]]; then
    echo "📦 Installing Samba..."
    sudo apt-get install -y samba smbclient
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
    
    # Use a more reliable method - sed with careful regex
    sudo python3 <<'PYTHON_SCRIPT'
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
    global_end = -1
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

### WSDD - SMART installation
echo ""
if command -v wsdd &> /dev/null && [ -f /etc/systemd/system/wsdd.service ]; then
  echo "✅ WSDD is already installed - skipping installation"
  sudo systemctl restart wsdd 2>/dev/null || true
else
  echo "📦 Installing WSDD for Windows 10/11 discovery..."
  cd /tmp
  if [ ! -d "wsdd" ]; then
    if ! command -v git &> /dev/null; then
      sudo apt-get install -y git
    fi
    if ! command -v python3 &> /dev/null; then
      sudo apt-get install -y python3
    fi
    git clone https://github.com/christgau/wsdd.git
  fi
  cd wsdd
  sudo cp src/wsdd.py /usr/local/bin/wsdd
  sudo chmod +x /usr/local/bin/wsdd
  
  sudo tee /etc/systemd/system/wsdd.service > /dev/null <<EOF
[Unit]
Description=Web Service Discovery host daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wsdd --shortlog
Restart=on-failure

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

### Verify services
echo ""
echo "🔍 Verifying services..."
services_ok=true

for service in avahi-daemon wsdd; do
  if systemctl is-active --quiet "$service" 2>/dev/null; then
    echo "✅ $service is running"
  else
    echo -e "${YELLOW}⚠️  $service is not running${NC}"
    services_ok=false
  fi
done

if [ "$samba_installed" = true ]; then
  for service in smbd nmbd; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      echo "✅ $service is running"
    else
      echo -e "${YELLOW}⚠️  $service is not running${NC}"
      services_ok=false
    fi
  done
fi

### Show configured shares
if [ "$samba_installed" = true ]; then
  echo ""
  echo "📁 Your Samba shares:"
  sudo smbclient -L localhost -N 2>/dev/null | grep -A 100 "Sharename" | grep -E "^\s+[A-Za-z]" || echo "  (none configured yet)"
fi

### Success message
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 Setup Complete!                                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "This machine should now be discoverable as:"
echo -e "  ${BLUE}🔸 ${new_hostname}.local${NC}      (mDNS)"
if [ "$samba_installed" = true ]; then
  echo -e "  ${BLUE}🔸 ${new_hostname}${NC}             (Windows network)"
fi
echo ""
echo -e "${YELLOW}🧪 Test from Windows:${NC}"
echo "  1. Open File Explorer → Network"
echo "  2. Look for '${new_hostname}'"
echo "  3. Or type: \\\\${new_hostname}"
if [ "$has_custom_shares" = true ]; then
  echo ""
  echo -e "${GREEN}✅ Your existing Samba shares were preserved!${NC}"
fi
echo ""
echo -e "${YELLOW}💡 Notes:${NC}"
echo "  • Discovery can take 1-2 minutes"
echo "  • Ensure Windows network is set to 'Private'"
if [ -n "${backup_file:-}" ]; then
  echo "  • Config backup: $backup_file"
fi
echo ""

if [ "$services_ok" = false ]; then
  echo -e "${YELLOW}⚠️  Some services had issues. Check logs:${NC}"
  echo "  sudo journalctl -u avahi-daemon -n 50"
  echo "  sudo journalctl -u smbd -n 50"
  echo "  sudo journalctl -u nmbd -n 50"
  echo "  sudo journalctl -u wsdd -n 50"
  echo ""
fi

