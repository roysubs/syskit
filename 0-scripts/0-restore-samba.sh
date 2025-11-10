#!/usr/bin/env bash
# Quick restore of Samba configuration

echo "🔄 Restoring your Samba configuration..."

# Copy your backup back
sudo cp /etc/samba/smb.conf.bak.20251108-162500 /etc/samba/smb.conf

# Add the critical network discovery settings to your existing config
# We'll append them to the [global] section without destroying your Downloads share

sudo tee -a /etc/samba/smb.conf > /dev/null <<'EOF'

# Network Discovery Settings (added by network discovery script)
   netbios name = hp2
   local master = yes
   preferred master = yes
   os level = 35
   wins support = no
   dns proxy = yes
   name resolve order = bcast host lmhosts wins
EOF

echo "✅ Configuration restored with your Downloads share intact"
echo "🔄 Restarting Samba services..."

sudo systemctl restart smbd nmbd

echo "✅ Done! Your Downloads share should be back and hp2 should still be discoverable"
echo ""
echo "Test it:"
echo "  From Linux: smbclient -L //hp2/ -U boss"
echo "  From Windows: \\\\hp2\\Downloads"
