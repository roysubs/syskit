#!/bin/bash
# Author: Roy Wiseman 2025-05

# Function to install Frotz
install_frotz() {
  if ! command -v "frotz" &> /dev/null; then
    echo "Installing Frotz (Z-machine interpreter)..."
    # Only update if it's been more than 2 days since the last update (to avoid constant updates)
    if [ -e /var/cache/apt/pkgcache.bin ]; then
        if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then
            sudo apt update && sudo apt upgrade -y
        fi
    else
        echo "Cache file not found, running update anyway..."
        sudo apt update && sudo apt upgrade -y
    fi
    sudo apt install -y frotz
  fi
}

# Function to run Zork
run_zork() {
  local script_dir
  script_dir=$(dirname "$(realpath "$0")")
  local zork_file="$script_dir/zork1.z5"

  if [[ -f "$zork_file" ]]; then
    echo "Found zork1.z5 in $script_dir. Running the game..."
    frotz "$zork_file"
  else
    echo "Error: zork1.z5 not found in $script_dir."
    echo "Please ensure zork1.z5 is in the same directory as this script."
    exit 1
  fi
}

# Main script execution
install_frotz
run_zork

cat <<EOF



Getting Z-Machine games, Infocom titles and community-created interactive fiction:

1. Infocom Games
- Legally Owned Copies: Many Infocom games are included in collections like The Lost Treasures of Infocom, which you can find on platforms like GOG or as part of older physical releases.
- Classic Gaming Archives: Some websites archive these games if their copyright status has changed. Be cautious and ensure downloads are from reputable and legal sources.

2. Community and Public Domain Z-Machine Games
- Interactive Fiction Archive: The IF Archive is a central repository for interactive fiction, hosting thousands of games, many of which are Z-Machine compatible.
- Direct Downloads: Explore /games/zcode/ on the site to find Z-Machine games in .z5, .z8, and other formats.
- Inform Developers: Many Inform developers release their Z-Machine-compatible games for free. Browse IFDB (Interactive Fiction Database) to find highly-rated games and download links.

3. Z-Machine Tools and Resources
- Lost Treasures Companion: If you're interested in learning more about the games, the Lost Treasures series includes maps and documentation for Infocom classics.
- Tools for Game Creation: You can even try creating your own Z-Machine games using Inform 7 or similar tools.

4. Abandonware Sites
- Websites like Abandonia or similar may host Infocom games for download. Their legality depends on your region, so proceed with caution.



EOF






#  declare -A zork_urls=(
#    ["zork1"]="http://infocom-if.org/downloads/zork1.zip"
#    ["zork2"]="http://infocom-if.org/downloads/zork2.zip"
#    ["zork3"]="http://infocom-if.org/downloads/zork3.zip"
#  )
#
#  for zork in "${!zork_urls[@]}"; do
#    local url="${zork_urls[$zork]}"
#    local zip_file="$base_dir/${zork}.zip"
#    local extract_dir="$base_dir/${zork}"
#
#    echo "Downloading $zork..."
#    wget --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36" -O "$zip_file" "$url"
#    if [ $? -ne 0 ] || [ ! -s "$zip_file" ]; then
#      echo "Failed to download $zork from $url. Skipping."
#      rm -f "$zip_file"
#      continue
#    fi
