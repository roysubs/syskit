#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-08-29 (v9)

# This script has been updated to be a universal video processing tool.
# It can now handle both YouTube URLs and local video files.
# It includes presets for quality-based encoding (CRF) and precise
# size-based encoding (calculating bitrate for a target file size).

set -e

# ---------------[ CONFIG ]---------------
DEFAULT_OUTDIR="."
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4, half, quarter, 10mb
YTDLP_CMD="" # Global variable to hold the yt-dlp command path

# ---------------[ HELPER FUNCTIONS ]---------------

# Function to display help information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <source> [start_time] [end_time]
Processes a video file from a local path or YouTube URL.
It performs optional trimming and re-encoding to a specified quality or target size.
Filenames are generated from the YouTube Video ID or the original filename.

OPTIONS:
  --out DIR         Set the output directory (default: current directory).
  --quality PROFILE Set the quality profile.
  -h, --help        Show this help message.

QUALITY PROFILES:
  phone_small:  Tiny file size (360p max) for small screens.
  phone_fast:   Small file (480p max), optimized for speed.
  sd:           Standard definition (720p max), good general quality. (Default)
  hd:           High definition (1080p max), best CRF-based quality.
  source_mp4:   Downloads best MP4 source, then re-encodes.
  half:         Aims for 1/2 original file size with the best possible quality.
  quarter:      Aims for 1/4 original file size with the best possible quality.
  10mb:         Compresses to just under 10MB for Discord/social media.

TIME FORMAT:
  Supports hh:mm:ss (01:03:18), mm:ss (2:05), or seconds (125).
  This includes milliseconds (e.g., 01:03:18.3, or, 1:31.5) for fine adjustment.

EXAMPLES:
  # Process a local file, aiming for under 10MB
  $(basename "$0") --quality 10mb video.mp4

  # Download a YouTube video and trim it to half its original size
  $(basename "$0") "https://youtu.be/dQw4w9WgXcQ" 1:09 2:15 --quality half
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

    # Check for core dependencies that do not have auto-install logic
    for cmd in bc date stat curl awk grep; do
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

    # Check for yt-dlp and update if necessary.
    if ! command_exists "$EXE_NAME" && [ ! -x "$TARGET_EXE_PATH" ]; then
        msg_warn "yt-dlp not found."
        read -r -p "Attempt to download the latest version to $INSTALL_DIR? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local LATEST_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
            mkdir -p "$INSTALL_DIR"
            msg "Downloading from: $LATEST_URL"
            if curl -SL --progress-bar -o "$TARGET_EXE_PATH" "$LATEST_URL" && chmod +x "$TARGET_EXE_PATH"; then
                msg_ok "yt-dlp installed successfully."
            else
                msg_error "Download or installation failed."
                exit 1
            fi
        else
            msg_error "yt-dlp is required for downloading videos. Exiting."
            exit 1
        fi
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

# Robust argument parsing
outdir="$DEFAULT_OUTDIR"; quality_profile="$DEFAULT_QUALITY_PROFILE"
positional_args=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --out) outdir="$2"; shift; shift;;
        --quality) quality_profile="$2"; shift; shift;;
        -h|--help) show_help; exit 0;;
        -*) msg_error "Error: Unknown option: $1" >&2; show_help; exit 1;;
        *) positional_args+=("$1"); shift;;
    esac
done
set -- "${positional_args[@]}" # Restore positional arguments

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
input_file=""

# Core logic for handling local files and YouTube URLs.
if [[ -f "$source_input" ]]; then
    msg_ok "Source is a local file: $source_input"
    input_file="$source_input"
    output_filename_stem="${outdir}/$(basename "${source_input%.*}")"
