#!/bin/bash
# Author: Roy Wiseman 2025-01

# Only run this script if it is sourced
(return 0 2>/dev/null) || {
    echo "Only run this script sourced (i.e., '. ./set-vi-mode.sh' to change to vi mode)"
    echo "This will set the bash environment to vi mode with:   set -o vi"
    exit 1;
}

echo
echo "set -o vi"
set -o vi
echo "
To switch back to (the default) emacs mode, use:   set -o emacs

Using vi Mode:
Once vi mode is enabled, Bash editing will be similar to working in vi/vim.

Command Mode (Press Esc to enter from Insert Mode):
In this mode, you can navigate through the command line with vi-like keys, such as:
h (move left), j (move down), k (move up), l (move right).
^ or 0 (move to the beginning of the line), $ (move to the end of the line).
w (move by word), b (move backward by word), e (move to the end of the current word).
dd (delete the current line), yy (yank/copy the current line).
p (paste), u (undo the last change), etc.

Insert Mode (Press i to enter from Command Mode):
In this mode, you can type freely like you would in a regular text editor.

"
