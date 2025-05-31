#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to download and install flazz/vim-colorschemes
# and backup existing colorschemes.
# It also lists built-in colorschemes from specific paths.

# --- Configuration ---
REPO_URL="https://github.com/flazz/vim-colorschemes.git"
TMP_CLONE_DIR="/tmp/vim-colorschemes-flazz"
BACKUP_BASE_DIR="$HOME/.backup"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

VIM_APP_NAME="vim"
NVIM_APP_NAME="nvim"

# Specific paths for built-in colorschemes
VIM_BUILTIN_COLORS_PATH="/usr/share/vim/vim90/colors" # Adjust vim90 if your version differs
NVIM_BUILTIN_COLORS_PATH="/usr/share/nvim/runtime/colors"

VIM_CONFIG_DIR_USER="$HOME/.vim"
VIM_COLORS_DIR_USER="$VIM_CONFIG_DIR_USER/colors"
VIM_BACKUP_DIR="$BACKUP_BASE_DIR/vim-colors-$TIMESTAMP"

NVIM_CONFIG_DIR_USER="$HOME/.config/nvim"
NVIM_COLORS_DIR_USER="$NVIM_CONFIG_DIR_USER/colors"
NVIM_BACKUP_DIR="$BACKUP_BASE_DIR/nvim-colors-$TIMESTAMP"

# --- Helper Functions ---
info() {
  echo -e "\033[34m[INFO]\033[0m $1"
}

warn() {
  echo -e "\033[33m[WARN]\033[0m $1"
}

error() {
  echo -e "\033[31m[ERROR]\033[0m $1" >&2
  exit 1
}

success() {
  echo -e "\033[32m[SUCCESS]\033[0m $1"
}

# --- Editor Information Functions ---

