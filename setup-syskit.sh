#!/bin/bash
# Author: Roy Wiseman 2025-05
# Wrapper script to invoke the add-paths, bashrc, and vimrc update scripts

# Prevent the script from running if not sourced
(return 0 2>/dev/null) || {
    echo "
This script must be sourced.
e.g.,   . ${0##*/}
or      source ${0##*/}

This will setup the following:
- ./0-new-system/new1-vimrc.sh      : Add essential definitions for vim and neovim
- ./0-new-system/new2-update-h-scripts.sh : Markdown help files, use h-<tab> to view
- ./0-new-system/new1-bashrc.sh     : Add essential definitions to ~/.bashrc
- ./0-new-system/new1-add-paths.sh  : Add path for 0-scripts to PATH
"
    exit 1
}

SCRIPT_PATH="$HOME/syskit/0-new-system/new1-vimrc.sh"

if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

SCRIPT_PATH="$HOME/syskit/0-new-system/new1-update-h-scripts.sh"

if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

SCRIPT_PATH="$HOME/syskit/0-new-system/new1-bashrc.sh"

if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH" --clean
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

# If new1-bashrc.sh is run *after* add-paths, then the paths will be deleted!
SCRIPT_PATH="$HOME/syskit/0-new-system/new1-add-paths.sh"

if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

