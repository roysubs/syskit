#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-06-14 (v6)

# This script has been updated to be a universal video processing tool.
# It can now handle both YouTube URLs and local video files.
# It also includes detailed timing for each step of the process.

set -e

# ---------------[ CONFIG ]---------------
DEFAULT_OUTDIR="."
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4

# ---------------[ HELPER FUNCTIONS ]---------------

# Function to display help information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <source> [start_time] [end_time]
Processes a video file from a local path or YouTube URL.
It performs optional trimming and re-encoding to a specified quality.
Filenames are generated from the YouTube Video ID or the original filename.

OPTIONS:
  --out DIR               Set the output directory (default: current directory).
  --quality PROFILE       Set the quality profile.
  -h, --help              Show this help message.

TIME FORMAT:
  Supports seconds (125), mm:ss (2:05.5), or hh:mm:ss (00:02:05.5).

EXAMPLES:
  # Process a local file with trimming
  $(basename "$0") video.mp4 1:09 2:15

  # Download and process a YouTube video
  $(basename "$0") "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 1:09 2:15
EOF
}

# Functions for colorful output
COLOR_RESET='\033[0m'; COLOR_RED='\033[0;31m'; COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'; COLOR_YELLOW='\033[0;33m';
msg_error() { echo -e "${COLOR_RED}[-]${COLOR_RESET} $1" >&2; }
msg() { echo -e "${COLOR_BLUE}[*]${COLOR_RESET} $1"; }
msg_ok() { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $1"; }
msg_warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"; }

# Function to check if a command exists on the system
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Function to get the YouTube video ID from various URL formats
get_video_id() {
    local input_url="$1"
    if [[ "$input_url" =~ (youtu\.be/|v=|/embed/|/v/|/e/|shorts/|live/)([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[2]}"
    else
        if [[ "$input_url" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
            echo "$input_url"
        else
            msg_error "Could not extract YouTube Video ID from URL: $input_url"
            exit 1
        fi
    fi
}

# Function to convert time from various formats to seconds
convert_to_seconds() {
    local t=$1
    if [[ -z "$t" ]]; then echo ""; return; fi
    # Add leading zero if needed for hh:mm:ss parsing
    if [[ $(grep -o ':' <<< "$t" | wc -l) -eq 1 ]]; then t="00:$t"; fi
    if [[ "$t" =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.[0-9]+)?$ ]]; then
        echo "$((10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[3]}))${BASH_REMATCH[4]:-}"
    elif [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$t";
    else
        msg_error "Error: Invalid time format '$1'." >&2; exit 1;
    fi
}

# Function to format seconds back to hh-mm-ss label for filenames
to_hms_label() {
    if [[ -z "$1" ]]; then echo ""; return; fi
    local s_total=${1%%.*}
    printf "%02d-%02d-%02d" $((s_total/3600)) $(((s_total%3600)/60)) $((s_total%60))
}

# Main function to handle dependency checking and installation
main_dep_install() {
    local GITHUB_REPO="yt-dlp/yt-dlp"; local INSTALL_DIR="$HOME/.local/bin"; local EXE_NAME="yt-dlp"; local TARGET_EXE_PATH="$INSTALL_DIR/$EXE_NAME"
    local YTDLP_CMD

    # Check for core dependencies that do not have auto-install logic
    for cmd in bc date; do
        if ! command_exists "$cmd"; then
            msg_error "Missing essential dependency: '$cmd'. Please install it manually."
            exit 1
        fi
    done
    
    # Check for FFmpeg/ffprobe, offer to install via apt-get if available
    for cmd in ffmpeg ffprobe; do
      if ! command_exists "$cmd"; then
        msg_warn "Dependency '$cmd' is not found.";
        if command_exists apt-get && command_exists sudo; then
          read -r -p "Attempt to install it using 'sudo apt-get install ffmpeg'? (y/N): " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if sudo apt-get install -y ffmpeg; then msg_ok "$cmd installed."; else msg_error "Failed to install $cmd."; exit 1; fi
          else
            msg_error "$cmd is required. Exiting."; exit 1;
          fi
        else
          msg_error "Cannot auto-install. Please install '$cmd' manually."; exit 1;
        fi
      fi
    done

    # Check for yt-dlp and update if necessary. This logic is separate because yt-dlp updates very frequently.
    local CURRENT_YTDLP_PATH=""; local CURRENT_YTDLP_VERSION=""; local LATEST_GITHUB_VERSION=""
    
    msg "Fetching latest yt-dlp version from GitHub...";
    local API_RESPONSE; API_RESPONSE=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    if echo "$API_RESPONSE" | grep -q "API rate limit exceeded"; then msg_error "GitHub API rate limit exceeded. Please wait an hour and try again."; exit 1; fi
    LATEST_GITHUB_VERSION=$(echo "$API_RESPONSE" | awk -F'"' '/"tag_name"/ {print $4}')
    if [ -z "$LATEST_GITHUB_VERSION" ]; then msg_error "Failed to fetch latest version from GitHub."; exit 1; fi
    msg_ok "Latest GitHub version: $LATEST_GITHUB_VERSION"

    # Determine current yt-dlp status
    if command_exists "$EXE_NAME"; then
      CURRENT_YTDLP_PATH=$(command -v "$EXE_NAME")
      CURRENT_YTDLP_VERSION=$("$CURRENT_YTDLP_PATH" --version 2>/dev/null | head -n1) || CURRENT_YTDLP_VERSION="unknown"
      msg_ok "Found user-installed yt-dlp in PATH at $CURRENT_YTDLP_PATH (v$CURRENT_YTDLP_VERSION)."
    elif [ -x "$TARGET_EXE_PATH" ]; then
      CURRENT_YTDLP_PATH="$TARGET_EXE_PATH"
      CURRENT_YTDLP_VERSION=$("$CURRENT_YTDLP_PATH" --version 2>/dev/null | head -n1) || CURRENT_YTDLP_VERSION="unknown"
      msg_ok "Found user-installed yt-dlp at $CURRENT_YTDLP_PATH (v$CURRENT_YTDLP_VERSION)."
    else
      msg "yt-dlp not found."
    fi

    # Install or update yt-dlp if needed
    if [ -z "$CURRENT_YTDLP_PATH" ] || [ "$CURRENT_YTDLP_VERSION" != "$LATEST_GITHUB_VERSION" ]; then
      msg "yt-dlp is not installed or is outdated. Installing/Updating to v$LATEST_GITHUB_VERSION..."
      if ! mkdir -p "$INSTALL_DIR"; then msg_error "Failed to create directory: $INSTALL_DIR"; exit 1; fi
      local url="https://github.com/$GITHUB_REPO/releases/download/$LATEST_GITHUB_VERSION/yt-dlp_linux"; local temp_file; temp_file=$(mktemp)
      msg "Downloading from: $url"
      if curl -SL --progress-bar -o "$temp_file" "$url"; then
        if chmod +x "$temp_file"; then
          if [ -e "$TARGET_EXE_PATH" ]; then msg_warn "Overwriting existing file at $TARGET_EXE_PATH"; fi
          if mv "$temp_file" "$TARGET_EXE_PATH"; then msg_ok "yt-dlp installed successfully.";
          else msg_error "Failed to move file. Check permissions."; rm -f "$temp_file"; exit 1; fi
        else msg_error "Failed to make file executable."; rm -f "$temp_file"; exit 1; fi
      else msg_error "Download failed."; rm -f "$temp_file"; exit 1; fi
    else
      msg_ok "yt-dlp is up-to-date (v$CURRENT_YTDLP_VERSION)."
    fi

    # Set the command path for yt-dlp
    YTDLP_CMD=$(command -v "$EXE_NAME" || echo "$TARGET_EXE_PATH")
    if ! [ -x "$YTDLP_CMD" ]; then
      msg_error "yt-dlp command is not available after check/install. Exiting."; exit 1;
    fi
    msg_ok "All dependencies are satisfied."
}

# ---------------[ MAIN EXECUTION ]-----------------

# Start a global timer for the entire script's execution
start_total_timer=$(date +%s.%N)

# Parse command line arguments
outdir="$DEFAULT_OUTDIR"; quality_profile="$DEFAULT_QUALITY_PROFILE"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --out) shift; outdir="$1";;
        --quality) shift; quality_profile="$1";;
        -h|--help) show_help; exit 0;;
        -*) msg_error "Error: Unknown option: $1" >&2; show_help; exit 1;;
        *) break;;
    esac
    shift
done

source_input="$1"; start_input="$2"; end_input="$3"

if [[ -z "$source_input" ]]; then
    msg_error "A source (local file or YouTube URL) is required."
    show_help; exit 1;
fi
mkdir -p "$outdir"

# Perform dependency checks before any processing begins
main_dep_install

# Time conversion for trimming
start_sec=$(convert_to_seconds "$start_input"); end_sec=$(convert_to_seconds "$end_input")
if [[ -n "$start_sec" && -n "$end_sec" && $(echo "$end_sec <= $start_sec" | bc -l) -eq 1 ]]; then
    msg_error "End time must be greater than start time."; exit 1;
fi

# Determine the final output filename stem
output_filename_stem=""

# This is the core logic for handling both local files and YouTube URLs.
# We first check if the provided source is a local file.
if [[ -f "$source_input" ]]; then
    # Case 1: The source is a local file.
    msg_ok "Source is a local file: $source_input"
    input_file="$source_input"
    output_filename_stem="${outdir}/$(basename "${source_input%.*}")"
elif [[ "$source_input" =~ ^https?:// ]]; then
    # Case 2: The source is a URL. Assume it's a YouTube URL for now.
    msg "Source is a URL. Detecting YouTube video ID..."
    video_id=$(get_video_id "$source_input")
    msg_ok "Detected Video ID: $video_id"
    output_filename_stem="${outdir}/${video_id}_${quality_profile}"
    
    # Define the path for the downloaded source file.
    downloaded_source_file="${output_filename_stem}_source.mp4"

    # Start the download timer.
    start_download_timer=$(date +%s.%N)

    # Check if the video is already downloaded.
    if [[ ! -f "$downloaded_source_file" ]]; then
        msg "Source file not found. Downloading video to: $downloaded_source_file"
        # Download the video using yt-dlp.
        if "$YTDLP_CMD" -f "$YTDLP_FORMAT_SELECTOR" --merge-output-format mp4 -o "$downloaded_source_file" "$source_input"; then
            msg_ok "Download complete."
        else
            msg_error "yt-dlp failed to download the video."
            if [ -f "$downloaded_source_file" ]; then rm "$downloaded_source_file"; fi
            exit 1
        fi
    else
        msg_ok "Source file already exists. Skipping download."
    fi

    # End the download timer.
    end_download_timer=$(date +%s.%N)
    input_file="$downloaded_source_file"

    if [[ ! -s "$input_file" ]]; then
        msg_error "Source file is missing or empty. Cannot proceed."
        exit 1
    fi

else
    msg_error "Invalid source. Please provide a valid local file path or YouTube URL."
    show_help
    exit 1
fi

# ---------------[ VIDEO PROCESSING (FFMPEG) ]---------------

msg "Starting video processing..."
start_processing_timer=$(date +%s.%N)

# Get video dimensions from the input file
video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$input_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$input_file")
if [[ -z "$video_width" || -z "$video_height" ]]; then msg_error "Could not get video dimensions."; exit 1; fi
msg "Source dimensions: ${video_width}x${video_height}"

# Get quality profile parameters
case "$quality_profile" in
    phone_small) YTDLP_FORMAT_SELECTOR="bestvideo[height<=360]+bestaudio/best[height<=360]"; FFMPEG_CONTENT_MAX_H=360; FFMPEG_CRF=32; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="64k";;
    phone_fast) YTDLP_FORMAT_SELECTOR="bestvideo[height<=480]+bestaudio/best[height<=480]"; FFMPEG_CONTENT_MAX_H=480; FFMPEG_CRF=25; FFMPEG_PRESET="veryfast"; FFMPEG_AUDIO_KBPS="96k";;
    sd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=720]+bestaudio/best[height<=720]"; FFMPEG_CONTENT_MAX_H=720; FFMPEG_CRF=19; FFMPEG_PRESET="fast"; FFMPEG_AUDIO_KBPS="128k";;
    hd) YTDLP_FORMAT_SELECTOR="bestvideo[height<=1080]+bestaudio/best[height<=1080]"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=13; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="160k";;
    source_mp4) YTDLP_FORMAT_SELECTOR="bestvideo[height<=2160][ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec=aac]/best"; FFMPEG_CONTENT_MAX_H=1080; FFMPEG_CRF=22; FFMPEG_PRESET="medium"; FFMPEG_AUDIO_KBPS="192k";;
    *) msg_error "Unknown quality profile: $quality_profile"; show_help; exit 1;;
