#!/bin/bash
# Author: Roy Wiseman 2025-01

# Functions for colored output
green()  { echo -e "\033[1;32m$*\033[0m"; }
white()  { echo -e "\033[0;37m$*"; }
red()    { echo -e "\033[1;31m$*\033[0m"; }
yellow() { echo -e "\033[1;33m$*\033[0m"; }

# Help/usage function
show_usage() {
    white "${0##*/} A simple zip tool."
    white "Usage: ${0##*/} [OPTIONS] /path/to/folder"
    white "Options:"
    white "  -s, --sudo          Use sudo to zip everything (ignores permission errors)"
    white "  -i, --ignore-errors Continue zipping and list errors at the end"
    white "  -h, --help          Show this help message"
    white ""
    white "  - Must be a directory (not a file), but accepts ~ ./ etc"
    white "  - Packs up with hidden files/folders included"
    white "  - Backup saved to ~/.backups/<foldername>-YYYY-MM-DD_HH-MM-SS.zip"
}

# Initialize flags
USE_SUDO=false
IGNORE_ERRORS=false
SRC_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--sudo)
            USE_SUDO=true
            shift
            ;;
        -i|--ignore-errors)
            IGNORE_ERRORS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            red "Error: Unknown option '$1'"
            exit 1
            ;;
        *)
            if [[ -n "$SRC_PATH" ]]; then
                red "Error: Multiple paths specified. Only one path allowed."
                exit 1
            fi
            SRC_PATH="$1"
            shift
            ;;
    esac
done

# Check for zip dependency
if ! command -v zip &>/dev/null; then
    red "Error: 'zip' command not found. Please install it first."
    exit 1
fi

# Ensure exactly one path argument is provided
if [[ -z "$SRC_PATH" ]]; then
    show_usage
    exit 1
fi

# Expand the path properly (handle ~, ./, ../, etc.)
if [[ "$SRC_PATH" == "~" ]]; then
    SRC_EXPANDED="$HOME"
elif [[ "$SRC_PATH" == ~/* ]]; then
    SRC_EXPANDED="$HOME/${SRC_PATH#~/}"
else
    SRC_EXPANDED="$SRC_PATH"
fi

# Convert to absolute path
SRC_ABS="$(realpath "$SRC_EXPANDED" 2>/dev/null)"
if [[ $? -ne 0 ]]; then
    red "Error: Cannot resolve path '$SRC_PATH'"
    exit 1
fi

# Check if input is a directory
if [[ ! -d "$SRC_ABS" ]]; then
    red "Error: '$SRC_PATH' is not a directory."
    exit 1
fi

# Prepare paths and names
FOLDER_NAME="$(basename "$SRC_ABS")"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DEST_DIR="$HOME/.backups"
ZIP_NAME="${FOLDER_NAME}-${TIMESTAMP}.zip"
ZIP_PATH="${DEST_DIR}/${ZIP_NAME}"

# Create backup directory if needed
mkdir -p "$DEST_DIR"

# Function to check for permission errors
check_permissions() {
    local temp_errors
    temp_errors=$(mktemp)
    
    if [[ "$USE_SUDO" == true ]]; then
        return 0  # Skip permission check if using sudo
    fi
    
    # Test du command to check for permission issues
    du -sm "$SRC_ABS" >/dev/null 2>"$temp_errors"
    
    if [[ -s "$temp_errors" ]]; then
        red "Permission errors detected:"
        cat "$temp_errors"
        rm -f "$temp_errors"
        
        if [[ "$IGNORE_ERRORS" == false ]]; then
            red "Aborting due to permission errors. Use -s for sudo or -i to ignore errors."
            exit 1
        else
            yellow "Continuing with errors (--ignore-errors specified)..."
            return 1  # Return 1 to indicate errors were found
        fi
    fi
    
    rm -f "$temp_errors"
    return 0
}

# Check permissions first
errors_found=false
if ! check_permissions; then
    errors_found=true
fi

# Calculate source size in MB (suppress errors if ignoring them)
if [[ "$USE_SUDO" == true ]]; then
    SRC_SIZE=$(sudo du -sm "$SRC_ABS" 2>/dev/null | awk '{printf "%.2f", $1/1}')
elif [[ "$IGNORE_ERRORS" == true ]]; then
    SRC_SIZE=$(du -sm "$SRC_ABS" 2>/dev/null | awk '{printf "%.2f", $1/1}')
else
    SRC_SIZE=$(du -sm "$SRC_ABS" | awk '{printf "%.2f", $1/1}')
fi

# Prepare zip command
ZIP_CMD="zip -r -9"
if [[ "$USE_SUDO" == true ]]; then
    ZIP_CMD="sudo $ZIP_CMD"
fi

# Show command that will be run (from the parent directory)
green "# cd \"$(dirname "$SRC_ABS")\""
green "\$ $ZIP_CMD \"$ZIP_PATH\" \"$FOLDER_NAME\""

# Create temporary file for error capture
error_log=$(mktemp)

# Change to parent directory and run zip
cd "$(dirname "$SRC_ABS")"

# Run zip command with appropriate error handling
if [[ "$USE_SUDO" == true ]]; then
    sudo zip -r -9 "$ZIP_PATH" "$FOLDER_NAME" >/dev/null 2>"$error_log"
    zip_exit_code=$?
elif [[ "$IGNORE_ERRORS" == true ]]; then
    zip -r -9 "$ZIP_PATH" "$FOLDER_NAME" >/dev/null 2>"$error_log"
    zip_exit_code=$?
else
    # Default mode: stop on any error
    zip -r -9 "$ZIP_PATH" "$FOLDER_NAME" >/dev/null 2>"$error_log"
    zip_exit_code=$?
fi

# Handle zip command results
if [[ $zip_exit_code -ne 0 ]] && [[ "$IGNORE_ERRORS" == false ]] && [[ "$USE_SUDO" == false ]]; then
    red "Zip command failed with errors:"
    cat "$error_log"
    rm -f "$error_log"
    # Clean up partial zip file
    rm -f "$ZIP_PATH"
    red "Backup aborted due to errors. Use -s for sudo or -i to ignore errors."
    exit 1
fi

# Show errors if any occurred and we're in ignore mode
if [[ -s "$error_log" ]] && [[ "$IGNORE_ERRORS" == true ]]; then
    yellow "Errors encountered during zip operation:"
    cat "$error_log"
fi

rm -f "$error_log"

# Get final zip size if file was created
if [[ -f "$ZIP_PATH" ]]; then
    ZIP_SIZE=$(du -sm "$ZIP_PATH" | awk '{printf "%.2f", $1/1}')
    
    # Output result
    white "Creating backup for: $SRC_ABS   (size: ${SRC_SIZE} MB)"
    white "Destination zip:     $ZIP_PATH   (size: ${ZIP_SIZE} MB)"
    
    if [[ "$errors_found" == true ]] || [[ -s "$error_log" ]]; then
        yellow "⚠️  Backup completed with errors!"
    else
        white "✅ Backup complete!"
    fi
else
    red "❌ Backup failed - no zip file created"
    exit 1
fi
