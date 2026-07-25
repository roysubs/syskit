#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
set -e

# ---------------[ CONFIG ]---------------
# Default output directory is the current working directory
DEFAULT_OUTDIR="."
# Default quality profile
DEFAULT_QUALITY_PROFILE="sd" # Options: phone_small, phone_fast, sd, hd, source_mp4
DEFAULT_USE_TITLE=true

# ---------------[ HELPER FUNCTIONS ]---------------
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] <youtube_url_or_id> [start_time] [end_time]

Downloads a YouTube video and encodes it to MP4, with optional trimming and resizing.

OPTIONS:
  --out DIR               Set the output directory (default: current directory).
  --no-title              Use video ID for filename instead of title.
  --quality PROFILE       Set the quality profile. Available profiles:
                          - phone_small: For very small file size, 360p content, fast encode.
                          - phone_fast:  For small file size, 480p content, veryfast encode.
                          - sd:          Standard definition, 720p content, CRF 25 (default, good quality balance).
                          - hd:          High definition, 1080p content, CRF 23, higher quality.
                          - source_mp4:  Tries to get the best MP4 source from yt-dlp, minimal re-encoding if no trim.
  -h, --help              Show this help message.

TIME FORMAT:
  start_time and end_time can be in seconds (e.g., 125) or hh:mm:ss[.xx] (e.g., 00:02:05.5).
  Note: YouTube times have +/-2 sec offset; start/end operate on downloaded video and so are accurate on that basis. 

EXAMPLES:
  $(basename "$0") "YOUR_YOUTUBE_VIDEO_URL_OR_ID"
  $(basename "$0") --quality phone_fast --out ./my_videos "VIDEO_ID" 00:00:10 00:01:30
  $(basename "$0") --no-title "VIDEO_ID" 30 90
EOF
}

# Function to print messages in yellow
print_yellow() {
  printf "\033[1;33m%s\033[0m\n" "$1"
}

# ---------------[ ARGS ]-----------------
outdir="$DEFAULT_OUTDIR"
quality_profile="$DEFAULT_QUALITY_PROFILE"
use_title="$DEFAULT_USE_TITLE"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out) shift; outdir="$1";;
    --no-title) use_title=false;;
    --quality) shift; quality_profile="$1";;
    -h|--help) show_help; exit 0;;
    -*) echo "Error: Unknown option: $1" >&2; show_help; exit 1;;
    *) break;; # First non-option is URL
  esac
  shift
done

url="$1"; start_input="$2"; end_input="$3"

if [[ -z "$url" ]]; then
  echo "Error: YouTube URL or Video ID is required." >&2
  show_help
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$outdir"

# ---------------[ TIME CONVERSION ]---------------
convert_to_seconds() {
  local t=$1
  if [[ -z "$t" ]]; then
    echo ""
    return
  fi
  if [[ "$t" =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.[0-9]+)?$ ]]; then
    local h=${BASH_REMATCH[1]}
    local m=${BASH_REMATCH[2]}
    local s=${BASH_REMATCH[3]}
    local ms=${BASH_REMATCH[4]}
    echo "$((10#$h * 3600 + 10#$m * 60 + 10#$s))${ms:-}"
  elif [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$t"
  else
    echo "Error: Invalid time format '$t'. Use seconds or hh:mm:ss[.xx]." >&2
    exit 1
  fi
}

start_sec=$(convert_to_seconds "$start_input")
end_sec=$(convert_to_seconds "$end_input")

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
  if (( $(echo "$end_sec <= $start_sec" | bc -l) )); then
    echo "Error: End time must be greater than start time." >&2
    exit 1
  fi
fi

to_hms_label() {
  if [[ -z "$1" ]]; then echo ""; return; fi
  local s_total=${1%%.*}
  local h=$((s_total / 3600))
  local m=$(((s_total % 3600) / 60))
  local s=$((s_total % 60))
  printf "%02d-%02d-%02d" "$h" "$m" "$s"
}

# ----------[ INSTALL YT-DLP FROM GITHUB ]----------
# Repo versions will usually fail to work on YouTube
# Always need to have the latest yt-dlp form GitHub

# --- Configuration ---
GITHUB_REPO="yt-dlp/yt-dlp"
INSTALL_DIR="$HOME/.local/bin"
EXE_NAME="yt-dlp"
TARGET_EXE_PATH="$INSTALL_DIR/$EXE_NAME"

