#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-06-14 (v6)
set -e

# ---------------[ CONFIG ]---------------
DEFAULT_OUTDIR="."
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4

# ---------------[ HELPER FUNCTIONS ]---------------
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] <youtube_url_or_id> [start_time] [end_time]
Downloads a YouTube video and encodes it to MP4, with optional trimming and resizing.
Filenames are generated from the Video ID for reliability.

OPTIONS:
  --out DIR               Set the output directory (default: current directory).
  --quality PROFILE       Set the quality profile.
  -h, --help              Show this help message.

TIME FORMAT:
  Supports seconds (125), mm:ss (2:05.5), or hh:mm:ss (00:02:05.5).

EXAMPLE:
  $(basename "$0") "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 1:09 2:15
EOF
}

print_yellow() { printf "\033[1;33m%s\033[0m\n" "$1"; }

# ---------------[ ARGS ]-----------------
outdir="$DEFAULT_OUTDIR"; quality_profile="$DEFAULT_QUALITY_PROFILE"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out) shift; outdir="$1";;
    --quality) shift; quality_profile="$1";;
    -h|--help) show_help; exit 0;;
    -*) echo "Error: Unknown option: $1" >&2; show_help; exit 1;;
    *) break;;
  esac
  shift
done
url="$1"; start_input="$2"; end_input="$3"

COLOR_RESET='\033[0m'; COLOR_RED='\033[0;31m'; COLOR_BLUE='\033[0;34m'
msg_error() { echo -e "${COLOR_RED}[-]${COLOR_RESET} $1" >&2; }
msg() { echo -e "${COLOR_BLUE}[*]${COLOR_RESET} $1"; }

if [[ -z "$url" ]]; then
    msg_error "YouTube URL or Video ID is required."
    show_help; exit 1;
fi
if [[ "$url" =~ ^[0-9:.]+$ ]]; then
    msg_error "Argument 1 ('$url') looks like a timestamp, not a URL."
    msg "The first argument must be the YouTube URL or Video ID."
    show_help
    exit 1
fi
mkdir -p "$outdir"

