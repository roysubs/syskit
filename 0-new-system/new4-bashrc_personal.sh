#!/bin/bash
# Author: Roy Wiseman 2025-01

# Each line in 'bashrc_block' will be tested against .bashrc
# If that item exists with a different value, it will not alter it
# so by design does not mess up existing configurations (it just
# adds any elements not covered to the end of .bashrc).
#
# e.g. if 'export EDITOR=' is set (to vi or emacs or nano) the
# export EDITOR= line in here will not be added and the existing
# line will not be altered.
#
# Multi-line functions are treated as a single block; again, if a
# function with that name already exists, this script will not modify
# that, and will not add the new entry. Otherwise, the whole
# multi-line function from bashrc_block will be added to .bashrc
# so the whole function is cleanly added.

# Backup ~/.bashrc before making changes
BASHRC_FILE="$HOME/.bashrc_personal"
if [[ -f "$BASHRC_FILE" ]]; then
    cp "$BASHRC_FILE" "$BASHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
    echo "Backed up $BASHRC_FILE to $BASHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
else
    echo "Warning: $BASHRC_FILE does not exist. A new one will be created."
fi

# If -clean is invoked, then the old block will be removed from .bashrc and replaced
CLEAN_MODE=false

# Check the number of arguments
if [[ "$#" -eq 0 ]]; then
    # No arguments, proceed with default behavior (CLEAN_MODE is already false)
    : # No operation
elif [[ "$#" -eq 1 && "$1" == "--clean" ]]; then
    # Exactly one argument and it is "--clean"
    CLEAN_MODE=true
else
    # Any other number of arguments or a different argument
    echo >&2 "Error: Invalid arguments."
    echo >&2 "Usage: $(basename "${BASH_SOURCE[0]}") [--clean]"

    # Decide whether to exit or return based on how the script was invoked
    if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
        exit 1
    else
        return 1
    fi
fi

# Block of text to check and add to .bashrc
# Using a here document for readability and maintainability.
# The delimiter 'EOF_BASHRC_CONTENT' is quoted to prevent shell expansion
# of variables like $HOME, $PATH, etc., within this block. They will be
# written literally to .bashrc and expanded when .bashrc is sourced.
bashrc_block=$(cat <<'EOF_BASHRC_CONTENT'
# syskit definitions
####################
# Tools and Jump functions for personal folder (could be in a separate .bashrc-personal, but fine to leave here for now)
# Use 'D' to jump to my the D variable Dv, and can use the variable like this:    mv *.mp4 "$Dv"/     # Easy access for defined locations like this
export Dv="$HOME/Downloads";   D()  { cd "$Dv" || { echo "Dir '$Dv' not present"; return 1; }; ls; } # Jump to my personal Downloads folder
export DFv="$Dv/0 Films"; DF() { cd "$DFv" 2>/dev/null && ls || echo "Dir '$DFv' not present"; } # Jump to '0 Films'
export DTv="$Dv/0 TV";    DT() { cd "$DTv" 2>/dev/null && ls || echo "Dir '$DTv' not present"; } # Jump to '0 TV'
export DMv="$Dv/0 Music"; DM() { cd "$DMv" 2>/dev/null && ls || echo "Dir '$DMv' not present"; } # Jump to '0 Music'
white() { cd ~/192.168.1.29-d || { echo "Directory '~/192.168.1.29-d' not present"; return 1; }; ls; } # Jump to my 'WHITE' Win11 PC SMB share

# Docker Compose quick commands for testing: dcup, dcstop, dcrm, dcrestart, dcdown
# Usage: dcup dashboards [optional args] → uses docker-dashboards.yaml
_docker_compose_wrap() {
    local cmd="$1"; shift
    local base="$1"; shift
  
    local file="docker-${base}.yaml"
    local project="${file%.yaml}"
    project="${project//-/_}"  # replace - with _
  
    if [[ ! -f "$file" ]]; then
        echo "❌ Compose file not found: $file"
        return 1
    fi
  
    docker compose -f "$file" -p "$project" "$cmd" "$@"
}
# Wrapper functions
dcup()       { _docker_compose_wrap up "$@" ; }
dcstop()     { _docker_compose_wrap stop "$@" ; }
dcrm()       { _docker_compose_wrap rm -f "$@" ; }
dcrestart()  { _docker_compose_wrap restart "$@" ; }
# Stop + remove containers
dcdown() {
    local base="$1"; shift
    dcstop "$base" "$@" && dcrm "$base" "$@"
}



EOF_BASHRC_CONTENT
)