# --- Helper Functions ---
# Color codes
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'

# Print messages
msg() {
    echo -e "${COLOR_BLUE}[*]${COLOR_RESET} $1"
}
msg_ok() {
    echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $1"
}
msg_warn() {
    echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $1"
}
msg_error() {
    echo -e "${COLOR_RED}[-]${COLOR_RESET} $1" >&2
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a directory is in PATH
is_dir_in_path() {
    local dir_to_check="$1"
    if [[ ":$PATH:" == *":$dir_to_check:"* ]]; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Check for essential dependencies
check_dependencies() {
    msg "Checking for essential dependencies..."
    local missing_deps=0
    local deps=("curl" "grep" "sed" "mktemp")

    if command_exists dpkg && command_exists apt-get; then
        msg_ok "dpkg and apt-get found (for managing apt packages)."
    else
        msg_warn "dpkg or apt-get not found. Cannot manage apt-installed yt-dlp."
        # This is not fatal if yt-dlp is not apt-installed or not installed at all.
    fi

    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            msg_error "Missing dependency: $dep. Please install it."
            missing_deps=1
        fi
    done

    if [ "$missing_deps" -eq 1 ]; then
        msg_error "Please install missing dependencies and try again."
        exit 1
    fi
    msg_ok "All essential dependencies found."
}

# Get currently installed yt-dlp path and version
get_current_ytdlp_info() {
    CURRENT_YTDLP_PATH=""
    CURRENT_YTDLP_VERSION=""
    IS_APT_MANAGED=false

    if command_exists "$EXE_NAME"; then
        CURRENT_YTDLP_PATH=$(command -v "$EXE_NAME")
        # Try to get version
        if [ -n "$CURRENT_YTDLP_PATH" ] && [ -x "$CURRENT_YTDLP_PATH" ]; then
            CURRENT_YTDLP_VERSION=$("$CURRENT_YTDLP_PATH" --version 2>/dev/null | head -n1) || CURRENT_YTDLP_VERSION="unknown"
        else
            CURRENT_YTDLP_VERSION="unknown" # Path found but not executable or version command failed
        fi

        # Check if managed by dpkg (apt)
        if command_exists dpkg && dpkg -S "$CURRENT_YTDLP_PATH" >/dev/null 2>&1; then
            IS_APT_MANAGED=true
            local apt_version
            apt_version=$(dpkg-query -W -f='${Version}' yt-dlp 2>/dev/null || echo "apt-version-unknown")
            msg_warn "Found yt-dlp at $CURRENT_YTDLP_PATH (version $CURRENT_YTDLP_VERSION, reported by apt as $apt_version)."
            msg_warn "This appears to be managed by apt."
        elif [ -n "$CURRENT_YTDLP_PATH" ]; then
            msg_ok "Found manually installed yt-dlp at $CURRENT_YTDLP_PATH (version $CURRENT_YTDLP_VERSION)."
        fi
    else
        msg "yt-dlp not found in PATH."
    fi
}

# Uninstall apt version of yt-dlp
uninstall_apt_ytdlp() {
    if ! command_exists apt-get || ! command_exists sudo; then
        msg_error "apt-get or sudo command not found. Cannot uninstall apt version."
        return 1
    fi
    msg_warn "The apt version of yt-dlp can cause issues and is often outdated."
    read -r -p "Do you want to uninstall the apt version of yt-dlp? This requires sudo. (y/N): " confirmation
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        msg "Uninstalling apt version of yt-dlp..."
        if sudo apt-get remove -y yt-dlp; then
            msg_ok "Successfully removed yt-dlp package."
            read -r -p "Do you want to run 'sudo apt autoremove' to remove unused dependencies? (y/N): " autoremove_confirm
            if [[ "$autoremove_confirm" =~ ^[Yy]$ ]]; then
                sudo apt-get autoremove -y
                msg_ok "Successfully ran apt autoremove."
            fi
            CURRENT_YTDLP_PATH="" # Reset, as it's gone
            CURRENT_YTDLP_VERSION=""
            IS_APT_MANAGED=false # No longer apt managed
            return 0
        else
            msg_error "Failed to uninstall apt version of yt-dlp."
            return 1
        fi
    else
        msg "Skipping uninstallation of apt version. The script will not proceed with GitHub version."
        return 1
    fi
}

# Get latest version from GitHub
get_latest_github_version() {
    msg "Fetching latest yt-dlp version from GitHub..."

    # Use sed to directly parse curl output and extract the tag_name value.
    # -n: suppress automatic printing of pattern space
    # -E: use extended regular expressions
    # s/.../.../p: substitute and print if successful
    # ^[[:space:]]* : matches any leading spaces on the line
    # "tag_name":[[:space:]]* : matches "tag_name": and any following spaces
    # "\([^"]+\)" : captures the version string (one or more characters that are not a quote)
    # .* : matches the rest of the line
    # \1 : the captured version string
    LATEST_GITHUB_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
                            sed -nE 's/^[[:space:]]*"tag_name":[[:space:]]*"([^"]+)".*/\1/p')

    if [ -z "$LATEST_GITHUB_VERSION" ]; then
        msg_error "Failed to fetch or parse the latest version from GitHub. The extracted version string was empty."
        msg_error "Please check your internet connection and ensure GitHub API is accessible."
        exit 1
    fi

    # Sanity check the extracted version string
    if [[ "$LATEST_GITHUB_VERSION" =~ [[:space:]\'\":\{\}] ]]; then # Checks for spaces, quotes, colons, braces
        msg_error "Fetched version string appears malformed: '$LATEST_GITHUB_VERSION'"
        msg_error "This might indicate an issue with the script's parsing logic or a change in GitHub API response format."
        msg_error "Ensure the get_latest_github_version function in the script is up-to-date with the latest provided version."
        exit 1
    fi

    msg_ok "Latest GitHub version: $LATEST_GITHUB_VERSION"
}

# Download and install/update yt-dlp
download_and_install_ytdlp() {
    local version_tag="$1"
    # Correctly define the asset name on GitHub for Linux
    local github_asset_name_on_server="yt-dlp_linux"

    msg "Preparing to install yt-dlp version $version_tag to $TARGET_EXE_PATH..."
    # $TARGET_EXE_PATH is "$INSTALL_DIR/$EXE_NAME" which resolves to "$HOME/.local/bin/yt-dlp"

    if ! mkdir -p "$INSTALL_DIR"; then
        msg_error "Failed to create installation directory: $INSTALL_DIR"
        msg_error "Please check permissions or create it manually."
        exit 1
    fi

    local download_url="https://github.com/$GITHUB_REPO/releases/download/$version_tag/$github_asset_name_on_server"
    local temp_file
    temp_file=$(mktemp)

    if [ -z "$temp_file" ]; then
        msg_error "Failed to create a temporary file."
        exit 1
    fi

    msg "Downloading $download_url ..." # This will now show the correct asset name
    if curl -SL --progress-bar -o "$temp_file" "$download_url"; then
        msg_ok "Download complete."
        if chmod +x "$temp_file"; then
            msg_ok "Made temporary file executable."

            # Check if target exists and if it's a symlink or a file before overwriting
            if [ -e "$TARGET_EXE_PATH" ] && [ ! -L "$TARGET_EXE_PATH" ]; then
                 msg_warn "An existing file at $TARGET_EXE_PATH will be overwritten."
            elif [ -L "$TARGET_EXE_PATH" ]; then
                 msg_warn "An existing symlink at $TARGET_EXE_PATH will be overwritten."
            fi

            # Move the downloaded file (e.g., yt-dlp_linux) to the target path (e.g., ~/.local/bin/yt-dlp)
            # This also handles the renaming from "yt-dlp_linux" to "yt-dlp"
            if mv "$temp_file" "$TARGET_EXE_PATH"; then
                msg_ok "yt-dlp version $version_tag (downloaded as $github_asset_name_on_server) installed successfully as $TARGET_EXE_PATH"

                # Verify installation by checking the version of the installed file
                local installed_version
                installed_version=$("$TARGET_EXE_PATH" --version 2>/dev/null | head -n1)
                if [ "$installed_version" == "$version_tag" ]; then
                    msg_ok "Verification successful: Installed version is $installed_version."
                else
                    msg_warn "Verification issue: Installed version reports '$installed_version', expected '$version_tag'."
                    msg_warn "This could be a temporary issue or a problem with the downloaded file."
                fi

                # Check if INSTALL_DIR is in PATH
                if ! is_dir_in_path "$INSTALL_DIR"; then
                    msg_warn "Directory $INSTALL_DIR is not in your PATH."
                    msg_warn "You may need to add it to your shell's configuration file (e.g., ~/.bashrc, ~/.zshrc):"
                    msg_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                    msg_warn "Then, open a new terminal or source the file (e.g., 'source ~/.bashrc')."
                else
                    msg_ok "$INSTALL_DIR is in your PATH."
                fi
            else
                msg_error "Failed to move downloaded file to $TARGET_EXE_PATH."
                msg_error "Please check permissions for $INSTALL_DIR."
                rm -f "$temp_file" # Clean up temp file on error
                exit 1
            fi
        else
            msg_error "Failed to make downloaded file executable."
            rm -f "$temp_file" # Clean up temp file
            exit 1
        fi
    else
        msg_error "Download failed from $download_url."
        rm -f "$temp_file" # Clean up temp file
        exit 1
    fi
}

# --- Main Logic ---
main_yt_dlp() {
    check_dependencies
    get_current_ytdlp_info

    if [ "$IS_APT_MANAGED" = true ]; then
        if ! uninstall_apt_ytdlp; then
            msg "Exiting as apt version was not uninstalled."
            exit 0 # User chose not to uninstall, or uninstallation failed.
        fi
        # Re-check info after potential uninstall
        get_current_ytdlp_info
    fi

    get_latest_github_version

    if [ -z "$CURRENT_YTDLP_VERSION" ] || [ "$CURRENT_YTDLP_VERSION" == "unknown" ]; then
        msg "yt-dlp is not installed or current version is unknown."
        download_and_install_ytdlp "$LATEST_GITHUB_VERSION"
    elif [ "$CURRENT_YTDLP_VERSION" == "$LATEST_GITHUB_VERSION" ]; then
        msg_ok "You already have the latest version of yt-dlp ($CURRENT_YTDLP_VERSION) at $CURRENT_YTDLP_PATH."
        # Ensure it's in the target location if it matches version but not path
        if [ "$CURRENT_YTDLP_PATH" != "$TARGET_EXE_PATH" ]; then
             msg_warn "However, it's not in the standard user path ($TARGET_EXE_PATH)."
             msg_warn "This script installs to $TARGET_EXE_PATH."
             # Optionally, offer to move/reinstall it here. For now, just inform.
        fi
    else
        msg "Current version ($CURRENT_YTDLP_VERSION) is older than the latest GitHub version ($LATEST_GITHUB_VERSION)."
        download_and_install_ytdlp "$LATEST_GITHUB_VERSION"
    fi

    msg_ok "Script finished."
}

# Run main function
main_yt_dlp


# ---------------[ QUALITY PROFILES ]---------------
case "$quality_profile" in
  phone_small)
    YTDLP_FORMAT_SELECTOR="bestvideo[height<=360]+bestaudio/best[height<=360]"
    FFMPEG_CONTENT_MAX_H=360
    FFMPEG_CRF=32
    FFMPEG_PRESET="fast"
    FFMPEG_AUDIO_KBPS="64k"
    ;;
  phone_fast)
    YTDLP_FORMAT_SELECTOR="bestvideo[height<=480]+bestaudio/best[height<=480]"
    FFMPEG_CONTENT_MAX_H=480
    FFMPEG_CRF=25
    FFMPEG_PRESET="veryfast"
    FFMPEG_AUDIO_KBPS="96k"
    ;;
  sd) # Default profile, adjusted CRF for better quality
    YTDLP_FORMAT_SELECTOR="bestvideo[height<=720]+bestaudio/best[height<=720]"
    FFMPEG_CONTENT_MAX_H=720
    FFMPEG_CRF=19 # Changed from 27 to 25 for higher quality/larger file
    FFMPEG_PRESET="fast"
    FFMPEG_AUDIO_KBPS="128k"
    ;;
  hd)
    YTDLP_FORMAT_SELECTOR="bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    FFMPEG_CONTENT_MAX_H=1080
    FFMPEG_CRF=13
    FFMPEG_PRESET="medium"
    FFMPEG_AUDIO_KBPS="160k"
    ;;
  source_mp4)
    YTDLP_FORMAT_SELECTOR="bestvideo[height<=2160][ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec=aac]/bestvideo[height<=2160][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=2160]+bestaudio/best"
    FFMPEG_CONTENT_MAX_H=1080
    FFMPEG_CRF=22
    FFMPEG_PRESET="medium"
    FFMPEG_AUDIO_KBPS="192k"
    ;;
  *)
    echo "Error: Unknown quality profile: $quality_profile" >&2
    show_help
    exit 1
    ;;