list_specific_builtin_colorschemes() {
  local editor_name="$1"
  local builtin_path="$2"

  if [ -d "$builtin_path" ]; then
    echo -n "  $editor_name built-in colorschemes are in $builtin_path: "
    local schemes
    schemes=$(ls "$builtin_path"/*.vim 2>/dev/null | sed "s#$builtin_path/##g; s#.vim##g" | sort | paste -sd ',' -)
    if [ -n "$schemes" ]; then
      echo "$schemes"
    else
      echo "No .vim files found."
    fi
  else
    info "  $editor_name built-in colorscheme path $builtin_path not found."
  fi
}

# --- Main Script ---

clear
info "Starting Vim/Neovim colorscheme enhancement process..."
echo "----------------------------------------------------"
info "Checking for built-in colorschemes in predefined paths:"

list_specific_builtin_colorschemes "Vim" "$VIM_BUILTIN_COLORS_PATH"
list_specific_builtin_colorschemes "Neovim" "$NVIM_BUILTIN_COLORS_PATH"

echo "----------------------------------------------------"
info "This script will perform the following actions:"
echo "  1. Attempt to backup existing user colorschemes from:"
echo "     - Vim:      $VIM_COLORS_DIR_USER"
echo "     - Neovim:   $NVIM_COLORS_DIR_USER"
echo "     to a timestamped directory under $BACKUP_BASE_DIR."
echo "  2. Clone the flazz/vim-colorschemes repository (containing many schemes) from:"
echo "     $REPO_URL"
echo "  3. Install these new colorschemes into:"
echo "     - Vim:      $VIM_COLORS_DIR_USER (overwriting existing if names clash)"
echo "     - Neovim:   $NVIM_COLORS_DIR_USER (if $NVIM_CONFIG_DIR_USER exists, overwriting)"
echo "  4. Clean up the temporary clone directory."
echo "----------------------------------------------------"

read -r -p "Do you want to continue? [y/N]: " response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  info "Aborted by user."
  exit 0
fi

info "Proceeding with colorscheme installation..."

# 1. Create backup base directory if it doesn't exist
if [ ! -d "$BACKUP_BASE_DIR" ]; then
  info "Creating backup directory: $BACKUP_BASE_DIR"
  mkdir -p "$BACKUP_BASE_DIR" || error "Failed to create backup directory $BACKUP_BASE_DIR"
fi

# 2. Backup existing Vim colors directory
VIM_NEEDS_INSTALL=false
if command -v "$VIM_APP_NAME" &>/dev/null; then
    VIM_NEEDS_INSTALL=true
    if [ -d "$VIM_COLORS_DIR_USER" ] && [ -n "$(ls -A "$VIM_COLORS_DIR_USER")" ]; then
      info "Backing up existing Vim colors from $VIM_COLORS_DIR_USER to $VIM_BACKUP_DIR"
      mkdir -p "$(dirname "$VIM_BACKUP_DIR")"
      cp -r "$VIM_COLORS_DIR_USER" "$VIM_BACKUP_DIR" || warn "Failed to backup Vim colors directory. Continuing..."
    else
      info "No existing user Vim colors directory found at $VIM_COLORS_DIR_USER or it's empty. Skipping backup."
    fi
else
    info "Vim ($VIM_APP_NAME) not found by 'command -v'. Skipping Vim steps."
fi


# 3. Backup existing Neovim colors directory (if Neovim config exists)
NVIM_NEEDS_INSTALL=false
if command -v "$NVIM_APP_NAME" &>/dev/null; then
    if [ -d "$NVIM_CONFIG_DIR_USER" ]; then
        NVIM_NEEDS_INSTALL=true
        if [ -d "$NVIM_COLORS_DIR_USER" ] && [ -n "$(ls -A "$NVIM_COLORS_DIR_USER")" ]; then
            info "Backing up existing Neovim colors from $NVIM_COLORS_DIR_USER to $NVIM_BACKUP_DIR"
            mkdir -p "$(dirname "$NVIM_BACKUP_DIR")"
            cp -r "$NVIM_COLORS_DIR_USER" "$NVIM_BACKUP_DIR" || warn "Failed to backup Neovim colors directory. Continuing..."
        else
            info "No existing user Neovim colors directory found at $NVIM_COLORS_DIR_USER or it's empty. Skipping backup for Neovim."
        fi
    else
        info "Neovim user config directory $NVIM_CONFIG_DIR_USER not found. Neovim schemes will not be installed to user location."
    fi
else
    info "Neovim ($NVIM_APP_NAME) not found by 'command -v'. Skipping Neovim steps."
fi

# 4. Clone the repository into /tmp/
info "Cloning $REPO_URL into $TMP_CLONE_DIR..."
if [ -d "$TMP_CLONE_DIR" ]; then
  info "Removing existing temporary clone directory: $TMP_CLONE_DIR"
  rm -rf "$TMP_CLONE_DIR"
fi
git clone --depth 1 "$REPO_URL" "$TMP_CLONE_DIR" || error "Failed to clone repository from $REPO_URL"

CLONED_COLORS_DIR="$TMP_CLONE_DIR/colors"
if [ ! -d "$CLONED_COLORS_DIR" ]; then
  error "Cloned repository does not contain a 'colors' subdirectory at $CLONED_COLORS_DIR"
fi

NUM_SCHEMES=$(find "$CLONED_COLORS_DIR" -name "*.vim" -type f | wc -l)
info "Found $NUM_SCHEMES colorschemes in the cloned repository."


# 5. Install for Vim
if [ "$VIM_NEEDS_INSTALL" = true ]; then
    info "Installing $NUM_SCHEMES colorschemes for Vim..."
    mkdir -p "$VIM_COLORS_DIR_USER" || error "Failed to create Vim colors directory: $VIM_COLORS_DIR_USER"
    info "Copying .vim files to $VIM_COLORS_DIR_USER (forcing overwrite)..."
    cp -f "$CLONED_COLORS_DIR"/*.vim "$VIM_COLORS_DIR_USER/" || error "Failed to copy colorschemes to $VIM_COLORS_DIR_USER"
    success "Vim colorschemes installed."
fi

# 6. Install for Neovim (if Neovim config exists and nvim is installed)
if [ "$NVIM_NEEDS_INSTALL" = true ]; then # This implies nvim command exists and user config dir exists
  info "Installing $NUM_SCHEMES colorschemes for Neovim..."
  mkdir -p "$NVIM_COLORS_DIR_USER" || error "Failed to create Neovim colors directory: $NVIM_COLORS_DIR_USER"
  info "Copying .vim files to $NVIM_COLORS_DIR_USER (forcing overwrite)..."
  cp -f "$CLONED_COLORS_DIR"/*.vim "$NVIM_COLORS_DIR_USER/" || error "Failed to copy colorschemes to $NVIM_COLORS_DIR_USER"
  success "Neovim colorschemes installed."
elif command -v "$NVIM_APP_NAME" &>/dev/null && [ ! -d "$NVIM_CONFIG_DIR_USER" ]; then
    info "Neovim is installed, but user config directory $NVIM_CONFIG_DIR_USER was not found. New schemes not installed for Neovim user."
fi

# 7. Cleanup temporary clone directory
info "Cleaning up temporary clone directory: $TMP_CLONE_DIR"
rm -rf "$TMP_CLONE_DIR"

echo "----------------------------------------------------"
success "Colorscheme installation process completed!"
echo "Your Vim/Neovim should now include approximately $NUM_SCHEMES new themes from flazz/vim-colorschemes in your user color directories."
echo "Previous user themes (if any) are backed up in $BACKUP_BASE_DIR"
echo "You might need to restart Vim/Neovim to see the new themes."