elif [[ "$source_input" =~ ^https?:// ]]; then
    msg "Source is a URL. Detecting YouTube video ID..."
    video_id=$(get_video_id "$source_input")
    msg_ok "Detected Video ID: $video_id"
    output_filename_stem="${outdir}/${video_id}"

    downloaded_source_file="${output_filename_stem}_source.mp4"
    start_download_timer=$(date +%s.%N)

    if [[ ! -f "$downloaded_source_file" ]]; then
        msg "Source file not found. Downloading video to: $downloaded_source_file"
        if "$YTDLP_CMD" -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 -o "$downloaded_source_file" "$source_input"; then
            msg_ok "Download complete."
        else
            msg_error "yt-dlp failed to download the video."
            if [ -f "$downloaded_source_file" ]; then rm "$downloaded_source_file"; fi
            exit 1
        fi
    else
        msg_ok "Source file already exists. Skipping download."
    fi
    end_download_timer=$(date +%s.%N)
    input_file="$downloaded_source_file"
else
    msg_error "Invalid source. Please provide a valid local file path or YouTube URL."
    show_help; exit 1;
fi

if [[ ! -s "$input_file" ]]; then
    msg_error "Source file is missing or empty. Cannot proceed."
    exit 1
fi

# ---------------[ VIDEO PROCESSING (FFMPEG) ]---------------

msg "Starting video processing..."
start_processing_timer=$(date +%s.%N)

# Get video properties from the input file
video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$input_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$input_file")
source_size_bytes=$(stat -c%s "$input_file")

# Determine the duration for bitrate calculation (either the full duration or the trimmed duration)
calc_duration_sec=""
if [[ -n "$start_sec" && -n "$end_sec" ]]; then
    calc_duration_sec=$(echo "$end_sec - $start_sec" | bc)
else
    calc_duration_sec=$(ffprobe -v error -i "$input_file" -show_entries format=duration -of default=noprint_wrappers=1:nokey=1)
fi

if [[ -z "$video_width" || -z "$video_height" ]]; then msg_error "Could not get video dimensions."; exit 1; fi
if [[ -z "$calc_duration_sec" ]]; then msg_error "Could not get video duration."; exit 1; fi

msg "Source dimensions: ${video_width}x${video_height}, Size: $(printf "%.2f" $(echo "$source_size_bytes/1024/1024" | bc -l)) MB"

# Construct FFmpeg commands
ffmpeg_cmd_base=(ffmpeg -hide_banner -stats -y)
ffmpeg_video_params=()
ffmpeg_audio_params=(-c:a aac -b:a 128k) # Default audio params

# Get quality profile parameters
case "$quality_profile" in
    phone_small) FFMPEG_CONTENT_MAX_H=360; ffmpeg_video_params=(-c:v libx264 -crf 32 -preset fast);;
    phone_fast)  FFMPEG_CONTENT_MAX_H=480; ffmpeg_video_params=(-c:v libx264 -crf 25 -preset veryfast);;
    sd)          FFMPEG_CONTENT_MAX_H=720; ffmpeg_video_params=(-c:v libx264 -crf 19 -preset fast);;
    hd)          FFMPEG_CONTENT_MAX_H=1080; ffmpeg_video_params=(-c:v libx264 -crf 13 -preset medium);;
    source_mp4)  FFMPEG_CONTENT_MAX_H=2160; ffmpeg_video_params=(-c:v libx264 -crf 22 -preset medium); ffmpeg_audio_params=(-c:a aac -b:a 192k);;

    10mb|half|quarter)
        target_size_bytes=0
        case "$quality_profile" in
            10mb) target_size_bytes=$(echo "9.8 * 1024 * 1024" | bc);; # 9.8MB to be safe
            half) target_size_bytes=$(echo "$source_size_bytes / 2" | bc);;
            quarter) target_size_bytes=$(echo "$source_size_bytes / 4" | bc);;
        esac

        if [[ "$quality_profile" == "10mb" && $(echo "$source_size_bytes < $target_size_bytes" | bc -l) -eq 1 && -z "$start_sec" ]]; then
            msg_warn "Source file is already under 10MB and no trimming is requested. No re-encoding needed."
        else
            msg "Calculating bitrate for target size: $(printf "%.2f" $(echo "$target_size_bytes/1024/1024" | bc -l)) MB over ${calc_duration_sec}s"
            audio_bitrate_k=128
            target_total_bitrate_k=$(echo "($target_size_bytes * 8 / $calc_duration_sec) / 1000" | bc)
            target_video_bitrate_k=$(echo "$target_total_bitrate_k - $audio_bitrate_k" | bc)

            if (( $(echo "$target_video_bitrate_k < 100" | bc -l) )); then
                msg_warn "Calculated video bitrate is very low (${target_video_bitrate_k}k). Quality may be poor."
            fi

            ffmpeg_video_params=(-c:v libx264 -b:v "${target_video_bitrate_k}k" -pass 1 -an -f null /dev/null)
            ffmpeg_video_params_pass2=(-c:v libx264 -b:v "${target_video_bitrate_k}k" -pass 2)
        fi
        FFMPEG_CONTENT_MAX_H=$video_height # Use original height for size-based
        ;;
    *) msg_error "Unknown quality profile: $quality_profile"; show_help; exit 1;;
