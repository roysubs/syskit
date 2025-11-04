#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# Modified by Gemini @ Google 2025-08-29 (v9)
# Modified again based on user feedback 2025-09-12 (v15)

# This script is a universal video processing tool for YouTube URLs/IDs and local files.
# It includes presets for quality/size-based encoding and optional trimming.
# Features: --rename flag, detailed final summary, and optimized FFmpeg seeking for speed.

set -e

# ---------------[ CONFIG ]---------------
DEFAULT_OUTDIR="$HOME"
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4, half, quarter, 10mb
YTDLP_CMD="" # Global variable to hold the yt-dlp command path
youtube_title="" # Global variable to store fetched YouTube title for later rename
youtube_duration="" # Global variable to store fetched YouTube duration for summary

# ---------------[ HELPER FUNCTIONS ]---------------

# Function to display help information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <source> [start_time] [end_time]
Processes a video file from a local path or YouTube URL/ID.
It performs optional trimming and re-encoding to a specified quality or target size.

OPTIONS:
  --out DIR         Set the output directory (default: home directory ~). Use "." for current directory.
  --quality PROFILE Set the quality profile.
  --rename          For YouTube videos, automatically rename the final file using the fetched title.
                    This will overwrite any existing file with the same name.
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
  Supports hh:mm:ss (01:03:18), mm:ss (2:05), or seconds (125), including milliseconds.

EXAMPLES:
  # Download a YouTube video by ID, trim it, and automatically rename it using its title.
  $(basename "$0") --rename 5v3bbkJW0gQ 1:09 2:15 --quality half

  # Process a local file and save to the current directory.
  $(basename "$0") --out . --quality 10mb video.mp4
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
command_exists() { command -v "$2" >/dev/null 2>&1; }
# Function to check if a command exists on the system
command_exists() {
    # First, try the standard 'command -v' which is fast and respects user's PATH
    if command -v "$1" >/dev/null 2>&1; then
        return 0 # Success
    fi

    # As a fallback for essential system utilities, check common paths directly
    for path in /bin /usr/bin /sbin /usr/sbin; do
        if [[ -x "$path/$1" ]]; then
            return 0 # Success
        fi
    done

    return 1 # Failure
}

# Function to check for common signs of a VPN connection
check_for_vpn() {
    # Check for common VPN interface names (e.g., tun0, ppp0)
    if ip addr | grep -q -E 'tun[0-9]+|ppp[0-9]+'; then
        return 0 # VPN likely detected
    fi

    # Check if the default route's interface name suggests a VPN
    local default_interface
    default_interface=$(ip route | grep '^default' | awk '{print $5}')
    if [[ -n "$default_interface" ]] && echo "$default_interface" | grep -q -i 'vpn'; then
        return 0 # VPN likely detected
    fi

    return 1 # No obvious VPN signs detected
}

# Must call via if-then-fi as otherwise set -e will see return 0 as an error and exit immediately
if check_for_vpn; then
    msg_warn "A VPN connection appears to be active. This may cause network timeouts. If the script fails, try disabling your VPN."
fi