esac

# ---------------[ DEPENDENCY CHECK ]---------------
echo "[*] Checking dependencies..."
for cmd in yt-dlp ffmpeg ffprobe bc date; do # Added 'date' for H:M:S formatting
  command -v "$cmd" >/dev/null || { echo "Error: Missing dependency: $cmd. Please install it." >&2; exit 1; }
done
echo "[*] All dependencies found."

# ---------------[ FILENAME SETUP ]---------------
if $use_title; then
  echo "[*] Fetching video title..."
  raw_title=$(yt-dlp --get-title "$url")
  if [[ -z "$raw_title" ]]; then
    echo "Error: Could not fetch video title for URL: $url" >&2
    video_id_for_filename="${url##*v=}"
    video_id_for_filename="${video_id_for_filename##*/}"
    video_id_for_filename="${video_id_for_filename%%&*}"
    title_sanitized="${video_id_for_filename}_NO_TITLE"
    echo "[!] Warning: Using Video ID for filename as title could not be fetched."
  else
    title_sanitized=$(echo "$raw_title" | sed 's/[\\\/:\*\?"<>\|\x00-\x1F\x7F]//g' | sed 's/ \+$//g' | sed 's/^ \+//g')
    title_sanitized=$(echo "$title_sanitized" | tr -s '[:space:]_.' '_')
    if [[ -z "$title_sanitized" ]]; then
        video_id_for_filename="${url##*v=}"
        video_id_for_filename="${video_id_for_filename##*/}"
        video_id_for_filename="${video_id_for_filename%%&*}"
        title_sanitized="${video_id_for_filename}_EMPTY_TITLE"
    fi
  fi
  base_filename_stem="${outdir}/${title_sanitized}_${quality_profile}"
