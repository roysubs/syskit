#!/bin/bash
# Author: Roy Wiseman 2025-02

# Explain what the script does
echo "The purpose of this script is to add simple .inputrc entries to use"
echo "Ctrl+Home / Ctrl+End to delete from the cursor to the start or end of the line."
echo
echo "As different keyboards have different codes for Home and End, we have to scan"
echo "this keyboard for them, and then display the lines to add to .inputrc"
echo
echo "  Set 'Ctrl+Home' to delete from current cursor back to the start of the line."
echo "  Set 'Ctrl+End' to delete from current cursor to the end of line."
echo
echo "Please press first the Home key, and then the input will wait for the End key."
echo "--------------------------------------------------------------------"
# Removed the extra echo here - the prompt function handles the newline after input
# echo


read_key_sequence() {
    local key=""
    local prompt="$1"

    # Save cursor position
    tput sc

    # Print the prompt
    printf "%s " "$prompt"

    # Try different flushing methods - tput effects, save/restore cursor
    tput smso; tput rmso # Using tput effects can also force flush
    tput rc # Restore cursor position (often forces flush)
    tput sc # Save cursor again before reading

    # Add a tiny sleep as a last resort if flushing isn't instant
    # sleep 0.02 # Maybe uncomment this if still failing

    # Read escape sequence silently, one character at a time
    IFS= read -rsn1 key
    while read -rsn1 -t 0.01 part; do
        key+="$part"
    done

    tput rc # Restore cursor after reading

    echo                      # Move to next line after reading the sequence
    # Use printf %q to show the sequence in a way suitable for shell/inputrc
    printf '%q' "$key"
}

HOME_SEQ=$(read_key_sequence "----------")
echo "You pressed HOME: $HOME_SEQ"

echo # Add a blank line for separation
END_SEQ=$(read_key_sequence "----------")
echo "You pressed END:  $END_SEQ"

echo
echo "--------------------------------------------------------------------"
echo "# Add the following to your ~/.inputrc:"
# NOTE: These are the standard modern codes. We'll also show the alternative.
echo "\"\\e[1;5H\": unix-line-discard    # Ctrl+HOME (delete to beginning of line)"
echo "\"\\e[1;5F\": kill-line            # Ctrl+END (delete to end of line)"

# Attempt to parse the actual key codes captured
# Modern terminals often send \e[1;5H and \e[1;5F for Ctrl+Home/End
# but older or different terminals might send sequences like \e[1~ and \e[4~
# combined with the Ctrl modifier often adding ';5'
# This part tries to see if the captured sequence is the simple \e[<NUM>~ format
# and if so, suggests the ;5 modifier version for Ctrl.

# Match \e[<Digits>~
[[ $HOME_SEQ =~ \\e\[([0-9]+)~ ]] && HOME_NUM=${BASH_REMATCH[1]}
[[ $END_SEQ  =~ \\e\[([0-9]+)~ ]] && END_NUM=${BASH_REMATCH[1]}


if [[ -n "$HOME_NUM" && -n "$END_NUM" ]]; then
    echo
    echo "# --- OR (based on the simple sequence your terminal sent): ---"
    echo "# Add the following to your ~/.inputrc instead:"
    echo "\"\\e[${HOME_NUM};5~\": unix-line-discard # Ctrl+HOME (delete to beginning of line)"
    echo "\"\\e[${END_NUM};5~\": kill-line          # Ctrl+END (delete to end of line)"
fi

echo "--------------------------------------------------------------------"
echo "After adding the lines to ~/.inputrc, you may need to reload it with:"
echo "bind -f ~/.inputrc"
