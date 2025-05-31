#!/bin/bash
# Author: Roy Wiseman 2025-05

# === Media File Cleaner ===
# Description: Cleans and renames media files by removing "junk" patterns
#              from filenames and standardizing the naming format.
#              Verifies and corrects file extensions using ffprobe if available.
#
# Author: Based on user script, with improvements.
# Version: 2.4

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
BLUE='\e[0;34m'
BOLD='\e[1m'
NC='\e[0m'

echo "Media File Cleaner - Auto-rename media files"

# --- Configuration ---
# List of supported media file extensions (lowercase)
MEDIA_EXTENSIONS=("mkv" "avi" "mp3" "mp4" "cbr" "cbz" "mov" "flv" "wmv" "webm" "mpg" "mpeg" "jpg" "png" "gif")

# Fast junk pattern list to strip from filenames (case-insensitive)
# Escaped hyphens in specific terms (e.g., HD-CAM) and split WEB-?DL for better sed compatibility.
DEFAULT_JUNK_PATTERN='(HDRip|HD\-CAM|HD\ CAM|BluRay|Blu\-Ray|WEBRip|WEB\-DL|WEBDL|DVDRip|HDTV|x264|h264|x265|h265|XviD|AAC|AC3|DTS|TGx|YIFY|RARBG|PROPER|REPACK|EXTENDED|UNRATED|REMUX|IMAX|NF|AMZN|DSNP|HMAX|GalaxyTV|720p|1080p|2160p|4K|HEVC|VP9|AV1|DD5\.?1|DDP5\.?1|[xXhH]265\-ELiTE|[xXhH]265)'

# Script path and junk database
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
JUNK_DB_FILE="$HOME/${SCRIPT_BASE}.db"

# --- Global Variables ---
DRY_RUN=1 # Default to dry run
COMMIT_MODE=0 # Explicit commit needed
VERBOSE=0
INPUT_PATH=""
USER_JUNK_TERMS=()

# --- Helper Functions ---
print_usage() {
  echo -e "\nUsage: $(basename "$0") [options] <file-or-dir> [custom_junk_term1 ...]"
  echo -e "\nDescription:"
  echo "  Cleans media filenames by removing common junk tags and standardizing format."
  echo "  Defaults to a dry run. Use --commit to apply changes."
  echo "  Custom junk terms provided are added to '$JUNK_DB_FILE' for future runs."
  echo -e "\nOptions:"
  echo "  -c, --commit      Actually rename/move files (default is dry run)."
  echo "  -v, --verbose     Enable verbose output."
  echo "  -h, --help        Show this help message."
  echo "  --no-dry-run      Deprecated, use --commit instead."
  echo -e "\nExamples:"
  echo "  $(basename "$0") \"My Movie.1080p.x264-JUNK.mkv\"  (This will be a dry run)"
  echo "  $(basename "$0") --commit \"/path/to/media_folder/\" SomeGroup AnotherTag"
  echo "  $(basename "$0") -v \"./My Show S01E01 WEBRip.mp4\""
}

check_command_exists() {
  local cmd_name="$1"
  local purpose="$2"
  if ! command -v "$cmd_name" &> /dev/null; then
    if [[ "$VERBOSE" -eq 1 ]]; then
      echo "[INFO] Command '$cmd_name' not found. $purpose will be unavailable."
    fi
    return 1
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
      echo "[INFO] Command '$cmd_name' found."
  fi
  return 0
}

# --- Argument Parsing ---
TEMP_ARGS=$(getopt -o 'chv' --long 'commit,help,verbose,no-dry-run' -n "$(basename "$0")" -- "$@")
if [[ $? -ne 0 ]]; then
  print_usage
  exit 1
fi
eval set -- "$TEMP_ARGS"
unset TEMP_ARGS

while true; do
  case "$1" in
    -c | --commit | --no-dry-run)
      COMMIT_MODE=1
      DRY_RUN=0
      shift
      ;;
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -h | --help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Internal error parsing options!" >&2
      exit 1
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Error: No input file or directory specified."
  print_usage
  exit 1
fi
INPUT_PATH="$1"
shift