# Extracts YouTube video ID from various input formats.
get_video_id() {
    local input="$1"
    if [[ "$input" =~ v=([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$input" =~ (youtu\.be/|shorts/|live/|embed/)([a-zA-Z0-9_-]{11}) ]]; then
        echo "${BASH_REMATCH[2]}"
        return
    fi
    if [[ "$input" =~ ^[a-zA-Z0-9_-]{11}$ ]]; then
        echo "$input"
        return
    fi
    echo ""
}

# Function to convert time from various formats to seconds
convert_to_seconds() {
    local t=$1
    if [[ -z "$t" ]]; then echo ""; return; fi
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

# Normalization function for filenames. Removes invalid characters and replaces spaces.
normalize_filename() {
    local filename="$1"
    filename=$(echo "$filename" | sed 's/[[:space:]]\+/_/g; s/[][()!"#$%&'\''*,:;<=>?@\\^`{|}~]/_/g')
    filename=$(echo "$filename" | sed 's/[^a-zA-Z0-9_.-]//g')
    filename=$(echo "$filename" | sed 's/__*/_/g')
    filename=$(echo "$filename" | sed 's/^[._-]//; s/[._-]$//')
    echo "$filename"
}

# Function to get a terse summary of a media file's properties.
get_file_summary() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        echo "File not found."
        return
    fi
    local summary_data
    summary_data=$(ffprobe -v error \
              -select_streams v:0 \
              -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate \
              -show_entries format=duration,size,format_name \
              -of default=noprint_wrappers=1 "$file_path")
    local codec="N/A" width="N/A" height="N/A" framerate="N/A" bitrate="N/A" duration="N/A" size="N/A" format="N/A"
    while IFS='=' read -r key value; do
        case "$key" in
            codec_name) codec="$value" ;;
            width) width="$value" ;;
            height) height="$value" ;;
            r_frame_rate) framerate="$value" ;;
            bit_rate) bitrate="$value" ;;
            duration) duration="$value" ;;
            size) size="$value" ;;
            format_name) format="$value" ;;
        esac
    done <<< "$summary_data"
    local framerate_clean="N/A"
    if [[ "$framerate" != "N/A" && "$framerate" != "0/0" ]]; then
        framerate_clean=$(printf "%.2f" "$(echo "$framerate" | bc -l)")
    fi
    local duration_fmt="N/A"
    if [[ "$duration" != "N/A" ]]; then
        duration_fmt=$(printf "%.2f" "$duration")
    fi
    local size_mb="N/A"
    if [[ "$size" != "N/A" ]]; then
        size_mb=$(printf "%.2f" "$(echo "$size / 1048576" | bc -l)")
    fi
    if [[ "$bitrate" == "N/A" && "$size" != "N/A" && "$duration" != "N/A" && $(echo "$duration > 0" | bc -l) -eq 1 ]]; then
        bitrate=$(echo "($size * 8) / $duration" | bc)
    fi
    local bitrate_kbps="N/A"
    if [[ "$bitrate" != "N/A" ]]; then
        bitrate_kbps=$(printf "%.0f" "$(echo "$bitrate / 1000" | bc -l)")
    fi
    format=$(echo "$format" | cut -d ',' -f 1)
    echo "${format^^}: ${width}x${height} @ ${framerate_clean}fps, ${duration_fmt}s, ${size_mb}MB, ${bitrate_kbps}kbps (${codec})"
}

# Function to handle dependency checking and installation
main_dep_install() {
    local EXE_NAME="yt-dlp"; local TARGET_EXE_PATH="$HOME/.local/bin/$EXE_NAME"
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
    YTDLP_CMD=$(command -v "$EXE_NAME" || echo "$TARGET_EXE_PATH")
    if ! [ -x "$YTDLP_CMD" ]; then
      msg_error "yt-dlp command is not available after check/install. Exiting."; exit 1;
    fi
}

# ---------------[ MAIN EXECUTION ]-----------------

start_total_timer=$(date +%s.%N)

outdir="$DEFAULT_OUTDIR"; quality_profile="$DEFAULT_QUALITY_PROFILE"
auto_rename_flag=false
positional_args=()
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --out) outdir="$2"; shift; shift;;
        --quality) quality_profile="$2"; shift; shift;;
        --rename) auto_rename_flag=true; shift;;
        -h|--help) show_help; exit 0;;
        -*) msg_error "Error: Unknown option: $1" >&2; show_help; exit 1;;
        *) positional_args+=("$1"); shift;;
    esac
done
set -- "${positional_args[@]}"

source_input="$1"; start_input="$2"; end_input="$3"
is_youtube_input=false

if [[ -z "$source_input" ]]; then
    msg_error "A source (local file or YouTube URL/ID) is required."
    show_help; exit 1;
fi

if [[ "$outdir" == "~" ]]; then outdir="$HOME"; fi
outdir=$(realpath "$outdir")
mkdir -p "$outdir"

main_dep_install
msg_ok "All dependencies are satisfied."

start_sec=$(convert_to_seconds "$start_input"); end_sec=$(convert_to_seconds "$end_input")
if [[ -n "$start_sec" && -n "$end_sec" && $(echo "$end_sec <= $start_sec" | bc -l) -eq 1 ]]; then
    msg_error "End time must be greater than start time."; exit 1;
fi

output_filename_stem=""
input_file=""
video_id=""

if [[ -f "$source_input" ]]; then
    msg_ok "Source is a local file: $source_input"
    input_file=$(realpath "$source_input")
    output_filename_stem="${outdir}/$(basename "${input_file%.*}")"
else
    is_youtube_input=true
    msg "Source is not a local file. Attempting YouTube ID extraction..."
    video_id=$(get_video_id "$source_input")
    if [[ -n "$video_id" ]]; then
        msg_ok "Detected Video ID: $video_id"
        msg "Fetching video metadata..."
        youtube_title=$("$YTDLP_CMD" --get-title --skip-download --no-warnings "$video_id" 2>/dev/null || echo "")
        youtube_duration=$("$YTDLP_CMD" --get-duration --skip-download --no-warnings "$video_id" 2>/dev/null || echo "")
        if [[ -n "$youtube_title" ]]; then
            msg_ok "Fetched Title: $youtube_title"
            msg_ok "Fetched Duration: $youtube_duration"
        else
            msg_warn "Could not fetch video metadata. Renaming will not be possible."
        fi
        output_filename_stem="${outdir}/${video_id}"
        downloaded_source_file="${output_filename_stem}_source.mp4"
        start_download_timer=$(date +%s.%N)
        if [[ ! -f "$downloaded_source_file" ]]; then
            msg "Downloading video to: $downloaded_source_file"
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

video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$input_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$input_file")
source_size_bytes=$(stat -c%s "$input_file")

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
    calc_duration_sec=$(echo "$end_sec - $start_sec" | bc)
else
    calc_duration_sec=$(ffprobe -v error -i "$input_file" -show_entries format=duration -of default=noprint_wrappers=1:nokey=1)
fi

if [[ -z "$video_width" || -z "$video_height" ]]; then msg_error "Could not get video dimensions."; exit 1; fi
if [[ -z "$calc_duration_sec" ]]; then msg_error "Could not get video duration."; exit 1; fi

msg "Source dimensions: ${video_width}x${video_height}, Size: $(printf "%.2f" $(echo "$source_size_bytes/1024/1024" | bc -l)) MB"

ffmpeg_cmd_base=(ffmpeg -hide_banner -stats -y)
ffmpeg_video_params=()
ffmpeg_audio_params=(-c:a aac -b:a 128k)

case "$quality_profile" in
    phone_small) FFMPEG_CONTENT_MAX_H=360; ffmpeg_video_params=(-c:v libx264 -crf 32 -preset fast);;
    phone_fast)  FFMPEG_CONTENT_MAX_H=480; ffmpeg_video_params=(-c:v libx264 -crf 25 -preset veryfast);;
    sd)          FFMPEG_CONTENT_MAX_H=720; ffmpeg_video_params=(-c:v libx264 -crf 19 -preset fast);;
    hd)          FFMPEG_CONTENT_MAX_H=1080; ffmpeg_video_params=(-c:v libx264 -crf 13 -preset medium);;
    source_mp4)  FFMPEG_CONTENT_MAX_H=2160; ffmpeg_video_params=(-c:v libx264 -crf 22 -preset medium); ffmpeg_audio_params=(-c:a aac -b:a 192k);;
    10mb|half|quarter)
        target_size_bytes=0
        case "$quality_profile" in
            10mb) target_size_bytes=$(echo "9.8 * 1024 * 1024" | bc);;
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
        FFMPEG_CONTENT_MAX_H=$video_height
        ;;
    *) msg_error "Unknown quality profile: $quality_profile"; show_help; exit 1;;
esac

target_pad_width=$(( video_width >= video_height ? 1280 : 720 ))
target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))
ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"

# OPTIMIZATION: Separate seek options from trim options for performance.
fast_seek_opts=()
output_trim_opts=()
time_suffix=""
if [[ -n "$start_sec" && -n "$end_sec" ]]; then
    start_label=$(to_hms_label "$start_sec"); end_label=$(to_hms_label "$end_sec")
    time_suffix="_${start_label}_to_${end_label}"
    ffmpeg_duration=$(echo "$end_sec - $start_sec" | bc)
    # -ss before -i is a fast, but less accurate, seek.
    fast_seek_opts=(-ss "$start_sec")
    # -t is the duration of the output clip.
    output_trim_opts=(-t "$ffmpeg_duration")
fi
output_final_mp4="${output_filename_stem}_${quality_profile}${time_suffix}.mp4"

msg "Processing video to: $output_final_mp4"
if [[ -n "${ffmpeg_video_params_pass2[*]+x}" ]]; then
    "${ffmpeg_cmd_base[@]}" "${fast_seek_opts[@]}" -i "$input_file" "${output_trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params[@]}"
    "${ffmpeg_cmd_base[@]}" "${fast_seek_opts[@]}" -i "$input_file" "${output_trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params_pass2[@]}" "${ffmpeg_audio_params[@]}" -movflags +faststart "$output_final_mp4"
elif [[ "$quality_profile" == "10mb" && $(echo "$source_size_bytes < 10276044" | bc -l) -eq 1 && -z "${output_trim_opts[*]}" ]]; then
    cp "$input_file" "$output_final_mp4"
    msg_ok "File copied without re-encoding."
elif [[ "$quality_profile" == "10mb" && $(echo "$source_size_bytes < 10276044" | bc -l) -eq 1 && -n "${output_trim_opts[*]}" ]]; then
    msg_warn "Source is under 10MB but trimming is requested. Trimming via stream copy..."
    # Stream copy also benefits from fast seeking.
    "${ffmpeg_cmd_base[@]}" "${fast_seek_opts[@]}" -i "$input_file" "${output_trim_opts[@]}" -c:v copy -c:a copy -movflags +faststart "$output_final_mp4"
else
    # Standard single-pass CRF encoding.
    "${ffmpeg_cmd_base[@]}" "${fast_seek_opts[@]}" -i "$input_file" "${output_trim_opts[@]}" -vf "$ffmpeg_vf" "${ffmpeg_video_params[@]}" "${ffmpeg_audio_params[@]}" -movflags +faststart "$output_final_mp4"
fi

rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree

if [[ $? -eq 0 && -s "$output_final_mp4" ]]; then
    final_size_mb=$(printf "%.2f" "$(echo "$(stat -c%s "$output_final_mp4")/1024/1024" | bc -l)")
    msg_ok "Successfully processed video (Size: ${final_size_mb} MB)"
else
    msg_error "ffmpeg processing failed or output file is empty."
    exit 1
fi

end_processing_timer=$(date +%s.%N)

# ---------------[ FINAL SUMMARY & RENAME ]---------------

end_total_timer=$(date +%s.%N)
msg_ok "Script finished."

final_output_path="$output_final_mp4"
if [[ -n "$youtube_title" && "$auto_rename_flag" == true ]]; then
    normalized_title=$(normalize_filename "$youtube_title")
    proposed_new_name="${outdir}/${normalized_title}${time_suffix}.mp4"

    if [[ -n "$normalized_title" && "$proposed_new_name" != "$final_output_path" ]]; then
        msg "Auto-renaming file as requested by --rename flag..."
        mv -vf "$final_output_path" "$proposed_new_name"
        if [[ $? -eq 0 ]]; then
            msg_ok "File renamed successfully."
            final_output_path="$proposed_new_name"
        else
            msg_error "An error occurred during renaming."
        fi
    elif [[ "$proposed_new_name" == "$final_output_path" ]]; then
        msg_warn "Proposed new name is identical to the current name. No rename performed."
    else
        msg_error "Could not perform rename due to an empty normalized title."
    fi
fi

echo
echo "-------------------------------------"
echo "           Processing Timers"
echo "-------------------------------------"
if [[ -v start_download_timer ]]; then
    printf "Download Time:     %.2f seconds\n" "$(echo "$end_download_timer - $start_download_timer" | bc -l)"
fi
printf "Processing Time:   %.2f seconds\n" "$(echo "$end_processing_timer - $start_processing_timer" | bc -l)"
printf "Total Script Time: %.2f seconds\n" "$(echo "$end_total_timer - $start_total_timer" | bc -l)"
echo "-------------------------------------"
echo
echo "-------------------------------------"
echo "              Summary"
echo "-------------------------------------"
echo -e "Input Source:  ${COLOR_YELLOW}$source_input${COLOR_RESET}"
if [[ "$is_youtube_input" == true ]]; then
    echo -e "             YouTube Video (Length: $youtube_duration)"
else
    echo -e "             $(get_file_summary "$source_input")"
fi
echo
echo -e "Output File:   ${COLOR_GREEN}$final_output_path${COLOR_RESET}"
echo -e "             $(get_file_summary "$final_output_path")"
echo "-------------------------------------"
