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
# --- Custom Key Bindings ---
# Explanation of inputrc syntax:
# "key-sequence": function-name
# Ctrl- key combinations are often represented as \C-X (e.g., Ctrl-k is \C-k)
# Alt- key combinations are often represented as \eX (Escape followed by X) or \M-X (Meta-X)
# Escape sequences (\e[...): These are common for function keys, arrow keys with modifiers.
#
# !!! IMPORTANT CAVEATS !!!
# 1. Terminal Emulators: The exact key sequences sent by Ctrl-Home, Ctrl-End, Ctrl-Backspace,
#    and some Alt combinations can vary significantly between different terminal emulators
#    (e.g., GNOME Terminal, Konsole, Alacritty, Kitty, Windows Terminal, etc.).
#    If a binding doesn't work, you may need to identify the specific escape sequence
#    your terminal sends for that key combination. You can often do this by running
#    'showkey -a' or 'cat -v' in your terminal, then press the key combination, and
#    see what is output. Then update the key sequence in this file accordingly.
#
# 2. Terminal Multiplexers (tmux, screen): Tools like tmux or screen can intercept
#    key presses before they reach the shell. This can sometimes prevent complex key
#    combinations (especially those involving Alt or Ctrl with Home/End/Arrows) from
#    working unless the multiplexer is configured to pass them through (e.g., in tmux,
#    'set-window-option -g xterm-keys on' in your tmux.conf might help).
#    If you use tmux/screen and a binding doesn't work, try testing it outside the
#    multiplexer to isolate the issue.
#
# 3. Bash Keymap (Emacs/Vi): Bash's command line editing uses either Emacs mode (default)
#    or Vi mode. These bindings are generally independent of the keymap, but understanding
#    the standard bindings in your chosen mode might help avoid conflicts or confusion.
#    (This script assumes default Emacs mode bindings are potentially being overridden).


# Ctrl-j: Incremental search forward through history
# This maps Ctrl-j to start a forward incremental search (after a backward search has begun).
# In Vim/vi terms, similar to navigating command history downwards.
# Standard Emacs mode binding for \C-j is 'newline' (execute line and move down).
# This binding OVERRIDES the standard newline action for Ctrl-j.
# If you prefer the standard 'newline' for Ctrl-j, remove or comment out the line below.
"\C-j": forward-i-search

# Ctrl-k: Incremental search backward through history (same as up in vim and roguelikes)
# This maps Ctrl-k to start a reverse incremental search. In Vim/vi terms, similar to
# navigating command history, but interactive searching is more powerful.
# Standard Emacs mode binding for \C-k is 'kill-line' (delete from cursor to end).
# This binding OVERRIDES the standard kill-line action for Ctrl-k.
# If you prefer the standard 'kill-line' for Ctrl-k, remove or comment out the line below.
"\C-k": backward-i-search

# Alt-r: Incremental search backward through history (Alternative binding)
# Provides an alternative keybinding for reverse history search.
### "\er": backward-i-searcr
"\M-r": backward-i-searcr

# Alt-s: Incremental search forward through history (Alternative binding)
# Provides an alternative keybinding for forward history search.
### "\es": forward-i-search
"\M-s": forward-i-search

# Ctrl-Backspace: Kill the word before the cursor
# This maps Ctrl-Backspace to the 'backward-kill-word' action.
# The key sequence "\C-?" is a common representation for Ctrl-Backspace in terminals.
# The standard readline binding for 'backward-kill-word' is \C-w (Ctrl-w).
# Binding Ctrl-Backspace here might conflict if your terminal sends a different sequence
# (like \C-h, which is commonly mapped to 'backward-char' or 'delete-backward-char').
# Test this binding carefully in your terminal. If it doesn't work, use 'showkey -a'
# to identify what Ctrl-Backspace sends and update "\C-?" below accordingly.
# Alternatively, consider using the standard \C-w which is more reliable across terminals.
"\C-?": backward-kill-word
# Alternative if Ctrl-Backspace sends \C-h in your terminal:
# "\C-h": backward-kill-word
# Standard readline binding (always works unless rebound):
# "\C-w": backward-kill-word

# Ctrl-Home: Kill from cursor to the beginning of the line
# This binding maps Ctrl-Home to the 'backward-kill-line' action.
# The escape sequence "\e[1;5H" is a common representation for Ctrl-Home, but is terminal-dependent.
# The standard readline binding for 'backward-kill-line' is \C-u (Ctrl-u).
# This binding OVERRIDES the standard Ctrl-u action if used simultaneously.
# Test this binding in your terminal and update "\e[1;5H" if needed using 'showkey -a'.
"\e[1;5H": backward-kill-line

# Ctrl-End: Kill from cursor to the end of the line
# This binding for Ctrl-End provides an alternative way to perform 'kill-line'.
# "\e[4;5H" or "\e[1;5F are common representations for Ctrl-End, but it is terminal-dependent.
# Test the below binding, and if it doesn't work, use 'showkey -a' or 'cat -v' then press the key
# combination to see and update the code below if needed.
# The standard readline binding for 'kill-line' (from cursor to end) is \C-k (Ctrl-k).
"\e[1;5F": kill-line

# --- End Custom Bindings ---
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
