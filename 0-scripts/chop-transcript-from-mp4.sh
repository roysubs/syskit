#!/usr/bin/env bash
# mp4-transcribe.sh
# Usage: ./mp4-transcribe.sh video.mp4
# Requirements: none pre-installed; installs on demand (ffmpeg, pip, whisper)

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 video.mp4"
    exit 1
fi

VIDEO="$1"
BASENAME="${VIDEO%.*}"
SUBFILE="${BASENAME}.srt"

if [ ! -f "$VIDEO" ]; then
    echo "Error: File '$VIDEO' not found."
    exit 1
fi

pkg_install() {
    local pkgs=("$@")
    if command -v zypper &>/dev/null; then
        sudo zypper --non-interactive install --auto-agree-with-licenses -y "${pkgs[@]}"
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${pkgs[@]}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "${pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm "${pkgs[@]}"
    elif command -v apk &>/dev/null; then
        sudo apk add "${pkgs[@]}"
    elif command -v brew &>/dev/null; then
        brew install "${pkgs[@]}"
    else
        echo "Error: Supported package manager not found." >&2
        return 1
    fi
}

# --- Ensure ffmpeg is installed ---
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
    echo "📦 Installing ffmpeg..."
    pkg_install ffmpeg
fi

# --- Ensure python3 and pip are installed ---
if ! command -v python3 >/dev/null 2>&1; then
    echo "📦 Installing python3..."
    pkg_install python3
fi

# --- Ensure pipx is installed ---
if ! command -v pipx >/dev/null 2>&1; then
    echo "📦 Installing pipx..."
    pkg_install pipx
    python3 -m pipx ensurepath 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
fi

# --- Ensure Whisper is installed via pipx ---
if ! command -v whisper >/dev/null 2>&1; then
    echo "📦 Installing Whisper via pipx..."
    pipx install openai-whisper
fi

# --- Check for subtitles ---
echo "🔍 Checking for embedded subtitles..."
SUB_STREAM=$(ffprobe -v error \
    -select_streams s \
    -show_entries stream=index \
    -of csv=p=0 "$VIDEO" | head -n 1)

if [ -n "$SUB_STREAM" ]; then
    echo "✅ Found subtitle track (index $SUB_STREAM). Extracting..."
    ffmpeg -y -i "$VIDEO" -map 0:s:"$SUB_STREAM" "$SUBFILE"
    echo "📄 Saved subtitles to: $SUBFILE"
else
    echo "⚠ No embedded subtitles found. Generating transcript with Whisper..."
    whisper "$VIDEO" --model medium --language en --output_format srt
    echo "📄 Whisper transcript saved alongside video."
fi

