#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-08-29 (v9)
# Modified again based on user feedback 2025-09-07 (v10)

# This script has been updated to be a universal video processing tool.
# It can now handle both YouTube URLs/IDs and local video files.
# It includes presets for quality-based encoding (CRF) and precise
# size-based encoding (calculating bitrate for a target file size).
# New features: Title extraction and renaming for YouTube videos, improved input parsing.

set -e

# ---------------[ CONFIG ]---------------
# REQ 1: Default output directory changed to home directory (~).
DEFAULT_OUTDIR="$HOME"
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4, half, quarter, 10mb
YTDLP_CMD="" # Global variable to hold the yt-dlp command path
youtube_title="" # Global variable to store fetched YouTube title for later rename

# ---------------[ HELPER FUNCTIONS ]---------------

# Function to display help information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <source> [start_time] [end_time]
Processes a video file from a local path or YouTube URL/ID.
It performs optional trimming and re-encoding to a specified quality or target size.
Filenames are generated from the YouTube Video ID or the original filename,
with an option to rename YouTube videos based on their title post-processing.

OPTIONS:
  --out DIR         Set the output directory (default: home directory ~). Use "." for current directory.
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

  # Download a YouTube video by ID and trim it
  $(basename "$0") 5v3bbkJW0gQ 1:09 2:15 --quality half

  # Process using a full URL and save to current directory
  $(basename "$0") --out . "https://youtu.be/dQw4w9WgXcQ" 0:30 1:00
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

