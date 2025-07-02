#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-07-01 (v7)
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
  --out DIR         Set the output directory (default: current directory).
  --quality PROFILE   Set the quality profile.
  -h, --help          Show this help message.

TIME FORMAT:
  Supports seconds (125), mm:ss (2:05.5), or hh:mm:ss (00:02:05.5).

EXAMPLE:
  ${0##*/} "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 1:09 2:15
EOF
}

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

COLOR_RESET='\033[0m'; COLOR_RED='\033[0;31m'; COLOR_BLUE='\033[0;34m'; COLOR_GREEN='\033[0;32m'; COLOR_YELLOW='\033[0;33m'
msg_error() { echo -e "${COLOR_RED}[-]${COLOR_RESET} $1" >&2; }
msg() { echo -e "${COLOR_BLUE}[*]${COLOR_RESET} $1"; }
msg_ok() { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $1"; }
msg_warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"; }

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

get_video_id() {
    local input_url="$1"
    if [[ "$input_url" =~ (youtu\.be/|v=|/embed/|/v/|/e/|shorts/|live/|googleusercontent.com/youtube.com/)([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[2]}"
    elif [[ "$input_url" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
        echo "$input_url"
    else
        # Fallback for URLs that might not have a clear indicator but contain the ID
        grep -o '[a-zA-Z0-9_-]\{11\}' <<< "$input_url" | head -n 1
    fi
}

# ---------------[ TIME CONVERSION & FORMATTING ]---------------
convert_to_seconds() {
    local t=$1
    if [[ -z "$t" ]]; then echo ""; return; fi
    if [[ $(grep -o ':' <<< "$t" | wc -l) -eq 1 ]]; then t="00:$t"; fi
    if [[ "$t" =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.[0-9]+)?$ ]]; then
        echo "$((10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[3]}))${BASH_REMATCH[4]:-}"
    elif [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then echo "$t";
    else echo "Error: Invalid time format '$1'." >&2; exit 1; fi
}

to_hms_label() {
    if [[ -z "$1" ]]; then echo ""; return; fi; local s_total=${1%%.*}
    printf "%02d-%02d-%02d" $((s_total/3600)) $(((s_total%3600)/60)) $((s_total%60))
}

# NEW: Format seconds into a human-readable string: hh hr mm min ss sec
format_duration_verbose() {
    local total_seconds=$1
    if (( total_seconds < 0 )); then total_seconds=0; fi
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))
    printf "%d hr %d min %d sec" "$hours" "$minutes" "$seconds"
}

start_sec=$(convert_to_seconds "$start_input"); end_sec=$(convert_to_seconds "$end_input")
if [[ -n "$start_sec" && -n "$end_sec" && $(echo "$end_sec <= $start_sec" | bc -l) -eq 1 ]]; then
    msg_error "End time must be greater than start time."; exit 1;
fi

# ----------[ INSTALL YT-DLP & FFMPEG ]----------
GITHUB_REPO="yt-dlp/yt-dlp"; INSTALL_DIR="$HOME/.local/bin"; EXE_NAME="yt-dlp"; TARGET_EXE_PATH="$INSTALL_DIR/$EXE_NAME"
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_dependencies() {
    # Check for yt-dlp
    if ! command_exists "$EXE_NAME"; then
        msg "yt-dlp not found."
        msg "Fetching latest yt-dlp version from GitHub..."
        local LATEST_GITHUB_VERSION; LATEST_GITHUB_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | awk -F'"' '/"tag_name"/ {print $4}')
        if [ -z "$LATEST_GITHUB_VERSION" ]; then msg_error "Failed to fetch latest yt-dlp version from GitHub."; exit 1; fi
        msg_ok "Latest GitHub version: $LATEST_GITHUB_VERSION"
        local asset="yt-dlp_linux"
        msg "Preparing to install yt-dlp v$LATEST_GITHUB_VERSION to $TARGET_EXE_PATH..."
        mkdir -p "$INSTALL_DIR"
        local url="https://github.com/$GITHUB_REPO/releases/download/$LATEST_GITHUB_VERSION/$asset"
        msg "Downloading from: $url"
        if curl -SL --progress-bar -o "$TARGET_EXE_PATH" "$url" && chmod +x "$TARGET_EXE_PATH"; then
            msg_ok "yt-dlp v$LATEST_GITHUB_VERSION installed successfully."
        else
            msg_error "yt-dlp download or installation failed."; exit 1;
        fi
    fi
    YTDLP_CMD=$(command -v "$EXE_NAME")

    # Check for ffmpeg and other tools
    for cmd in ffmpeg ffprobe bc; do
        if ! command_exists "$cmd"; then
            msg_warn "Dependency '$cmd' is not found."
            if [[ "$cmd" == "ffmpeg" || "$cmd" == "ffprobe" ]] && command_exists apt-get && command_exists sudo; then
                read -r -p "Attempt to install ffmpeg using 'sudo apt-get install ffmpeg'? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if sudo apt-get install -y ffmpeg; then msg_ok "ffmpeg installed."; else msg_error "Failed to install ffmpeg."; exit 1; fi
                else msg_error "ffmpeg is required. Exiting."; exit 1; fi
            else
                msg_error "Missing essential dependency: '$cmd'. Please install it manually."; exit 1;
            fi
        fi
    done
    msg_ok "All dependencies are satisfied."
}

# =========================================================================
install_dependencies

# ---------------[ QUALITY PROFILES ]---------------
case "$quality_profile" in
  phone_small) YTDLP_FORMAT_SELECTOR="bestvideo[height<=360]+bestaudio/best[height<=360]"; FFMPEG_CONTENT_MAX_H=360; FFMPEG_CRF=32; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="64k";;
  phone_fast) YTDLP_FORMAT_SELECTOR="bestvideo[height<=480]+bestaudio/best[height<=480]"; FFMPEG_CONTENT_MAX_H=480; FFMPEG_CRF=25; FFMPEG_PRESET="veryfast"; FFMPEG_AUDIO_KBPS="96k";;
  sd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=720]+bestaudio/best[height<=720]"; FFMPEG_CONTENT_MAX_H=720; FFMPEG_CRF=19; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="128k";;
  hd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=1080]+bestaudio/best[height<=1080]"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=13; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="160k";;
  source_mp4) YTDLP_FORMAT_SELECTOR="bestvideo[height<=2160][ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec=aac]/best"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=22; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="192k";;
  *) msg_error "Unknown quality profile: $quality_profile"; show_help; exit 1;;
