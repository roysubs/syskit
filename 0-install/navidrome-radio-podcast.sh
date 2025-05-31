#!/bin/bash
# Author: Roy Wiseman 2025-01

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31mElevation required; rerunning as sudo...\033[0m\n"
    exec sudo "$0" "$@"
fi

# Set Navidrome music directory (update if different)
MUSIC_DIR="/srv/music"
PLAYLISTS_DIR="$MUSIC_DIR/Playlists"
PODCASTS_DIR="$MUSIC_DIR/Podcasts"

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
echo "Downloading latest podcasts..."
cd "$PODCASTS_DIR"

# Ben Shapiro Show
curl -s "https://feeds.megaphone.fm/ben-shapiro" | grep -oP '(?<=<enclosure url=")[^"]*' | head -n 1 | xargs wget -q -O "ben-shapiro.mp3"

# Joe Rogan (Spotify-exclusive, need workaround)
SPOTIFY_LINK="https://www.spotify.com/uk/podcasts/show/4rOoJ6Egrf8K2IrywzwOMk"
echo "Joe Rogan podcast is Spotify-exclusive, please listen at: $SPOTIFY_LINK"

# Set permissions
chown -R navidrome:navidrome "$MUSIC_DIR"

# Restart Navidrome service
echo "Restarting Navidrome..."
systemctl restart navidrome

echo "Done! Radio stations and podcasts added."