# --- FIX: New function to get video ID reliably without network call ---
get_video_id() {
    local input_url="$1"
    # This regex handles youtu.be/, watch?v=, /embed/, and plain IDs
    if [[ "$input_url" =~ (youtu\.be/|v=|/embed/|/v/|/e/|shorts/|live/)([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[2]}"
    else
        # Fallback for plain ID
        if [[ "$input_url" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
            echo "$input_url"
        else
            msg_error "Could not extract YouTube Video ID from URL: $input_url"
            exit 1
        fi
    fi
}


# ---------------[ TIME CONVERSION ]---------------
convert_to_seconds() {
    local t=$1
    if [[ -z "$t" ]]; then echo ""; return; fi
    if [[ $(grep -o ':' <<< "$t" | wc -l) -eq 1 ]]; then t="00:$t"; fi
    if [[ "$t" =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.[0-9]+)?$ ]]; then
        echo "$((10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[3]}))${BASH_REMATCH[4]:-}"
    elif [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then echo "$t";
    else echo "Error: Invalid time format '$1'." >&2; exit 1; fi
}
start_sec=$(convert_to_seconds "$start_input"); end_sec=$(convert_to_seconds "$end_input")
if [[ -n "$start_sec" && -n "$end_sec" && $(echo "$end_sec <= $start_sec" | bc -l) -eq 1 ]]; then
    msg_error "End time must be greater than start time."; exit 1;
fi
to_hms_label() {
    if [[ -z "$1" ]]; then echo ""; return; fi; local s_total=${1%%.*}
    printf "%02d-%02d-%02d" $((s_total/3600)) $(((s_total%3600)/60)) $((s_total%60))
}

# ----------[ INSTALL YT-DLP & FFMPEG ]----------
GITHUB_REPO="yt-dlp/yt-dlp"; INSTALL_DIR="$HOME/.local/bin"; EXE_NAME="yt-dlp"; TARGET_EXE_PATH="$INSTALL_DIR/$EXE_NAME"
COLOR_GREEN='\033[0;32m'; COLOR_YELLOW='\033[0;33m';
msg_ok() { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $1"; }
msg_warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

get_current_ytdlp_info() {
    CURRENT_YTDLP_PATH=""; CURRENT_YTDLP_VERSION=""; IS_APT_MANAGED=false; YTDLP_CMD=""
    local found_in_path=false
    if command_exists "$EXE_NAME"; then
        CURRENT_YTDLP_PATH=$(command -v "$EXE_NAME"); YTDLP_CMD="$CURRENT_YTDLP_PATH"; found_in_path=true
    elif [ -x "$TARGET_EXE_PATH" ]; then
        msg_warn "Found yt-dlp at '$TARGET_EXE_PATH' but the directory is not in your PATH."; CURRENT_YTDLP_PATH="$TARGET_EXE_PATH"; YTDLP_CMD="$TARGET_EXE_PATH"
    fi
    if [ -n "$CURRENT_YTDLP_PATH" ]; then
        CURRENT_YTDLP_VERSION=$("$CURRENT_YTDLP_PATH" --version 2>/dev/null | head -n1) || CURRENT_YTDLP_VERSION="unknown"
        if command_exists dpkg && dpkg -S "$CURRENT_YTDLP_PATH" >/dev/null 2>&1; then IS_APT_MANAGED=true; msg_warn "Found apt-managed yt-dlp at $CURRENT_YTDLP_PATH (v$CURRENT_YTDLP_VERSION).";
        elif [ "$found_in_path" = true ]; then msg_ok "Found user-installed yt-dlp in PATH at $CURRENT_YTDLP_PATH (v$CURRENT_YTDLP_VERSION).";
        else msg_ok "Found user-installed yt-dlp at $CURRENT_YTDLP_PATH (v$CURRENT_YTDLP_VERSION)."; fi
    else msg "yt-dlp not found."; fi
}

get_latest_github_version() {
    msg "Fetching latest yt-dlp version from GitHub..."; local API_RESPONSE; API_RESPONSE=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    if echo "$API_RESPONSE" | grep -q "API rate limit exceeded"; then msg_error "GitHub API rate limit exceeded. Please wait an hour and try again."; exit 1; fi
    LATEST_GITHUB_VERSION=$(echo "$API_RESPONSE" | awk -F'"' '/"tag_name"/ {print $4}')
    if [ -z "$LATEST_GITHUB_VERSION" ]; then msg_error "Failed to fetch latest version from GitHub."; msg_error "Response: $API_RESPONSE"; exit 1; fi
    msg_ok "Latest GitHub version: $LATEST_GITHUB_VERSION"
}

download_and_install_ytdlp() {
    local version_tag="$1"; local asset="yt-dlp_linux"; msg "Preparing to install yt-dlp v$version_tag to $TARGET_EXE_PATH..."
    if ! mkdir -p "$INSTALL_DIR"; then msg_error "Failed to create directory: $INSTALL_DIR"; exit 1; fi
    local url="https://github.com/$GITHUB_REPO/releases/download/$version_tag/$asset"; local temp_file; temp_file=$(mktemp)
    msg "Downloading from: $url"
    if curl -SL --progress-bar -o "$temp_file" "$url"; then
        if chmod +x "$temp_file"; then
            if [ -e "$TARGET_EXE_PATH" ]; then msg_warn "Overwriting existing file at $TARGET_EXE_PATH"; fi
            if mv "$temp_file" "$TARGET_EXE_PATH"; then msg_ok "yt-dlp v$version_tag installed successfully."; YTDLP_CMD="$TARGET_EXE_PATH";
            else msg_error "Failed to move file to $TARGET_EXE_PATH. Check permissions."; rm -f "$temp_file"; exit 1; fi
        else msg_error "Failed to make file executable."; rm -f "$temp_file"; exit 1; fi
    else msg_error "Download failed."; rm -f "$temp_file"; exit 1; fi
}

main_dep_install() {
    get_current_ytdlp_info
    if [ "$IS_APT_MANAGED" = true ]; then msg_error "An apt-managed version of yt-dlp was found. Please remove it first ('sudo apt remove yt-dlp')."; exit 1; fi
    get_latest_github_version
    if [ -z "$CURRENT_YTDLP_PATH" ]; then download_and_install_ytdlp "$LATEST_GITHUB_VERSION";
    elif [ "$CURRENT_YTDLP_VERSION" != "$LATEST_GITHUB_VERSION" ]; then msg "Current version ($CURRENT_YTDLP_VERSION) is outdated. Updating..."; download_and_install_ytdlp "$LATEST_GITHUB_VERSION";
    else msg_ok "yt-dlp is up-to-date (v$CURRENT_YTDLP_VERSION)."; fi
    if ! command -v "$YTDLP_CMD" >/dev/null; then
      msg_error "yt-dlp command is not available after check/install. Exiting."; exit 1;
    fi
    for cmd in ffmpeg ffprobe bc date; do
      if ! command_exists "$cmd"; then
        if [[ "$cmd" == "ffmpeg" || "$cmd" == "ffprobe" ]]; then
          msg_warn "Dependency '$cmd' is not found.";
          if command_exists apt-get && command_exists sudo; then
            read -r -p "Attempt to install it using 'sudo apt-get install ffmpeg'? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
              if sudo apt-get install -y ffmpeg; then msg_ok "$cmd installed."; else msg_error "Failed to install $cmd."; exit 1; fi
            else msg_error "$cmd is required. Exiting."; exit 1; fi
          else msg_error "Cannot auto-install. Please install '$cmd' manually."; exit 1; fi
        else msg_error "Missing essential dependency: '$cmd'. Please install it."; exit 1; fi
      fi
    done
    msg_ok "All dependencies are satisfied."
}

# =========================================================================
main_dep_install

# ---------------[ QUALITY PROFILES ]---------------
case "$quality_profile" in
  phone_small) YTDLP_FORMAT_SELECTOR="bestvideo[height<=360]+bestaudio/best[height<=360]"; FFMPEG_CONTENT_MAX_H=360; FFMPEG_CRF=32; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="64k";;
  phone_fast) YTDLP_FORMAT_SELECTOR="bestvideo[height<=480]+bestaudio/best[height<=480]"; FFMPEG_CONTENT_MAX_H=480; FFMPEG_CRF=25; FFMPEG_PRESET="veryfast"; FFMPEG_AUDIO_KBPS="96k";;
  sd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=720]+bestaudio/best[height<=720]"; FFMPEG_CONTENT_MAX_H=720; FFMPEG_CRF=19; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="128k";;
  hd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=1080]+bestaudio/best[height<=1080]"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=13; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="160k";;
  source_mp4) YTDLP_FORMAT_SELECTOR="bestvideo[height<=2160][ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec=aac]/best"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=22; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="192k";;
  *) msg_error "Unknown quality profile: $quality_profile"; show_help; exit 1;;