esac

# Construct the FFmpeg video filter for resizing and padding
target_pad_width=$(( video_width >= video_height ? 1280 : 720 ))
target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))
ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"

# Set up final output filename and trimming parameters
trim_opts=()
time_suffix=""
if [[ -n "$start_sec" && -n "$end_sec" ]]; then
    start_label=$(to_hms_label "$start_sec"); end_label=$(to_hms_label "$end_sec")
    time_suffix="_${start_label}_to_${end_label}"
    ffmpeg_duration=$(echo "$end_sec - $start_sec" | bc)
    trim_opts=(-ss "$start_sec" -t "$ffmpeg_duration") # Corrected from -to to -t
fi
output_final_mp4="${output_filename_stem}_${quality_profile}${time_suffix}.mp4"

# Execute the final FFmpeg command
msg "Processing video to: $output_final_mp4"
if [[ -n "${ffmpeg_video_params_pass2[*]+x}" ]]; then
    # Two-pass encoding for bitrate targets
    msg "Performing two-pass encoding for precise file size..."
    "${ffmpeg_cmd_base[@]}" -i "$input_file" "${trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params[@]}"
    "${ffmpeg_cmd_base[@]}" -i "$input_file" "${trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params_pass2[@]}" "${ffmpeg_audio_params[@]}" -movflags +faststart "$output_final_mp4"
elif [[ "$quality_profile" == "10mb" && $(echo "$source_size_bytes < 10276044" | bc -l) -eq 1 && -z "${trim_opts[*]}" ]]; then
    # Special case: under 10mb and no trimming, just copy
    cp "$input_file" "$output_final_mp4"
    msg_ok "File copied without re-encoding."
elif [[ "$quality_profile" == "10mb" && $(echo "$source_size_bytes < 10276044" | bc -l) -eq 1 && -n "${trim_opts[*]}" ]]; then
    # Special case: under 10mb WITH trimming. Must re-encode but without changing quality (stream copy).
    msg_warn "Source is under 10MB but trimming is requested. Trimming via stream copy..."
    "${ffmpeg_cmd_base[@]}" "${trim_opts[@]}" -i "$input_file" -c:v copy -c:a copy -movflags +faststart "$output_final_mp4"
else
    # Standard single-pass CRF encoding
    "${ffmpeg_cmd_base[@]}" -i "$input_file" "${trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params[@]}" "${ffmpeg_audio_params[@]}" -movflags +faststart "$output_final_mp4"
fi

# Clean up ffmpeg2pass log files
rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree

# Check for successful completion
if [[ $? -eq 0 && -s "$output_final_mp4" ]]; then
    final_size_mb=$(printf "%.2f" $(echo "$(stat -c%s "$output_final_mp4")/1024/1024" | bc -l))
    msg_ok "Successfully processed video saved as: $output_final_mp4 (Size: ${final_size_mb} MB)"
else
    msg_error "ffmpeg processing failed or output file is empty."
    exit 1
fi

end_processing_timer=$(date +%s.%N)

# ---------------[ FINAL SUMMARY ]---------------

end_total_timer=$(date +%s.%N)

msg_ok "Script finished."
echo "-------------------------------------"
echo "         Processing Timers"
echo "-------------------------------------"
if [[ -v start_download_timer ]]; then
    printf "Download Time:     %.2f seconds\n" $(echo "$end_download_timer - $start_download_timer" | bc -l)
    echo "-------------------------------------"
fi
printf "Processing Time:   %.2f seconds\n" $(echo "$end_processing_timer - $start_processing_timer" | bc -l)
echo "-------------------------------------"
printf "Total Script Time: %.2f seconds\n" $(echo "$end_total_timer - $start_total_timer" | bc -l)
echo "-------------------------------------"



