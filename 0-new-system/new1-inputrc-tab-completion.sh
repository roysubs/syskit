#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script: new1-inputrc.sh
# Purpose: Update the user's ~/.inputrc file with custom key bindings for bash/readline.
# Have to be very careful with making any changes here, so do not alter any default
# bindings at all, only add additional, and only if they do not conflict with existing
# shell functions, or tmux, or Windows Terminal (as a remote connection) etc.
# This only modifies the user's current configuration.
# Very tricky to get this right, due to different codes from keyboards and XOFF issue with
# some terminal emulators (so invoking 'stty -ixon' might affect tmux etc).

echo "Starting ~/.inputrc configuration update..."

# Define the target inputrc file
INPUTRC_FILE="$HOME/.inputrc"

# Define the inputrc configuration block with comments
# Use a quoted heredoc ('EOF') to prevent variable expansion within the block content.
read -r -d '' INPUTRC_BLOCK << 'EOF'


# --- Custom Tab Completion Bindings ---

# Cycle through completions with Tab
TAB: menu-complete

# (Optional) Cycle backward with Shift+Tab
"\e[Z": menu-complete-backward

# (Optional) Show all ambiguous completions before cycling
set show-all-if-ambiguous on

# Keep case-insensitive completion as you set previously
set completion-ignore-case on

# --- End Tab Completion Bindings ---
EOF

# Ensure ~/.inputrc file exists
if [ ! -f "$INPUTRC_FILE" ]; then
    echo "Creating $INPUTRC_FILE..."
    touch "$INPUTRC_FILE"
    if [ $? -ne 0 ]; then
        echo "Error: Could not create $INPUTRC_FILE. Check file permissions for $HOME."
        exit 1
    fi
else
    echo "$INPUTRC_FILE already exists."
fi

# Use a temporary file for processing to ensure atomicity and handle duplicates
TEMP_FILE=$(mktemp)

# Read the current content of .inputrc into the temporary file
# Handle cases where cat might fail or the file is empty
if [ -f "$INPUTRC_FILE" ]; then
    cat "$INPUTRC_FILE" > "$TEMP_FILE"
else
    # Should not happen if touch succeeded, but good practice
    echo "" > "$TEMP_FILE"
fi


# Append the new configuration block to the temporary file
echo "$INPUTRC_BLOCK" >> "$TEMP_FILE"

# Filter the temporary file to remove duplicate lines
# This ensures running the script multiple times doesn't add duplicate bindings.
# awk '!x[$0]++' prints each line only once based on content.
# Redirecting stderr of awk to /dev/null just in case (e.g., very large file issues)
awk '!x[$0]++' "$TEMP_FILE" 2>/dev/null > "${TEMP_FILE}.cleaned"
mv "${TEMP_FILE}.cleaned" "$TEMP_FILE"

# Replace the original .inputrc with the processed temporary file
# This ensures the file is updated cleanly.
mv "$TEMP_FILE" "$INPUTRC_FILE"

echo "Successfully updated $INPUTRC_FILE."

echo -e "\nConfiguration update complete!"
echo "The changes will take effect in new bash sessions."
echo "To apply them to your *current* session, run: bind -f ~/.inputrc"

echo -e "\nRemember the caveats mentioned in the comments inside $INPUTRC_FILE regarding terminal compatibility (showkey -a) and terminal multiplexers (tmux/screen)."