esac

# --- FIX: Re-architected file handling to be robust and avoid unnecessary network calls ---

# 1. Get the video ID (local operation)
video_id=$(get_video_id "$url")
msg "Detected Video ID: $video_id"

# 2. Define filenames based on the stable video ID
base_filename_stem="${outdir}/${video_id}_${quality_profile}"
downloaded_source_file="${base_filename_stem}_source.mp4"

# 3. Check for the source file and only download if it's missing
if [[ ! -f "$downloaded_source_file" ]]; then
  msg "Source file not found. Downloading video to: $downloaded_source_file"
  if "$YTDLP_CMD" -f "$YTDLP_FORMAT_SELECTOR" --merge-output-format mp4 -o "$downloaded_source_file" "$url"; then
    msg_ok "Download complete."
  else
    msg_error "yt-dlp failed to download the video."
    # Clean up potentially empty/failed file
    if [ -f "$downloaded_source_file" ]; then rm "$downloaded_source_file"; fi
    exit 1
  fi
else
  msg_ok "Source file already exists. Skipping download."
fi

# Abort if the source file isn't valid for any reason
if [[ ! -s "$downloaded_source_file" ]]; then
    msg_error "Source file is missing or empty. Cannot proceed."
    exit 1
fi

# ---------------[ VIDEO PROCESSING (FFMPEG) ]---------------
msg "Starting video processing..."
video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$downloaded_source_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$downloaded_source_file")
if [[ -z "$video_width" || -z "$video_height" ]]; then msg_error "Could not get video dimensions."; exit 1; fi
msg "Source dimensions: ${video_width}x${video_height}"
target_pad_width=$(( video_width >= video_height ? 1280 : 720 )); target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))
ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"

# Show concise progress stats for ffmpeg
ffmpeg_cmd_base=(ffmpeg -hide_banner -stats -y)

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
  start_label=$(to_hms_label "$start_sec"); end_label=$(to_hms_label "$end_sec"); output_final_mp4="${base_filename_stem}_${start_label}_to_${end_label}.mp4"
  ffmpeg_to_duration=$(echo "$end_sec - $start_sec" | bc); msg "Trimming video to: $output_final_mp4"
  "${ffmpeg_cmd_base[@]}" -ss "$start_sec" -i "$downloaded_source_file" -to "$ffmpeg_to_duration" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
else
  output_final_mp4="${base_filename_stem}_full.mp4"; msg "Re-encoding full video to: $output_final_mp4"
  "${ffmpeg_cmd_base[@]}" -i "$downloaded_source_file" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
fi
if [[ $? -eq 0 && -s "$output_final_mp4" ]]; then msg_ok "Successfully processed video saved as: $output_final_mp4"; else msg_error "ffmpeg processing failed or output file is empty."; exit 1; fi
msg_ok "Script finished."