# Capture the first non-empty line of $bashrc_block, this is the header line
first_non_empty_line=$(echo "$bashrc_block" | sed -n '/[^[:space:]]/s/^[[:space:]]*//p' | head -n 1)

# Ensure the variable is not empty
if [[ -z "$first_non_empty_line" ]]; then
    echo "Error: No valid content found in bashrc_block. Exiting."
    exit 1 # Exit if the block is empty, as something is wrong.
fi

# Check if this line exists in .bashrc
# Only attempt cleanup if the marker is found and CLEAN_MODE is true
if [[ "$CLEAN_MODE" == true ]]; then
    if grep -Fxq "$first_non_empty_line" "$BASHRC_FILE"; then
        echo "CLEAN_MODE: Performing cleanup. Deleting block from '$first_non_empty_line' to end of $BASHRC_FILE."
        # Escape the marker line for sed address
        escaped_marker=$(printf '%s\n' "$first_non_empty_line" | sed 's/[.[\*^$]/\\&/g')
        sed -i "/^${escaped_marker}$/,\$d" "$BASHRC_FILE"
        echo "Removed block from $BASHRC_FILE."
    else
        echo "CLEAN_MODE: Marker line '$first_non_empty_line' not found in $BASHRC_FILE. No cleanup performed."
    fi
fi

# Function to check and add lines/functions
# This function will now be called by the main loop that processes $bashrc_block
# It determines the type of line and checks if it (or its identifier) already exists.
add_entry_if_not_exists() {
    local entry_block="$1" # Can be a single line or a full function block
    local first_line_of_entry
    first_line_of_entry=$(echo "$entry_block" | head -n 1)
    local entry_type=""
    local identifier=""

    # Determine entry type and identifier (e.g., alias name, export variable name, function name)
    if [[ "$first_line_of_entry" =~ ^[[:space:]]*alias[[:space:]]+([^=]+)= ]]; then
        entry_type="alias"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*(export|declare[[:space:]]+-x)[[:space:]]+([^=]+)= ]]; then
        entry_type="export"
        identifier="${BASH_REMATCH[2]}"
        # Special handling for PATH to allow multiple unique additions
        if [[ "$identifier" == "PATH" ]]; then
            if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
                echo "Exact PATH definition already exists: $first_line_of_entry. Skipping."
                return
            fi
            # If not exact match, proceed to add (handled by general "add now" logic)
        fi
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*\{ ]]; then # func() {
        entry_type="function"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*([\{\(]) ]]; then # function func { or function func () {
        entry_type="function"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*# ]]; then
        entry_type="comment"
         # For comments, shopt, complete, if, fi, and other simple lines, check for exact line existence
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
            # Silently skip if exact comment already exists
            return
        fi
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*(shopt|complete|if|fi) ]]; then
        entry_type="directive" # Generic type for shopt, complete etc.
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
             # Silently skip if exact directive already exists
            return
        fi
    elif [[ -z "${first_line_of_entry// }" ]]; then # Check if line is blank or only whitespace
        entry_type="blank"
        # Blank lines will be added directly by the main loop
    else
        entry_type="other"
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
            # Silently skip if exact other line already exists
            return
        fi
    fi

    # Check for existence based on identifier for alias, export (non-PATH), function
    if [[ "$entry_type" == "alias" ]]; then
        # Trim whitespace from identifier for grep
        local trimmed_identifier=$(echo "$identifier" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if grep -qE "^[[:space:]]*alias[[:space:]]+${trimmed_identifier}=" "$BASHRC_FILE"; then
            echo "Alias ${trimmed_identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    elif [[ "$entry_type" == "export" && "$identifier" != "PATH" ]]; then # PATH is handled above
        if grep -qE "^[[:space:]]*(export|declare[[:space:]]+-x)[[:space:]]+${identifier}=" "$BASHRC_FILE"; then
            echo "Export ${identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    elif [[ "$entry_type" == "function" ]]; then
        # More robust check for function definition start
        if grep -qE "(^|[[:space:]])${identifier}[[:space:]]*\(\)[[:space:]]*\{|^\s*function\s+${identifier}" "$BASHRC_FILE"; then
            echo "Function ${identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    fi

    # If we reach here, the entry (or its unique part) doesn't exist, or it's a type that should be added if not an exact match
    echo "Adding to $BASHRC_FILE:"
    echo "$entry_block" # For logging what's being added
    echo "$entry_block" >> "$BASHRC_FILE"
    echo # Add a newline for better separation in .bashrc if adding multiple blocks
}