else
  video_id="${url##*v=}"
  video_id="${video_id##*/}"
  video_id="${video_id%%&*}"
  base_filename_stem="${outdir}/${video_id}_${quality_profile}"
fi

downloaded_source_file="${base_filename_stem}_source.mp4"

# ---------------[ DOWNLOAD VIDEO ]---------------
yt_dlp_start_time=$SECONDS
if [[ ! -f "$downloaded_source_file" ]]; then
  echo "[*] Downloading video to: $downloaded_source_file"
  if yt-dlp \
    -f "$YTDLP_FORMAT_SELECTOR" \
    --merge-output-format mp4 \
    -o "$downloaded_source_file" \
    "$url"; then
    echo "[*] Download complete: $downloaded_source_file"
  else
    echo "Error: yt-dlp failed to download the video." >&2
    if [[ -f "$downloaded_source_file" && ! -s "$downloaded_source_file" ]]; then
        rm "$downloaded_source_file"
    fi
    exit 1
  fi
else
  echo "[*] Skipping download: Found existing source file $downloaded_source_file"
fi
yt_dlp_end_time=$SECONDS
yt_dlp_duration=$((yt_dlp_end_time - yt_dlp_start_time))

if [[ ! -s "$downloaded_source_file" ]]; then
    echo "Error: Downloaded file $downloaded_source_file is empty or does not exist." >&2
    exit 1
