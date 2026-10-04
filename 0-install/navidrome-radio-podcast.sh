#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-01
# Cross-platform: adds radio stations + podcast episodes to a running Navidrome library.

IS_MACOS=false
if [[ "$(uname)" == "Darwin" ]]; then
    IS_MACOS=true
fi

# Root is only needed on Linux (system-owned /srv path + dedicated 'navidrome' user).
# On macOS, MUSIC_DIR lives under the invoking user's own home directory - no elevation needed.
if [[ "$IS_MACOS" == "false" ]] && [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31mElevation required; rerunning as sudo...\033[0m\n"
    exec sudo "$0" "$@"
fi

# Set Navidrome music directory (override with MUSIC_DIR env var if yours differs)
if [[ "$IS_MACOS" == "true" ]]; then
    MUSIC_DIR="${MUSIC_DIR:-$HOME/Music/Navidrome}"
else
    MUSIC_DIR="${MUSIC_DIR:-/srv/music}"
fi
PLAYLISTS_DIR="$MUSIC_DIR/Playlists"
PODCASTS_DIR="$MUSIC_DIR/Podcasts"
echo "Using music directory: $MUSIC_DIR"

# Create necessary directories
mkdir -p "$PLAYLISTS_DIR"
mkdir -p "$PODCASTS_DIR"

# Define radio stations
echo "Adding radio stations..."
cat <<EOF > "$PLAYLISTS_DIR/radio.m3u"
#EXTM3U
#EXTINF:-1,BBC Radio 1
http://stream.live.vc.bbcmedia.co.uk/bbc_radio_one
#EXTINF:-1,BBC Radio 2
http://stream.live.vc.bbcmedia.co.uk/bbc_radio_two
#EXTINF:-1,BBC Radio 3
http://stream.live.vc.bbcmedia.co.uk/bbc_radio_three
#EXTINF:-1,BBC Radio 4
http://stream.live.vc.bbcmedia.co.uk/bbc_radio_fourfm
#EXTINF:-1,BBC 6 Music
http://stream.live.vc.bbcmedia.co.uk/bbc_6music
#EXTINF:-1,Classic FM
http://media-ice.musicradio.com/ClassicFMMP3
#EXTINF:-1,Jazz FM
http://media-ice.musicradio.com/JazzFMMP3
EOF

# Fetch latest podcast episodes
if ! command -v wget &>/dev/null; then
    echo "wget not found." >&2
    if [[ "$IS_MACOS" == "true" ]]; then
        echo "Install it with: brew install wget" >&2
    fi
    exit 1
fi

echo "Downloading latest podcasts..."
cd "$PODCASTS_DIR"

# Ben Shapiro Show
# (grep -oP is a GNU-only extension - macOS's BSD grep has no -P at all, so this used
#  a portable grep -o + sed extraction instead, which works identically everywhere)
curl -s "https://feeds.megaphone.fm/ben-shapiro" | grep -o 'enclosure url="[^"]*"' | head -n 1 | sed -E 's/^enclosure url="//; s/"$//' | xargs -I{} wget -q -O "ben-shapiro.mp3" {}

# Joe Rogan (Spotify-exclusive, need workaround)
SPOTIFY_LINK="https://www.spotify.com/uk/podcasts/show/4rOoJ6Egrf8K2IrywzwOMk"
echo "Joe Rogan podcast is Spotify-exclusive, please listen at: $SPOTIFY_LINK"

# Set permissions (Linux only - macOS runs Navidrome as the invoking user, no dedicated system user)
if [[ "$IS_MACOS" == "false" ]]; then
    chown -R navidrome:navidrome "$MUSIC_DIR"
fi

# Restart Navidrome service
echo "Restarting Navidrome..."
if [[ "$IS_MACOS" == "true" ]]; then
    if command -v brew &>/dev/null && brew services list 2>/dev/null | grep -q "^navidrome"; then
        brew services restart navidrome
    else
        echo "Could not find Navidrome managed by 'brew services'. If you run it another way (e.g. a custom launchd agent), restart it manually." >&2
    fi
else
    systemctl restart navidrome
fi

echo "Done! Radio stations and podcasts added."