# Ensure the main marker line is present if it was cleaned or never existed
if ! grep -Fxq "$first_non_empty_line" "$BASHRC_FILE"; then
    echo "Adding main marker: $first_non_empty_line"
    echo "$first_non_empty_line" >> "$BASHRC_FILE"
fi


# Process the bashrc_block, identifying functions and other entries
current_block=""
in_function_block=false
first_line_of_block="" # Not strictly needed here anymore with current logic but kept for now

# Use process substitution to feed the main block processing loop,
# skipping the first line (marker line) which is handled separately.
# This avoids issues with the last line of input sometimes being missed by `while read` from a variable.
while IFS= read -r line; do
    # Detect start of a function (e.g., func() { or function func {)
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*\{ || "$line" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        if $in_function_block && [[ -n "$current_block" ]]; then # We were in a function, and it's ending implicitly by starting a new one
            add_entry_if_not_exists "$current_block"
        fi
        current_block="$line"
        in_function_block=true
    elif $in_function_block; then
        current_block+=$'\n'"$line"
        # Detect end of a function block
        if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            add_entry_if_not_exists "$current_block"
            current_block=""
            in_function_block=false
        fi
    else # Not in a function block, treat as a single-line entry or a non-function multi-line (e.g. comments)
        if [[ -n "${line// }" ]]; then # If line is not blank (handles lines with only spaces correctly)
             add_entry_if_not_exists "$line" # Process single lines or start of non-function blocks
        else # Preserve blank lines from the here-doc
            echo >> "$BASHRC_FILE"
        fi
        # current_block="" # Not needed here as single lines are processed immediately
    fi
done < <(echo "$bashrc_block" | sed '1d') # Process block, skipping the first_non_empty_line (marker)

# If the loop finishes and we were still accumulating a function block (e.g., file ends mid-function without a closing brace on its own line)
if $in_function_block && [[ -n "$current_block" ]]; then
    add_entry_if_not_exists "$current_block"
fi

# Remove trailing blank lines that might have been introduced
if [[ -s "$BASHRC_FILE" ]]; then # Only run sed if file is not empty
    # This sed command removes all trailing blank lines from the file
    sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$BASHRC_FILE"
    # Additionally, ensure there's exactly one newline at the very end if the file is not empty
    if [[ $(tail -c1 "$BASHRC_FILE" | wc -l) -eq 0 ]]; then
        echo >> "$BASHRC_FILE"
    fi
fi


echo
echo "Finished updating $BASHRC_FILE."

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Script is sourced
    echo
    echo "This script was sourced. Sourcing $BASHRC_FILE to apply changes to the current environment..."
    # Ensure BASHRC_FILE is sourced correctly even if path contains spaces
    # shellcheck source=/dev/null
    source "$BASHRC_FILE"
    echo "Environment updated."
else
    # Script is executed
    echo
    echo "This script was executed directly. To apply changes to the current environment, run:"
    echo "    source $BASHRC_FILE"
    echo "Or open a new terminal session."
fi

