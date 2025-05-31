#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to download Mac versions of Zork I, II, and III,
# extract them, find the .z5 game files, and move them to the current directory.

# --- Configuration ---
# Target directory for the final .z5 files (current working directory where the script is run)
CWD=$(pwd)

# Base temporary directory for downloads and extraction.
# Using $$ for a process-ID-specific temporary directory name.
TMP_BASE_DIR="/tmp/zork_hqx_extraction_$$"

# Zork game details: game_key -> download_url
declare -A ZORK_GAMES
ZORK_GAMES=(
    ["zork1"]="http://infocom-if.org/downloads/zorki.hqx"
    ["zork2"]="http://infocom-if.org/downloads/zorkii.hqx"
    ["zork3"]="http://infocom-if.org/downloads/zorkiii.hqx"
)
# --- End Configuration ---

# --- Sanity Checks ---
# Check if unar is available
if ! command -v unar &> /dev/null; then
    echo "Error: 'unar' command not found." >&2
    echo "This script requires 'unar' to extract .hqx files." >&2
    echo "Please install it. For example:" >&2
    echo "  On Debian/Ubuntu: sudo apt-get install unar" >&2
    echo "  On macOS (via Homebrew): brew install unar" >&2
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' command not found." >&2
    echo "This script requires 'curl' to download files." >&2
    exit 1
fi
# --- End Sanity Checks ---

# --- Main Logic ---
# Create the base temporary directory
mkdir -p "$TMP_BASE_DIR"
if [ ! -d "$TMP_BASE_DIR" ]; then
    echo "Error: Failed to create temporary base directory $TMP_BASE_DIR. Aborting." >&2
    exit 1
fi

# Ensure cleanup of the base temporary directory on script exit (normal or error)
trap 'echo "Cleaning up temporary directory $TMP_BASE_DIR..."; rm -rf "$TMP_BASE_DIR"' EXIT

echo "Zork .z5 file fetcher"
echo "Output directory for .z5 files: $CWD"
echo "Temporary work directory: $TMP_BASE_DIR"
echo "---"

SUCCESS_COUNT=0
FAIL_COUNT=0

for GAME_KEY in "${!ZORK_GAMES[@]}"; do
    GAME_URL="${ZORK_GAMES[$GAME_KEY]}"
    HQX_FILENAME=$(basename "$GAME_URL")
    # Create a unique temporary directory for each game's processing
    GAME_TMP_DIR="$TMP_BASE_DIR/$GAME_KEY"
    Z5_TARGET_FILENAME="${GAME_KEY}.z5" # e.g., zork1.z5

    echo "Processing $GAME_KEY ($HQX_FILENAME)..."

    mkdir -p "$GAME_TMP_DIR"
    if [ ! -d "$GAME_TMP_DIR" ]; then
        echo "  Error: Failed to create temporary directory $GAME_TMP_DIR for $GAME_KEY. Skipping." >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "  Downloading $HQX_FILENAME..."
    if curl --fail -L -s -o "$GAME_TMP_DIR/$HQX_FILENAME" "$GAME_URL"; then
        echo "  Download successful: $GAME_TMP_DIR/$HQX_FILENAME"

        echo "  Extracting $HQX_FILENAME in $GAME_TMP_DIR..."
        # -q for quiet, -o to specify output directory.
        # unar will often create a subdirectory within GAME_TMP_DIR if the archive has one.
        if unar -q -o "$GAME_TMP_DIR" "$GAME_TMP_DIR/$HQX_FILENAME"; then
            echo "  Extraction successful."

            echo "  Searching for .z5 file(s) in $GAME_TMP_DIR..."
            # Find .z5 files (case-insensitive). Store all found files in an array.
            mapfile -t Z5_FILES_FOUND < <(find "$GAME_TMP_DIR" -type f -iname "*.z5")

            if [ ${#Z5_FILES_FOUND[@]} -gt 0 ]; then
                # If multiple .z5 files are found, we'll take the first one.
                # You might want to add logic here if multiple are common and need specific handling.
                Z5_FILE_PATH="${Z5_FILES_FOUND[0]}"
                Z5_BASENAME=$(basename "$Z5_FILE_PATH")
                echo "    Found .z5 file: $Z5_BASENAME (at $Z5_FILE_PATH)"

                if [ ${#Z5_FILES_FOUND[@]} -gt 1 ]; then
                    echo "    Warning: Multiple .z5 files found. Using the first one: $Z5_BASENAME"
                    echo "    Other files found:"
                    for (( i=1; i<${#Z5_FILES_FOUND[@]}; i++ )); do
                        echo "      - $(basename "${Z5_FILES_FOUND[$i]}") (at ${Z5_FILES_FOUND[$i]})"
                    done
                fi

                echo "    Moving '$Z5_BASENAME' to '$CWD/$Z5_TARGET_FILENAME'"
                if mv "$Z5_FILE_PATH" "$CWD/$Z5_TARGET_FILENAME"; then
                    echo "    Successfully moved to $CWD/$Z5_TARGET_FILENAME"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                else
                    echo "    Error: Failed to move .z5 file to $CWD." >&2
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                fi
            else
                echo "    Error: No .z5 file found for $GAME_KEY in the extracted contents of $HQX_FILENAME." >&2
                echo "    You can inspect the extracted contents (if any) in a subdirectory under $GAME_TMP_DIR before this script cleans it up (if not run with immediate rm)." >&2
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        else
            echo "  Error: Failed to extract $HQX_FILENAME." >&2
            echo "  The downloaded file is $GAME_TMP_DIR/$HQX_FILENAME" >&2
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "  Error: Failed to download $HQX_FILENAME from $GAME_URL. curl exit code: $?" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Clean up the specific game's temporary directory immediately
    # The main trap will catch TMP_BASE_DIR, but this keeps /tmp cleaner during long runs.
    # Note: If you need to inspect files on failure, you might comment out the rm command here
    # and rely solely on the main trap, or add conditional logic.
    echo "  Cleaning up $GAME_TMP_DIR..."
    rm -rf "$GAME_TMP_DIR"
    echo "$GAME_KEY processing complete."
    echo "---"
done

echo "All processing finished."
echo "Successfully retrieved $SUCCESS_COUNT .z5 file(s)."
if [ $FAIL_COUNT -gt 0 ]; then
    echo "Failed to retrieve $FAIL_COUNT .z5 file(s)." >&2
    echo "Check for error messages above."
    # The main trap will still clean up $TMP_BASE_DIR
    exit 1 # Exit with an error code if any failures occurred
fi

# Trap will handle final cleanup of TMP_BASE_DIR
exit 0