esac

# Construct the FFmpeg video filter for resizing and padding
target_pad_width=$(( video_width >= video_height ? 1280 : 720 ))
target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))
ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"

# Show concise progress stats for ffmpeg
ffmpeg_cmd_base=(ffmpeg -hide_banner -stats -y)

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
    start_label=$(to_hms_label "$start_sec"); end_label=$(to_hms_label "$end_sec")
    output_final_mp4="${output_filename_stem}_${start_label}_to_${end_label}.mp4"
    ffmpeg_to_duration=$(echo "$end_sec - $start_sec" | bc)
    msg "Trimming video to: $output_final_mp4"
    "${ffmpeg_cmd_base[@]}" -ss "$start_sec" -i "$input_file" -to "$ffmpeg_to_duration" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
else
    output_final_mp4="${output_filename_stem}_full.mp4"
    msg "Re-encoding full video to: $output_final_mp4"
    "${ffmpeg_cmd_base[@]}" -i "$input_file" -vf "$ffmpeg_vf" -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" "$output_final_mp4"
fi

# Check for successful completion
if [[ $? -eq 0 && -s "$output_final_mp4" ]]; then
    msg_ok "Successfully processed video saved as: $output_final_mp4"
else
    msg_error "ffmpeg processing failed or output file is empty."
    exit 1
fi

end_processing_timer=$(date +%s.%N)

# ---------------[ FINAL SUMMARY ]---------------

end_total_timer=$(date +%s.%N)

msg_ok "Script finished."

echo "-------------------------------------"
echo "        Processing Timers"
echo "-------------------------------------"
if [[ -v start_download_timer ]]; then
    printf "Download Time:      %.2f seconds\n" $(echo "$end_download_timer - $start_download_timer" | bc -l)
    echo "-------------------------------------"
fi
printf "Processing Time:    %.2f seconds\n" $(echo "$end_processing_timer - $start_processing_timer" | bc -l)
echo "-------------------------------------"
printf "Total Script Time:  %.2f seconds\n" $(echo "$end_total_timer - $start_total_timer" | bc -l)
echo "-------------------------------------"