esac

# --- File Handling ---
video_id=$(get_video_id "$url")
if [[ -z "$video_id" ]]; then
    msg_error "Could not extract a valid YouTube Video ID from: $url"
    exit 1
fi
msg "Detected Video ID: $video_id"

base_filename_stem="${outdir}/${video_id}_${quality_profile}"
downloaded_source_file="${base_filename_stem}_source.mp4"

if [[ ! -f "$downloaded_source_file" ]]; then
  msg "Source file not found. Downloading video to: $downloaded_source_file"
  if "$YTDLP_CMD" -f "$YTDLP_FORMAT_SELECTOR" --merge-output-format mp4 -o "$downloaded_source_file" "$url"; then
    msg_ok "Download complete."
  else
    msg_error "yt-dlp failed to download the video."
    if [ -f "$downloaded_source_file" ]; then rm "$downloaded_source_file"; fi
    exit 1
  fi
else
  msg_ok "Source file already exists. Skipping download."
fi

if [[ ! -s "$downloaded_source_file" ]]; then
    msg_error "Source file is missing or empty. Cannot proceed."
    exit 1
fi

# ---------------[ VIDEO PROCESSING (FFMPEG) ]---------------
# NEW: Start timing here, after setup and download
processing_start_time=$(date +%s)

msg "Starting video processing..."
video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$downloaded_source_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$downloaded_source_file")
if [[ -z "$video_width" || -z "$video_height" ]]; then msg_error "Could not get video dimensions."; exit 1; fi
msg "Source dimensions: ${video_width}x${video_height}"

target_pad_width=$(( video_width >= video_height ? 1280 : 720 ))
target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))
ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"
ffmpeg_cmd_base=(ffmpeg -hide_banner -stats -y)
duration_to_process=0

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
  start_label=$(to_hms_label "$start_sec"); end_label=$(to_hms_label "$end_sec")
  output_final_mp4="${base_filename_stem}_${start_label}_to_${end_label}.mp4"
  duration_to_process=$(echo "$end_sec - $start_sec" | bc)
  msg "Trimming and resizing video to: $output_final_mp4"
  "${ffmpeg_cmd_base[@]}" -ss "$start_sec" -i "$downloaded_source_file" -to "$duration_to_process" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
else
  output_final_mp4="${base_filename_stem}_full.mp4"
  duration_to_process=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$downloaded_source_file")
  msg "Re-encoding and resizing full video to: $output_final_mp4"
  "${ffmpeg_cmd_base[@]}" -i "$downloaded_source_file" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
fi

# --- Post-processing checks and timing metrics ---
if [[ $? -ne 0 || ! -s "$output_final_mp4" ]]; then
    msg_error "ffmpeg processing failed or output file is empty."
    exit 1
fi

# NEW: Calculate and display timing metrics
processing_end_time=$(date +%s)
elapsed_seconds=$(( processing_end_time - processing_start_time ))
# Ensure elapsed_seconds is not zero to avoid division by zero error
if (( elapsed_seconds == 0 )); then elapsed_seconds=1; fi

processing_time_str=$(format_duration_verbose "$elapsed_seconds")
processing_speed=$(printf "%.2f" "$(echo "scale=2; $duration_to_process / $elapsed_seconds" | bc -l)")

msg_ok "Successfully processed video saved as: $output_final_mp4"
msg_ok "Video processing took ${processing_time_str}"
msg_ok "${processing_speed} seconds of video were processed per second"
msg_ok "Script finished at $(date +'%T')."
