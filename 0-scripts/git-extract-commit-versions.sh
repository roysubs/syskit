#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to export all versions of a Git repository's branch
# since a specific date into separate timestamped directories.
# This allows for later comparison of file versions.

# --- Configuration ---
# Path to your existing local clone of the syskit repository
# Example: REPO_PATH_TO_PROCESS="/home/boss/syskit"
REPO_PATH_TO_PROCESS="" # Will ask user if not set here

# Branch to process (usually "main" or "master")
BRANCH_NAME="main"

# Date from which to start processing commits (YYYY-MM-DDTHH:MM:SS+ZZ:ZZ or YYYY-MM-DD)
# "At least 2 days ago" from May 25, 2025 = May 23, 2025, 00:00:00 CEST
SINCE_DATE="2025-05-23T00:00:00+02:00"

# Parent directory for all the versioned checkouts.
OUTPUT_PARENT_DIR_BASE_NAME="project_commit_history"
# ---

# Function for logging messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}
# Function for debug messages
debug_message() {
    echo "DEBUG: [$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Script Start ---
debug_message "Script started."

# Prompt for REPO_PATH_TO_PROCESS if not set
if [ -z "$REPO_PATH_TO_PROCESS" ]; then
    read -r -p "Enter the full path to your local Git repository (e.g., ~/syskit on WSL2): " REPO_PATH_TO_PROCESS
    debug_message "User input for REPO_PATH_TO_PROCESS: '$REPO_PATH_TO_PROCESS'"
fi

# Expand tilde if present at the beginning of the path
original_repo_path_input="$REPO_PATH_TO_PROCESS" # Keep original for error messages if needed
if [[ "${REPO_PATH_TO_PROCESS:0:1}" == "~" ]]; then
    if [[ -z "${REPO_PATH_TO_PROCESS:1:1}" || "${REPO_PATH_TO_PROCESS:1:1}" == "/" ]]; then
        debug_message "Tilde found at start of '$original_repo_path_input', expanding with \$HOME."
        REPO_PATH_TO_PROCESS="${HOME}${REPO_PATH_TO_PROCESS:1}"
        debug_message "REPO_PATH_TO_PROCESS after tilde expansion: '$REPO_PATH_TO_PROCESS'"
    else
        debug_message "Tilde found in '$original_repo_path_input' but not in '~/...' or '~' format (e.g., '~user'). Current script does not expand other users' tildes. Proceeding with path as is."
    fi
fi

# Validate repository path (initial check before realpath)
if [ ! -d "$REPO_PATH_TO_PROCESS" ]; then
    log_message "Error: Preliminary check failed. Path '$REPO_PATH_TO_PROCESS' (from input '$original_repo_path_input') does not exist or is not a directory."
    exit 1
fi
debug_message "Preliminary path check passed for '$REPO_PATH_TO_PROCESS'."

# Convert REPO_PATH_TO_PROCESS to an absolute path and validate .git existence
debug_message "Attempting realpath for REPO_PATH_TO_PROCESS: '$REPO_PATH_TO_PROCESS'"
REPO_PATH_TO_PROCESS_ABS=$(realpath "$REPO_PATH_TO_PROCESS" 2>/dev/null)
REALPATH_STATUS_REPO=$?

if [ "$REALPATH_STATUS_REPO" -ne 0 ] || [ -z "$REPO_PATH_TO_PROCESS_ABS" ]; then
    log_message "Error: Could not resolve '$REPO_PATH_TO_PROCESS' to an absolute path using realpath (status: $REALPATH_STATUS_REPO)."
    log_message "Please check the path and if 'realpath' command is available and working."
    exit 1
fi
REPO_PATH_TO_PROCESS="$REPO_PATH_TO_PROCESS_ABS" # Use the absolute path from now on
debug_message "REPO_PATH_TO_PROCESS absolute path set to: '$REPO_PATH_TO_PROCESS'"

if [ ! -d "$REPO_PATH_TO_PROCESS/.git" ]; then
    log_message "Error: '$REPO_PATH_TO_PROCESS' does not appear to be a valid Git repository (missing .git directory)."
    exit 1
fi
log_message "Processing repository: $REPO_PATH_TO_PROCESS" # You saw this line before

# --- Output Parent Directory Creation ---
debug_message "Starting output parent directory creation."
CURRENT_WORKING_DIR=$(pwd)
debug_message "Current working directory (pwd) for script is: '$CURRENT_WORKING_DIR'"

OUTPUT_PARENT_DIR="${CURRENT_WORKING_DIR}/${OUTPUT_PARENT_DIR_BASE_NAME}"
debug_message "Proposed OUTPUT_PARENT_DIR path: '$OUTPUT_PARENT_DIR'"

mkdir -p "$OUTPUT_PARENT_DIR"
MKDIR_STATUS=$?
debug_message "mkdir -p '$OUTPUT_PARENT_DIR' exit status: $MKDIR_STATUS"

if [ "$MKDIR_STATUS" -ne 0 ]; then
    log_message "Error: mkdir -p '$OUTPUT_PARENT_DIR' failed with status $MKDIR_STATUS."
    exit 1
fi

if [ ! -d "$OUTPUT_PARENT_DIR" ]; then
    log_message "Error: Failed to create or access base output directory '$OUTPUT_PARENT_DIR' (it does not exist after mkdir -p command)."
    exit 1
fi
debug_message "Successfully created or ensured existence of '$OUTPUT_PARENT_DIR'"

debug_message "Attempting realpath for OUTPUT_PARENT_DIR: '$OUTPUT_PARENT_DIR'"
OUTPUT_PARENT_DIR_ABS=$(realpath "$OUTPUT_PARENT_DIR" 2>/dev/null)
REALPATH_STATUS_OUT=$?

if [ "$REALPATH_STATUS_OUT" -ne 0 ] || [ -z "$OUTPUT_PARENT_DIR_ABS" ]; then
    log_message "Error: Could not resolve '$OUTPUT_PARENT_DIR' to an absolute path using realpath (status: $REALPATH_STATUS_OUT)."
    log_message "Output directory may be invalid. Please check if 'realpath' command is available and working."
    exit 1
fi
OUTPUT_PARENT_DIR="$OUTPUT_PARENT_DIR_ABS" # Use the absolute path from now on
debug_message "OUTPUT_PARENT_DIR absolute path set to: '$OUTPUT_PARENT_DIR'"

log_message "Outputting versioned directories to: $OUTPUT_PARENT_DIR" # This should now print if the above steps worked.

# --- Get Commit List ---
debug_message "Attempting to get commit list."
debug_message "Running git log in: '$REPO_PATH_TO_PROCESS'"
debug_message "Branch: '$BRANCH_NAME', Since: '$SINCE_DATE'"

# Using a temporary file for git log output to robustly capture it and check command status
temp_commit_data_list_file=""
# Ensure temp file is cleaned up on exit, error, or interrupt
trap 'rm -f "$temp_commit_data_list_file"' EXIT SIGINT SIGTERM

temp_commit_data_list_file=$(mktemp "/tmp/commit_list_XXXXXX.txt")
if [ -z "$temp_commit_data_list_file" ] || [ ! -w "$temp_commit_data_list_file" ]; then
    log_message "Error: Could not create temporary file for commit list."
    exit 1
fi
debug_message "Temporary file for commit list: $temp_commit_data_list_file"

subshell_exit_status=0
(cd "$REPO_PATH_TO_PROCESS" && git log "$BRANCH_NAME" --since="$SINCE_DATE" --pretty=format:"%H %ct" --reverse > "$temp_commit_data_list_file")
subshell_exit_status=$?

debug_message "Exit status of (cd && git log) sequence: $subshell_exit_status"

if [ $subshell_exit_status -ne 0 ]; then
    log_message "Error: 'git log' command (or 'cd' into repo) failed with exit status $subshell_exit_status."
    log_message "Attempted to run in: '$REPO_PATH_TO_PROCESS'"
    log_message "Check for errors if you run this manually: cd \"$REPO_PATH_TO_PROCESS\" && git log \"$BRANCH_NAME\" --since=\"$SINCE_DATE\" --pretty=format:\"%H %ct\" --reverse"
    exit 1
fi

commit_data_list=$(cat "$temp_commit_data_list_file")
# Temp file will be removed by trap

debug_message "Raw commit_data_list length: ${#commit_data_list}"
# For multiline debug output, use a loop or process substitution if needed, or just head
if [ -n "$commit_data_list" ]; then
    debug_message "First few lines of commit_data_list:"
    echo "$commit_data_list" | head -n 3 | sed 's/^/DEBUG:   /'
else
    debug_message "commit_data_list is empty."
fi

if [ -z "$commit_data_list" ]; then
    log_message "No commits found since '$SINCE_DATE' on branch '$BRANCH_NAME' in '$REPO_PATH_TO_PROCESS'."
    log_message "Please check your SINCE_DATE ('$SINCE_DATE'), BRANCH_NAME ('$BRANCH_NAME'), and that the repository has commits in this range."
    log_message "Manual test command that should work if commits exist:"
    log_message "cd '$REPO_PATH_TO_PROCESS' && git log '$BRANCH_NAME' --since='$SINCE_DATE' --pretty=format:'%H %ct' --reverse"
    exit 0
fi

log_message "Found commits to process. This might take a while depending on the number of commits and repository size..."
log_message "--------------------------------------------------------------------------------"

# --- Process Each Commit ---
echo "$commit_data_list" | while IFS=' ' read -r commit_hash commit_unix_timestamp; do
    if [ -z "$commit_hash" ] || [ -z "$commit_unix_timestamp" ]; then
        log_message "Warning: Skipping invalid line from git log output (Hash: '$commit_hash', Timestamp: '$commit_unix_timestamp')."
        continue
    fi

    # Format the timestamp for the directory name (YYYYMMDD_HHMMSS)
    # Appending short commit hash for uniqueness if multiple commits share the exact same second.
    dir_timestamp_name=$(date -d "@$commit_unix_timestamp" +"%Y%m%d_%H%M%S")
    target_checkout_dir="${OUTPUT_PARENT_DIR}/syskit_${dir_timestamp_name}_${commit_hash:0:7}"

    log_message "Processing commit ${commit_hash:0:7} (Timestamp: $dir_timestamp_name)..."
    debug_message "Target directory for this commit: '$target_checkout_dir'"

    if [ -d "$target_checkout_dir" ]; then
        log_message "  Directory '$target_checkout_dir' already exists. Skipping export for this commit."
        debug_message "Skipped existing directory."
        log_message "--------------------------------------------------------------------------------"
        continue
    fi

    mkdir -p "$target_checkout_dir"
    if [ ! -d "$target_checkout_dir" ]; then
        log_message "  Error: Could not create directory '$target_checkout_dir'. Skipping this commit."
        debug_message "Failed to create target directory."
        log_message "--------------------------------------------------------------------------------"
        continue
    fi

    log_message "  Exporting files to '$target_checkout_dir'..."
    # Run git archive within the repo path, and ensure tar extracts to the correct absolute path
    if (cd "$REPO_PATH_TO_PROCESS" && git archive "$commit_hash" | tar -x -C "$target_checkout_dir"); then
        log_message "  Successfully exported commit ${commit_hash:0:7}."
    else
        log_message "  Error: Failed to export commit ${commit_hash:0:7}. Cleaning up partially created directory."
        rm -rf "$target_checkout_dir" # Clean up if archive/tar failed
    fi
    log_message "--------------------------------------------------------------------------------"
done

log_message "Finished processing all specified commits."
log_message "Versioned directories are located in: $OUTPUT_PARENT_DIR"
debug_message "Script finished."
