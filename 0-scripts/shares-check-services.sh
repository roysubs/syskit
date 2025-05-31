#!/bin/bash
# Author: Roy Wiseman 2025-02

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No color

echo "Check systemctl for SAMBA and NFS services"
echo

# Check if Samba is installed
echo -e "${GREEN}systemctl list-unit-files | grep -q smbd.service${NC}"
if systemctl list-unit-files | grep -q smbd.service; then
    echo -e "${GREEN}Samba is installed.${NC}"
else
    echo -e "${RED}Samba is NOT installed or the smbd service is missing.${NC}"
    echo -e "${RED}To install Samba: sudo apt install samba${NC}"
fi

echo "To restart Samba:      sudo systemctl restart smbd"
echo "To check Samba shares: smbclient -L localhost -U%"
echo "To check Samba status: systemctl status smbd"
echo "smbd: Handles file sharing and authentication."
echo "nmbd: Handles NetBIOS name resolution, allowing Windows machines to find the Samba server by name."
echo "      Restart nmbd if you are having name resolution issues:  sudo systemctl restart nmbd"
echo ""

# Check if NFS is installed
echo -e "${GREEN}systemctl list-unit-files | grep -q nfs-server.service${NC}"
if systemctl list-unit-files | grep -q nfs-server.service; then
    echo -e "${GREEN}NFS is installed.${NC}"
else
    echo -e "${RED}NFS is NOT installed.${NC}"
    echo -e "${RED}To install NFS: sudo apt install nfs-kernel-server${NC}"
fi

echo "To restart NFS:       sudo systemctl restart nfs-server"
echo "To check NFS exports: sudo exportfs -v"
echo "To check NFS status:  systemctl status nfs-server"

