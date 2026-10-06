#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script is for bash 4+ (macOS ships bash 3.2: brew install bash). If you use zsh, source setup-syskit-zsh.sh instead." >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05
# Wrapper script to invoke the add-paths, bashrc, and vimrc update scripts

# Prevent the script from running if not sourced
(return 0 2>/dev/null) || {
    echo "
This script must be sourced.
e.g.,   . ${0##*/}
or      source ${0##*/}

This will setup the following (paths are relative to the syskit folder):
- ./0-new-system/new1-vimrc.sh      : Add essential definitions for vim and neovim
- ./0-new-system/new1-update-h-scripts.sh : Markdown help files, use h-<tab> to view
- ./0-new-system/new1-bashrc.sh     : Add essential definitions to ~/.bashrc
                                      (includes interactive aliases: rm, cp, mv use -i)
- ./0-new-system/new1-add-paths.sh  : Add syskit/0-scripts and /0-help to PATH
"
    exit 1
}

# Get the directory where this script is located
# Use a unique variable name to avoid collisions when sourcing sub-scripts
_SYSKIT_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Steps that fail are recorded here and reported at the end
FAILED=()

# 1. Vim RC (Does not need sourcing as it only modifies files)
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-vimrc.sh"
if [ -x "$SCRIPT_PATH" ]; then
    "$SCRIPT_PATH" || FAILED+=("vimrc")
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
    FAILED+=("vimrc")
fi

# 2. Update H Scripts (Does not need sourcing)
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-update-h-scripts.sh"
if [ -x "$SCRIPT_PATH" ]; then
    "$SCRIPT_PATH" || FAILED+=("h-scripts")
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
    FAILED+=("h-scripts")
fi

# 3. Bash RC (MUST be sourced to update current session)
# Sourced files only need to be readable, so test -f, not -x
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-bashrc.sh"
if [ -f "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH" --clean || FAILED+=("bashrc")
else
    echo "Error: Script $SCRIPT_PATH not found."
    FAILED+=("bashrc")
fi

# 4. Add Paths (MUST be sourced to update current session)
# If new1-bashrc.sh is run *after* add-paths, then the paths will be deleted!
SCRIPT_PATH="$_SYSKIT_SETUP_DIR/0-new-system/new1-add-paths.sh"
if [ -f "$SCRIPT_PATH" ]; then
    . "$SCRIPT_PATH" || FAILED+=("add-paths")
else
    echo "Error: Script $SCRIPT_PATH not found."
    FAILED+=("add-paths")
fi

unset _SYSKIT_SETUP_DIR

if (( ${#FAILED[@]} )); then
    echo -e "\n\033[1;31mSetup finished with errors in: ${FAILED[*]}\033[0m" >&2
    return 1 2>/dev/null
fi
echo -e "\n\033[1;32mSuccess!\033[0m Syskit bash setup complete."