fi

# Metrics for yt-dlp
source_video_duration_sec_float=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$downloaded_source_file")
source_video_duration_sec=${source_video_duration_sec_float%.*} # Integer part

print_yellow "[METRIC] YT-DLP download process took ${yt_dlp_duration}s."
if [[ -n "$source_video_duration_sec" && "$source_video_duration_sec" -ne 0 ]]; then
  source_video_duration_hms=$(date -u -d "@${source_video_duration_sec}" +'%H:%M:%S')
  print_yellow "[METRIC] Downloaded video duration: ${source_video_duration_hms} (${source_video_duration_sec_float}s)."
  yt_dlp_secs_per_min_vid=$(echo "scale=2; ($yt_dlp_duration * 60) / $source_video_duration_sec" | bc)
  print_yellow "[METRIC] YT-DLP download speed: ${yt_dlp_secs_per_min_vid}s of processing per minute of video."
else
  print_yellow "[METRIC] Could not determine downloaded video duration for speed calculation."
fi

# ---------------[ VIDEO PROCESSING (FFMPEG) ]---------------
echo "[*] Getting video dimensions from: $downloaded_source_file"
video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$downloaded_source_file")
video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$downloaded_source_file")

if [[ -z "$video_width" || -z "$video_height" ]]; then
    echo "Error: Could not get video dimensions from $downloaded_source_file." >&2
    exit 1