# REQ 2: Updated get_video_id function to handle various input formats flexibly.
# Extracts YouTube video ID from full URLs, partial strings (e.g., watch?v=ID), or just the ID itself.
get_video_id() {
    local input="$1"
    # Pattern 1: Extract from 'v=' parameter (handles full URLs, fragments like 'watch?v=ID', '?v=ID', 'v=ID')
    # Greedily matches the 11 characters after 'v='
    if [[ "$input" =~ v=([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    # Pattern 2: Extract from short URLs (youtu.be/) or specific paths (/shorts/, /live/, /embed/)
    if [[ "$input" =~ (youtu\.be/|shorts/|live/|embed/)([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[2]}"
        return
    fi
    # Pattern 3: Assume input IS the ID itself if it matches the format exactly.
    if [[ "$input" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
        echo "$input"
        return
    fi
    # Return empty if no pattern matches
    echo ""
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

# REQ 3: Normalization function for filenames. Removes invalid characters and replaces spaces.
normalize_filename() {
    local filename="$1"
    # Replace spaces and punctuation with underscores
    filename=$(echo "$filename" | sed 's/[[:space:]]\+/_/g; s/[][()!"#$%&'\''*,:;<=>?@\\^`{|}~]/_/g')
    # Remove characters unsafe for Windows/Linux filesystems (keep letters, numbers, underscore, hyphen, period)
    filename=$(echo "$filename" | sed 's/[^a-zA-Z0-9_.-]//g')
    # Consolidate multiple underscores into one
    filename=$(echo "$filename" | sed 's/__*/_/g')
    # Remove leading/trailing underscores or periods
    filename=$(echo "$filename" | sed 's/^[._-]//; s/[._-]$//')
    echo "$filename"
}

# Function to handle dependency checking and installation
main_dep_install() {
    local EXE_NAME="yt-dlp"; local TARGET_EXE_PATH="$HOME/.local/bin/$EXE_NAME"

    # Check for core dependencies that do not have auto-install logic
    for cmd in bc date stat curl awk grep ffmpeg ffprobe; do
        if ! command_exists "$cmd"; then
            msg_warn "Dependency '$cmd' is not found.";
            if [[ "$cmd" == "ffmpeg" || "$cmd" == "ffprobe" ]] && command_exists apt-get && command_exists sudo; then
                read -r -p "Attempt to install 'ffmpeg' using 'sudo apt-get install ffmpeg'? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if sudo apt-get install -y ffmpeg; then msg_ok "$cmd installed."; else msg_error "Failed to install $cmd."; exit 1; fi
                else
                    msg_error "$cmd is required. Exiting."; exit 1;
                fi
            else
                 msg_error "Missing essential dependency: '$cmd'. Please install it manually."
                 exit 1
            fi
        fi
    done

    # Check for yt-dlp and update if necessary.
    if ! command_exists "$EXE_NAME" && [ ! -x "$TARGET_EXE_PATH" ]; then
        msg_warn "yt-dlp not found."
        read -r -p "Attempt to download the latest version to $HOME/.local/bin? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local LATEST_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
            mkdir -p "$HOME/.local/bin"
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
    # msg_ok "All dependencies are satisfied." # Moved to be called after parsing to reduce noise on help command
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
    msg_error "A source (local file or YouTube URL/ID) is required."
    show_help; exit 1;
fi

# REQ 1: Resolve output directory path, handling special case for ~
# REQ 1: Handle --out . by resolving it to pwd. realpath ensures clean path.
if [[ "$outdir" == "~" ]]; then outdir="$HOME"; fi
outdir=$(realpath "$outdir")
mkdir -p "$outdir"

# Perform dependency checks before any processing begins
main_dep_install
msg_ok "All dependencies are satisfied."

# Time conversion for trimming
start_sec=$(convert_to_seconds "$start_input"); end_sec=$(convert_to_seconds "$end_input")
if [[ -n "$start_sec" && -n "$end_sec" && $(echo "$end_sec <= $start_sec" | bc -l) -eq 1 ]]; then
    msg_error "End time must be greater than start time."; exit 1;
fi

# Determine the final output filename stem
output_filename_stem=""
input_file=""
video_id=""

# REQ 2: Updated source handling logic.
# 1. Check if the input is a local file.
# 2. If not a file, try to extract a YouTube video ID from the input string.
# 3. If ID extraction fails, error out.

if [[ -f "$source_input" ]]; then
    # --- Local File Processing ---
    msg_ok "Source is a local file: $source_input"
    input_file="$source_input"
    # Use realpath to get absolute path for input file to avoid issues if script changes directory (though it doesn't here)
    input_file=$(realpath "$input_file")
    output_filename_stem="${outdir}/$(basename "${input_file%.*}")"
else
    # --- YouTube Processing ---
    msg "Source is not a local file. Attempting YouTube ID extraction..."
    video_id=$(get_video_id "$source_input")

    if [[ -n "$video_id" ]]; then
        msg_ok "Detected Video ID: $video_id"

        # REQ 3: Fetch YouTube video title
        msg "Fetching video title..."
        # Store title in global variable for use in final rename prompt
        youtube_title=$("$YTDLP_CMD" --get-title --skip-download --no-warnings "$video_id" 2>/dev/null || echo "")
        if [[ -n "$youtube_title" ]]; then
            msg_ok "Fetched Title: $youtube_title"
        else
            msg_warn "Could not fetch video title. Will use video ID for filename."
        fi

        # Set base filename for download. We always use the ID for the *source* download file
        # to ensure consistency for future runs and avoid complex character issues in source filename.
        output_filename_stem="${outdir}/${video_id}"
        downloaded_source_file="${output_filename_stem}_source.mp4"
        start_download_timer=$(date +%s.%N)

        if [[ ! -f "$downloaded_source_file" ]]; then
            msg "Source file not found. Downloading video to: $downloaded_source_file"
            # Use video_id for download to ensure yt-dlp gets the correct video even if source_input was partial
            if "$YTDLP_CMD" -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" --merge-output-format mp4 -o "$downloaded_source_file" "$video_id"; then
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
        msg_error "Invalid source. Please provide a valid local file path or YouTube URL/ID."
        show_help; exit 1;
    fi
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
    trim_opts=(-ss "$start_sec" -t "$ffmpeg_duration")
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
echo "           Processing Timers"
echo "-------------------------------------"
if [[ -v start_download_timer ]]; then
    printf "Download Time:     %.2f seconds\n" $(echo "$end_download_timer - $start_download_timer" | bc -l)
    echo "-------------------------------------"
fi
printf "Processing Time:   %.2f seconds\n" $(echo "$end_processing_timer - $start_processing_timer" | bc -l)
echo "-------------------------------------"
printf "Total Script Time: %.2f seconds\n" $(echo "$end_total_timer - $start_total_timer" | bc -l)
echo "-------------------------------------"

# REQ 3: Rename offer based on fetched YouTube title.
if [[ -n "$youtube_title" ]]; then
    normalized_title=$(normalize_filename "$youtube_title")

    # Construct proposed new name: {Title}{timestamp_suffix}.mp4 in the output directory.
    # The quality profile part is omitted for a cleaner final name.
    proposed_new_name="${outdir}/${normalized_title}${time_suffix}.mp4"

    # Ensure proposed name is valid and different from original processed file name
    if [[ -n "$normalized_title" && "$proposed_new_name" != "$output_final_mp4" ]]; then
        msg_warn "\nWould you like to rename the final file using the video title?"
        echo -e "Current: ${COLOR_YELLOW}$(basename "$output_final_mp4")${COLOR_RESET}"
        echo -e "New:     ${COLOR_GREEN}$(basename "$proposed_new_name")${COLOR_RESET}"
        read -r -p "Rename file? (y/N): " confirm_rename
        if [[ "$confirm_rename" =~ ^[Yy]$ ]]; then
            mv -v "$output_final_mp4" "$proposed_new_name"
            msg_ok "File renamed successfully."
        fi
    fi
fi
