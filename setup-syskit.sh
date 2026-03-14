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
- ./0-new-system/new1-update-h-scripts.sh : Markdown help files, use h-<tab> to view
- ./0-new-system/new1-bashrc.sh     : Add essential definitions to ~/.bashrc
- ./0-new-system/new1-add-paths.sh  : Add syskit/0-scripts and /0-help to PATH
"
    exit 1
}

# Get the directory where this script is located
# Use a unique variable name to avoid collisions when sourcing sub-scripts
_SYSKIT_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# 1. Vim RC (Does not need sourcing as it only modifies files)
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-vimrc.sh"
if [ -x "$SCRIPT_PATH" ]; then
    "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

# 2. Update H Scripts (Does not need sourcing)
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-update-h-scripts.sh"
if [ -x "$SCRIPT_PATH" ]; then
    "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

# 3. Bash RC (MUST be sourced to update current session)
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-bashrc.sh"
if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH" --clean
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

# 4. Add Paths (MUST be sourced to update current session)
# If new1-bashrc.sh is run *after* add-paths, then the paths will be deleted!
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-add-paths.sh"
if [ -x "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH"
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
fi

