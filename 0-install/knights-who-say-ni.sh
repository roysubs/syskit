#!/bin/bash
# Author: Roy Wiseman 2025-01


# Only run 'apt update' if last update was 2 days or more
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update; fi
HOME_DIR="$HOME"

# Install tools if not already installed
PACKAGES=("lynx" "pv")
install-if-missing() {
    local package="$1"
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
        echo "Installing $package..."; sudo apt-get install -y "$package"
    fi
}
for package in "${PACKAGES[@]}"; do install-if-missing "$package"; done

# Lynx configuration
URL="https://genius.com/Monty-python-the-knights-who-say-ni-annotated"
OUTPUT_FILE="/tmp/ni.txt"
LYNX_CFG="/etc/lynx/lynx.cfg"
COOKIE_SETTINGS_BACKUP="$(mktemp).lynx.cfg"
cp "$LYNX_CFG" "$COOKIE_SETTINGS_BACKUP"

# Update or add lynx settings
sudo sed -i "s|^#?SET_COOKIES:.*|SET_COOKIES:TRUE|" "$LYNX_CFG"
sudo sed -i "s|^#?ACCEPT_ALL_COOKIES:.*|ACCEPT_ALL_COOKIES:TRUE|" "$LYNX_CFG"
sudo sed -i "s|^#?COOKIE_FILE:.*|COOKIE_FILE:$HOME/.lynx_cookies|" "$LYNX_CFG"
sudo sed -i "s|^#?COOKIE_SAVE_FILE:.*|COOKIE_SAVE_FILE:$HOME/.lynx_cookies|" "$LYNX_CFG"

# Add missing settings
grep -q "^SET_COOKIES" "$LYNX_CFG" || echo "SET_COOKIES:TRUE" | sudo tee -a "$LYNX_CFG"
grep -q "^ACCEPT_ALL_COOKIES" "$LYNX_CFG" || echo "ACCEPT_ALL_COOKIES:TRUE" | sudo tee -a "$LYNX_CFG"
grep -q "^COOKIE_FILE" "$LYNX_CFG" || echo "COOKIE_FILE:$HOME/.lynx_cookies" | sudo tee -a "$LYNX_CFG"
grep -q "^COOKIE_SAVE_FILE" "$LYNX_CFG" || echo "COOKIE_SAVE_FILE:$HOME/.lynx_cookies" | sudo tee -a "$LYNX_CFG"

# Ensure cookie file exists
touch "$HOME/.lynx_cookies"

# Fetch content using lynx
lynx --dump "$URL" > "$OUTPUT_FILE"

# Extract content
awk '
/HEAD KNIGHT: Ni!/ { start = NR }
/KNIGHTS: Aaaaugh!/ { end = NR }
{ lines[NR] = $0 }
END {
    if (start && end && start <= end) {
        for (i = start; i <= end; i++) {
            print lines[i]
        }
    } else {
        print "Error: Start or end markers not found or invalid." > "/dev/stderr"
        exit 1
    }
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp"
mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Revert lynx settings
if [ -f "$COOKIE_SETTINGS_BACKUP" ]; then
    # Restoring original lynx.cfg...
    sudo mv "$COOKIE_SETTINGS_BACKUP" "$LYNX_CFG"
else
    echo "Error: Backup file $COOKIE_SETTINGS_BACKUP not found."
    exit 1
fi

# Display content with pv
echo
echo
echo
cat "$OUTPUT_FILE" | pv -qL 50