fi
echo "[*] Source dimensions: ${video_width}x${video_height}"

target_pad_width=$(( video_width >= video_height ? 1280 : 720 ))
target_pad_height=$(( video_width >= video_height ? 720 : 1280 ))

echo "[*] Target canvas for padding: ${target_pad_width}x${target_pad_height}"
echo "[*] Max content height for encoding: ${FFMPEG_CONTENT_MAX_H}p"

ffmpeg_vf="scale=-2:'min(ih,${FFMPEG_CONTENT_MAX_H})',scale=w='min(iw,${target_pad_width})':h='min(ih,${target_pad_height})':force_original_aspect_ratio=decrease,pad=w=${target_pad_width}:h=${target_pad_height}:x='(ow-iw)/2':y='(oh-ih)/2'"

output_final_mp4=""
ffmpeg_cmd_base=(ffmpeg -hide_banner -loglevel error -y)

ffmpeg_start_time=$SECONDS
output_segment_duration_for_metric_sec_float=""

if [[ -n "$start_sec" && -n "$end_sec" ]]; then
  start_label=$(to_hms_label "$start_sec")
  end_label=$(to_hms_label "$end_sec")
  output_final_mp4="${base_filename_stem}_${start_label}_to_${end_label}.mp4"
  # Duration for ffmpeg -to option needs to be relative to -ss
  ffmpeg_to_duration=$(echo "$end_sec - $start_sec" | bc)
  output_segment_duration_for_metric_sec_float="$ffmpeg_to_duration"


  echo "[*] Trimming video from $start_input ($start_sec s) to $end_input ($end_sec s), duration: $ffmpeg_to_duration s"
  echo "[*] Output clip will be: $output_final_mp4"

  "${ffmpeg_cmd_base[@]}" \
    -ss "$start_sec" -i "$downloaded_source_file" \
    -to "$ffmpeg_to_duration" \
    -vf "$ffmpeg_vf" \
    -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" \
    -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" \
    "$output_final_mp4"
else
  output_final_mp4="${base_filename_stem}_full.mp4"
  echo "[*] No trim requested. Re-encoding full video with resizing/padding."
  echo "[*] Output video will be: $output_final_mp4"
  output_segment_duration_for_metric_sec_float="$source_video_duration_sec_float"

  "${ffmpeg_cmd_base[@]}" \
    -i "$downloaded_source_file" \
    -vf "$ffmpeg_vf" \
    -c:v libx264 -crf "$FFMPEG_CRF" -preset "$FFMPEG_PRESET" \
    -c:a aac -b:a "$FFMPEG_AUDIO_KBPS" \
    "$output_final_mp4"
fi
ffmpeg_end_time=$SECONDS
ffmpeg_duration=$((ffmpeg_end_time - ffmpeg_start_time))

# Metrics for ffmpeg
print_yellow "[METRIC] FFMPEG processing took ${ffmpeg_duration}s."
if [[ -n "$output_segment_duration_for_metric_sec_float" ]]; then
    output_segment_duration_for_metric_sec=${output_segment_duration_for_metric_sec_float%.*}
    if [[ "$output_segment_duration_for_metric_sec" -ne 0 ]]; then
        ffmpeg_secs_per_min_vid=$(echo "scale=2; ($ffmpeg_duration * 60) / $output_segment_duration_for_metric_sec" | bc)
        processed_duration_hms=$(date -u -d "@${output_segment_duration_for_metric_sec}" +'%H:%M:%S')
        print_yellow "[METRIC] FFMPEG processed segment duration: ${processed_duration_hms} (${output_segment_duration_for_metric_sec_float}s)."
        print_yellow "[METRIC] FFMPEG encoding speed: ${ffmpeg_secs_per_min_vid}s of processing per minute of video."
    else
        print_yellow "[METRIC] Processed segment duration is zero, cannot calculate FFMPEG speed per minute."
    fi
else
    print_yellow "[METRIC] Could not determine processed segment duration for FFMPEG speed calculation."
fi


if [[ $? -eq 0 && -s "$output_final_mp4" ]]; then
  echo "[*] Successfully processed video saved as: $output_final_mp4"
else
  echo "Error: ffmpeg processing failed or output file is empty for $output_final_mp4" >&2
  exit 1
fi

echo "[*] Script finished."

