#!/bin/zsh
# Author: Roy Wiseman 2025-05
# Wrapper script to invoke the add-paths, zshrc, and vimrc update scripts for Zsh users (macOS/Linux)

# Prevent the script from running if not sourced
# Zsh: $0 equals $ZSH_ARGZERO only when the file is run as a script
if [[ $0 == $ZSH_ARGZERO ]]; then
    echo "
This script must be sourced.
e.g.,   . ${0##*/}
or      source ${0##*/}

This will setup the following:
- ./0-new-system/new1-vimrc.sh      : Add essential definitions for vim and neovim
- ./0-new-system/new1-update-h-scripts.sh : Markdown help files, use h-<tab> to view
- ./0-new-system/new1-zshrc.sh      : Add essential definitions to ~/.zshrc
- (Built-in)                        : Add /0-scripts and /0-help to PATH
"
    exit 1
fi

SCRIPT_DIR=${0:a:h} # Get absolute path of script directory in Zsh

# Steps that fail are recorded here and reported at the end
FAILED=()

# Ensure /usr/local/bin exists (common issue on clean macOS)
if [[ ! -d "/usr/local/bin" ]]; then
    echo "Directory /usr/local/bin does not exist. Creating it (requires sudo)..."
    sudo mkdir -p "/usr/local/bin"
fi

# 1. Vim RC: the macOS version on macOS, the general version everywhere else
if [[ "$(uname)" == "Darwin" ]]; then
    VIMRC_SCRIPT="$SCRIPT_DIR/0-new-system/new1-vimrc-macos.sh"
else
    VIMRC_SCRIPT="$SCRIPT_DIR/0-new-system/new1-vimrc.sh"
fi
if [[ -x "$VIMRC_SCRIPT" ]]; then
    "$VIMRC_SCRIPT" || FAILED+=("vimrc")
else
    echo "Error: Script $VIMRC_SCRIPT not found or not executable."
    FAILED+=("vimrc")
fi

# 2. Update H Scripts
SCRIPT_PATH="$SCRIPT_DIR/0-new-system/new1-update-h-scripts.sh"
if [[ -x "$SCRIPT_PATH" ]]; then
    "$SCRIPT_PATH" || FAILED+=("h-scripts")
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
    FAILED+=("h-scripts")
fi

# 3. Zsh RC (The new zsh script)
SCRIPT_PATH="$SCRIPT_DIR/0-new-system/new1-zshrc.sh"
if [[ -x "$SCRIPT_PATH" ]]; then
    "$SCRIPT_PATH" --clean || FAILED+=("zshrc")
else
    echo "Error: Script $SCRIPT_PATH not found or not executable."
    FAILED+=("zshrc")
fi

# 4. Add Paths (Integrated logic)
# Add ~/syskit to PATH in both current session and .zshrc
add_to_path() {
  local DIR="$1"
  # Resolve absolute path
  # Zsh modifiers :a :h etc are great.
  local ABS_DIR="${DIR:a}"

  # Add to current session
  if [[ ":$PATH:" != *":$ABS_DIR:"* ]]; then
      echo "Adding $ABS_DIR to PATH for the current session..."
      export PATH="$ABS_DIR:$PATH"
  else
      echo "$ABS_DIR is already in the PATH for the current session."
  fi

  # Ensure it's added to .zshrc
  local PROFILE_FILE="$HOME/.zshrc"
  # Check if exactly this export exists
  if ! grep -qxF "export PATH=\"$ABS_DIR:\$PATH\"" "$PROFILE_FILE"; then
    echo "Adding $ABS_DIR to PATH in $PROFILE_FILE..."
    echo "export PATH=\"$ABS_DIR:\$PATH\"" >> "$PROFILE_FILE"
  else
    echo "$ABS_DIR is already in $PROFILE_FILE (file check)."
  fi
}

echo "Updating PATHs..."
# Clean path duplicates in current session unique
typeset -U path
# path is the array tied to PATH in zsh, -U makes it keep unique values.

# Add syskit paths
add_to_path "$SCRIPT_DIR"
add_to_path "$SCRIPT_DIR/0-scripts"
add_to_path "$SCRIPT_DIR/0-help"

if (( ${#FAILED[@]} )); then
    echo -e "\n\033[1;31mSetup finished with errors in: ${FAILED[*]}\033[0m" >&2
    return 1
fi
echo -e "\n\033[1;32mSuccess!\033[0m Syskit Zsh setup complete."