# ---------------[ SCRIPT DEEP DIVE & CONCEPTS ]---------------
#
# This section provides a detailed explanation of the video encoding
# techniques and FFmpeg concepts used in this script.
#
#
# ## Quality vs. Size: Two Main Approaches
#
# There are two primary ways to control the final quality and size of a
# video during encoding:
#
# 1.  **Constant Rate Factor (CRF):** This is a quality-based approach.
#     You tell the encoder what level of quality you want to maintain,
#     and it uses whatever bitrate is necessary to achieve that quality.
#
#     - **How it works:** A lower CRF number means higher quality and a larger
#       file size. A higher CRF number means lower quality and a smaller
#       file size.
#     - **Range:** The scale is typically 0-51. 0 is lossless, ~18 is often
#       considered "visually lossless", and ~23 is a good default.
#     - **In this script:** The `phone_small`, `sd`, and `hd` presets use
#       CRF. This is great when your primary goal is a specific quality
#       level and you aren't concerned about the exact final file size.
#
# 2.  **Target Bitrate (Two-Pass Encoding):** This is a size-based approach.
#     You tell the encoder what final file size you want, and it calculates
#     the average bitrate needed to hit that target.
#
#     - **How it works:** We calculate the required bitrate using a simple
#       formula: `bitrate = (target_file_size_in_bits / duration_in_seconds)`.
#       We then instruct the encoder to average this bitrate over the
#       duration of the video.
#     - **In this script:** The `10mb`, `half`, and `quarter` presets use this
#       method. This is essential when you have a strict file size limit,
#       like for a Discord upload.
#
#
# ## The Magic of Two-Pass Encoding
#
# When using a target bitrate, the best results are achieved with two-pass
# encoding. This script uses it for all size-based presets.
#
# - **Pass 1:** FFmpeg analyzes the entire video to learn where the complex
#   and simple scenes are. For example, a high-action scene needs more
#   bits than a static scene. It writes this analysis data to a log file
#   but creates no video output (`-f null /dev/null`).
#
# - **Pass 2:** FFmpeg uses the log file from Pass 1 to intelligently
#   distribute the available bits. It allocates more of the "bitrate budget"
#   to complex scenes and fewer bits to simple scenes. This results in
#   much higher overall quality for the same target file size compared to a
#   single pass.
#
#
# ## Web Optimization: The `-movflags +faststart` Flag
#
# This is a fascinating and crucial flag for any video intended for the web.
# MP4/MOV files have a piece of metadata called the "moov atom," which contains
# the index of the file (like a table of contents). By default, this atom is
# written at the *end* of the file after encoding is complete.
#
# - **The Problem:** A web browser or video player needs the "moov atom" to
#   start playing the video. If it's at the end, the entire file must be
#   downloaded before playback can begin.
#
# - **The Solution:** The `-movflags +faststart` command tells FFmpeg to
#   reserve space at the beginning of the file and then move the "moov atom"
#   there after encoding is finished. This allows the video to start
#   streaming and playing almost instantly.
#
#
# ## Video Filtering (`-vf`): Resizing and Padding
#
# The script uses a complex video filtergraph (`-vf`) to intelligently
# resize and pad the video to fit a standard 16:9 frame (1280x720 or
# 720x1280 for vertical video).
#
# Here's a breakdown of the filter chain:
#
# `scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})'`
#   - This first scales the video down. It ensures the height is no more
#     than the maximum allowed by the quality profile (e.g., 720 for `sd`).
#     The `-2` for the width ensures the aspect ratio is maintained and the
#     width is an even number, which is required by many encoders.
#
# `scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease`
#   - This second scale ensures the video is not wider or taller than the
#     final padded frame. The `force_original_aspect_ratio=decrease` part
#     is key—it scales the video down to fit *within* the target dimensions
#     while preserving its aspect ratio.
#
# `pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'`
#   - Finally, this pads the (now smaller) video with black bars to fill
#     the rest of the 1280x720 or 720x1280 frame. The `x` and `y` expressions
#     center the video perfectly within the frame.

