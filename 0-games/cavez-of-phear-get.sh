#!/bin/bash
# Author: Roy Wiseman 2025-01
set -e

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ -e /var/cache/apt/pkgcache.bin ]; then
    if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then
        sudo apt update && sudo apt upgrade -y
    fi
else
    echo "Cache file not found, running update anyway..."
    sudo apt update && sudo apt upgrade -y
fi

if ! command -v phear &> /dev/null; then
    echo "Installing Cavez of Phear from apt..."
    sudo apt install -y cavezofphear
fi

# Define the actual binary and target symlink names
REAL_BIN="/usr/games/phear"
LINK_DIR="/usr/local/bin"
LINK_NAMES=("cavez" "caves" "cavezofphear" "cavesofphear" "cavez-of-phear" "caves-of-phear")

echo "Creating symlinks for easier access..."

for name in "${LINK_NAMES[@]}"; do
    sudo ln -sf "$REAL_BIN" "$LINK_DIR/$name"
    echo "  -> $LINK_DIR/$name → $REAL_BIN"
done

echo "Done! Try launching with: ${LINK_NAMES[*]}"

echo "
https://github.com/AMDmi3/cavezofphear

How to play
==========
Cursor keys to move (or 2-4-8-6 keypad keys).
b to place and t to detonate bomb.
w to highlight position. s to toggle sound on/off.
==========

To open a specific level:
phear /usr/share/phear/data/levels/02
The only levels available now in that folder are:
01  02  03  04  05  06  07  08  09  10  11

By picking up a diamond * you get 10 points, picking up money $ gives
you 100 points. You get one extra life for every 1000 points you score.

Move around with the arrow keys or the 2-4-8-6 keys. Press k to commit
suicide if you should get stuck.

Got the bombs (%)? Great! Press b to place them, and t to detonate them
all at once. Note that the bombs you place will act just like stones,
affected by gravity, rolling, and so on..

Watch out for monsters (M) -- if they catch you, you will die. To fight
back, drop stones on them or blow them up using your bombs.

Pressing s will enable/disable sound, w will highlight your current position.

"