if [[ $# -gt 0 ]]; then
  USER_JUNK_TERMS=("$@")
fi

# --- Initial Checks for Dependencies ---
FFPROBE_EXISTS=0
JQ_EXISTS=0
check_command_exists "ffprobe" "Media metadata extraction and extension correction" && FFPROBE_EXISTS=1
check_command_exists "jq" "Parsing ffprobe JSON output for extension correction" && JQ_EXISTS=1


# --- Main Logic ---
if [[ ${#USER_JUNK_TERMS[@]} -gt 0 ]]; then
  TEMP_JUNK_DB="${JUNK_DB_FILE}.tmp.$$"
  touch "$JUNK_DB_FILE"
  cp "$JUNK_DB_FILE" "$TEMP_JUNK_DB"
  for term in "${USER_JUNK_TERMS[@]}"; do
    if ! grep -qxiF "$term" "$TEMP_JUNK_DB"; then
      echo "$term" >> "$TEMP_JUNK_DB"
      echo "[INFO] Appended '$term' to junk DB: $JUNK_DB_FILE"
    elif [[ "$VERBOSE" -eq 1 ]]; then
      echo "[INFO] Junk term '$term' already in DB. Skipping."
    fi
  done
  sort -u -f "$TEMP_JUNK_DB" -o "$JUNK_DB_FILE"
  rm "$TEMP_JUNK_DB"
fi

declare -a ALL_JUNK_TERMS_FROM_DB
if [[ -f "$JUNK_DB_FILE" ]]; then
  mapfile -t ALL_JUNK_TERMS_FROM_DB < <(grep -vE '^\s*(#|$)' "$JUNK_DB_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

is_media_file() {
  local filename
  filename=$(basename "$1")
  local ext="${filename##*.}"
  ext="${ext,,}"
  for media_ext in "${MEDIA_EXTENSIONS[@]}"; do
    if [[ "$ext" == "$media_ext" ]]; then
      return 0
    fi
  done
  return 1
}

get_correct_extension_from_format_name() {
    local format_name="$1"
    local original_ext="$2"

    if [[ -z "$format_name" ]]; then
        echo "$original_ext"
        return
    fi

    if [[ "$format_name" == *"matroska"* ]]; then echo "mkv"; return; fi
    if [[ "$format_name" == *"mp4"* ]]; then echo "mp4"; return; fi
    if [[ "$format_name" == *"webm"* ]]; then echo "webm"; return; fi
    if [[ "$format_name" == "mp3" ]]; then echo "mp3"; return; fi
    if [[ "$format_name" == "flv" ]]; then echo "flv"; return; fi
    if [[ "$format_name" == "avi" ]]; then echo "avi"; return; fi
    if [[ "$format_name" == "mpeg" ]]; then echo "mpg"; return; fi
    if [[ "$format_name" == "gif" ]]; then echo "gif"; return; fi
    if [[ "$format_name" == *"png"* ]]; then echo "png"; return; fi
    if [[ "$format_name" == *"jpeg"* || "$format_name" == *"mjpeg"* ]]; then echo "jpg"; return; fi

    if [[ ! "$format_name" == *,* ]]; then
        for known_ext in "${MEDIA_EXTENSIONS[@]}"; do
            if [[ "$format_name" == "$known_ext" ]]; then
                echo "$known_ext"
                return
            fi
        done
    fi

    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "[VERBOSE]   Could not determine a specific new extension for ffprobe format_name '$format_name'. Using original '$original_ext'."
    fi
    echo "$original_ext"
}


clean_name() {
  local current_filepath="$1"
  local current_dir
  current_dir=$(dirname "$current_filepath")
  local current_filename
  current_filename=$(basename "$current_filepath")

  local base_name="${current_filename%.*}"
  local ext="${current_filename##*.}"
  local original_lower_ext="${ext,,}"

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[VERBOSE] Processing: $current_filepath"
    echo "[VERBOSE]   Base name: $base_name, Original Extension: $ext"
  fi

  local corrected_ext="$ext"
  if [[ "$FFPROBE_EXISTS" -eq 1 && "$JQ_EXISTS" -eq 1 ]] && is_media_file "$current_filepath"; then
    if [[ "$VERBOSE" -eq 1 ]]; then echo "[VERBOSE]   Checking actual container format with ffprobe..."; fi
    local ffprobe_output
    ffprobe_output=$(ffprobe -v quiet -show_entries format=format_name -of json "$current_filepath" 2>/dev/null)

    if [[ -n "$ffprobe_output" ]]; then
      local format_name
      format_name=$(echo "$ffprobe_output" | jq -r '.format.format_name // empty')

      if [[ -n "$format_name" ]]; then
        if [[ "$VERBOSE" -eq 1 ]]; then echo "[VERBOSE]   ffprobe detected format_name: '$format_name'"; fi
        local probed_ext
        probed_ext=$(get_correct_extension_from_format_name "$format_name" "$original_lower_ext")

        if [[ "$probed_ext" != "$original_lower_ext" ]]; then
          echo "[INFO] Extension mismatch for '$current_filename'. Original: '.$original_lower_ext', ffprobe suggests: '.$probed_ext'. Correcting."
          corrected_ext="$probed_ext"
        elif [[ "$VERBOSE" -eq 1 ]]; then
          echo "[VERBOSE]   File extension '.$original_lower_ext' matches ffprobe format."
        fi
      elif [[ "$VERBOSE" -eq 1 ]]; then
        echo "[VERBOSE]   ffprobe could not determine format_name."
      fi
    elif [[ "$VERBOSE" -eq 1 ]]; then
      echo "[VERBOSE]   ffprobe failed or produced no output for '$current_filename'."
    fi
  elif [[ "$VERBOSE" -eq 1 && (! "$FFPROBE_EXISTS" -eq 1 || ! "$JQ_EXISTS" -eq 1) ]]; then
    echo "[VERBOSE]   ffprobe and/or jq not available. Skipping extension correction."
  fi
  ext="$corrected_ext"


  local cleaned_name="${base_name//./ }"
  cleaned_name="${cleaned_name//_/ }"
  cleaned_name="${cleaned_name//-/ }" # Initial replacement of all hyphens with spaces

  # Apply default junk pattern removal
  if [[ -n "$cleaned_name" ]]; then
    cleaned_name=$(echo "$cleaned_name" | sed -E "s/${DEFAULT_JUNK_PATTERN}//gi")
  fi

  # Apply junk terms from DB
  for junk_item in "${ALL_JUNK_TERMS_FROM_DB[@]}"; do
    if [[ -n "$junk_item" && -n "$cleaned_name" ]]; then
      local escaped_junk_item
      escaped_junk_item=$(printf '%s\n' "$junk_item" | sed 's/[][\\/.^$*?+|(){}]/\\&/g')
      cleaned_name=$(echo "$cleaned_name" | sed -E "s/\b${escaped_junk_item}\b//gi")
    fi
  done

  local year=""
  if [[ "$cleaned_name" =~ ([(\[]?\b(19[0-9]{2}|20[0-9]{2})\b[)\]]?) ]]; then
    year="${BASH_REMATCH[2]}"
    cleaned_name=$(echo "$cleaned_name" | sed -E "s/[(\[]?\b${year}\b[)\]]?(\s|$)/ /g")
  fi
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/\b([Ss])([0-9]{1,2})([EeXx])([0-9]{1,3})\b/S\2E\4/g')
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/\b[Ss]eason\s+([0-9]+)\s+[Ee]pisode\s+([0-9]+)\b/S\1E\2/gI')
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/\bS([0-9])E/S0\1E/g; s/ES([0-9])\b/ES0\1/g')
  # cleaned_name=$(echo "$cleaned_name" | sed -E 's/E([0-9])(?![0-9])/E0\1/g')   # ?! not understood by most GNU sed
  # 1. Pad E<digit> when it is followed by a non-digit character.
  #    ([^0-9]) captures the non-digit character, which is then put back using \2.
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/E([0-9])([^0-9])/E0\1\2/g')
  # 2. Pad E<digit> when it is at the very end of the string ($).
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/E([0-9])$/E0\1/g')
  cleaned_name=$(echo "$cleaned_name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print $0}')

  if [[ -n "$year" ]]; then
    cleaned_name="$cleaned_name ($year)"
  fi
  cleaned_name=$(echo "$cleaned_name" | sed -E 's/\s+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')

  if [[ -z "$cleaned_name" ]]; then
    echo "[WARNING] Cleaned name for '$current_filename' resulted in an empty string. Using original base name after basic space replacement."
    cleaned_name="${base_name//./ }" # Re-process original base_name if everything got stripped
    cleaned_name="${cleaned_name//_/ }"
    cleaned_name="${cleaned_name//-/ }"
    cleaned_name=$(echo "$cleaned_name" | sed -E 's/\s+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    if [[ -z "$cleaned_name" ]]; then
        cleaned_name="Untitled"
    fi
  fi

  local final_filename="${cleaned_name}.${ext}"

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[VERBOSE]   Original filename: $current_filename"
    echo "[VERBOSE]   Proposed new filename: $final_filename"
  fi

  if [[ "$final_filename" == "$current_filename" ]]; then
    echo "[INFO] No rename needed for: $current_filename"
    return
  fi

  local final_filepath="${current_dir}/${final_filename}"

  if [[ -e "$final_filepath" ]]; then
    local counter=1
    local conflict_base_name="${cleaned_name}"
    while [[ -e "${current_dir}/${conflict_base_name} (${counter}).${ext}" ]]; do
      ((counter++))
    done
    final_filename="${conflict_base_name} (${counter}).${ext}"
    final_filepath="${current_dir}/${final_filename}"
    echo "[WARNING] Target '$current_dir/$cleaned_name.$ext' exists. Using '$final_filename' instead."
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would rename '$current_filepath' to '$final_filepath'"
  else
    echo "Renaming '$current_filepath' to '$final_filepath'"
    mv -v -- "$current_filepath" "$final_filepath"
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Failed to rename '$current_filepath'."
    fi
  fi
}

process_folder() {
  local folder_to_process="$1"
  if [[ ! -d "$folder_to_process" ]]; then
    echo "Error: '$folder_to_process' is not a directory." >&2
    return 1
  fi

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[VERBOSE] Processing folder: $folder_to_process"
  fi

  find "$folder_to_process" -type f -print0 | while IFS= read -r -d $'\0' file_item; do
    if is_media_file "$file_item"; then
      clean_name "$file_item"
    elif [[ "$VERBOSE" -eq 1 ]]; then
      echo "[VERBOSE] Skipping non-media file: $file_item"
    fi
  done

  if [[ -z "$(ls -A "$folder_to_process")" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY RUN] Would attempt to remove empty directory: $folder_to_process"
    else
        read -r -p "Directory '$folder_to_process' appears empty. Remove it? (yes/no): " confirm_rmdir
        if [[ "${confirm_rmdir,,}" == "yes" ]]; then
            echo "Removing empty directory: $folder_to_process"
            rmdir "$folder_to_process"
            if [[ $? -eq 0 ]]; then
                echo "[INFO] Successfully removed empty directory: $folder_to_process"
            else
                echo "[WARNING] Failed to remove directory (it might not be empty or permissions issue): $folder_to_process"
            fi
        else
            echo "[INFO] Skipping removal of directory: $folder_to_process"
        fi
    fi
  elif [[ "$VERBOSE" -eq 1 ]]; then
    echo "[VERBOSE] Directory '$folder_to_process' is not empty. Not attempting removal."
  fi
}

# --- Script Entry Point ---
if [[ "$DRY_RUN" -eq 1 && "$COMMIT_MODE" -eq 0 ]]; then
  echo -e "${YELLOW}*** DRY RUN MODE ENABLED - NO FILES WILL BE CHANGED. Use --commit to apply changes. ***${NC}"
elif [[ "$COMMIT_MODE" -eq 1 ]]; then
  echo "*** COMMIT MODE ENABLED - FILES WILL BE RENAMED. ***"
  read -r -p "You are about to make permanent changes. Continue? (yes/no): " confirm_commit
  if [[ "${confirm_commit,,}" != "yes" ]]; then
    echo "Operation cancelled by user."
    exit 0
  fi
fi


if [[ -f "$INPUT_PATH" ]]; then
  if is_media_file "$INPUT_PATH"; then
    clean_name "$INPUT_PATH"
  else
    echo "[INFO] Skipping non-media file (based on extension): $INPUT_PATH"
  fi
elif [[ -d "$INPUT_PATH" ]]; then
  process_folder "$INPUT_PATH"
else
  echo "Error: Input path '$INPUT_PATH' is not a valid file or directory." >&2
  exit 1
fi

echo "Media cleaning process complete."
exit 0

