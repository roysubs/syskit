#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02
set -euo pipefail

VIMRC="$HOME/.vimrc"
PLUGGED_DIR="$HOME/.vim/plugged"
PLUG_BLOCK="call plug#begin('$PLUGGED_DIR')"
GITGUTTER_LINE="Plug 'airblade/vim-gitgutter'"
GITGUTTER_SETTINGS=$(cat <<'EOF'
" GitGutter visual settings
let g:gitgutter_sign_added = '+'
let g:gitgutter_sign_modified = '~'
let g:gitgutter_sign_removed = '_'
set signcolumn=yes
EOF
)

function explain_usage {
  cat <<EOF

📘 HOW TO USE GitGutter IN VIM:

1. Open a file inside a Git repository.
2. Make sure the file is committed at least once (e.g. with \`git commit -m "init"\`).
3. Now edit the file — GitGutter will show:
     +   for added lines
     ~   for modified lines
     _   for deleted lines

📌 Commands inside Vim:
   :GitGutter        — manually refresh signs
   :GitGutterAll     — refresh all open files
   :GitGutterDebug   — shows internal GitGutter state

🔧 Optional (already added to .vimrc):
   - Uses '+' / '~' / '_' signs
   - Ensures sign column is always visible

EOF
}

function ask_toggle {
  if grep -q "$GITGUTTER_LINE" "$VIMRC"; then
    echo "GitGutter appears to be INSTALLED."
    read -rp "Do you want to UNINSTALL GitGutter? [y/N]: " choice
    [[ "$choice" == [yY]* ]] || exit 0
    uninstall
  else
    echo "GitGutter appears to be NOT installed."
    read -rp "Do you want to INSTALL GitGutter? [y/N]: " choice
    [[ "$choice" == [yY]* ]] || exit 0
    install
  fi
}

function install_vim_plug {
  if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
    echo "Installing vim-plug..."
    curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  else
    echo "vim-plug already installed."
  fi
}

function install {
  install_vim_plug
  echo "Adding plug#begin()/end() block and GitGutter to .vimrc..."

  if ! grep -q "$PLUG_BLOCK" "$VIMRC"; then
    echo -e "\n$PLUG_BLOCK" >> "$VIMRC"
    echo "$GITGUTTER_LINE" >> "$VIMRC"
    echo "call plug#end()" >> "$VIMRC"
  elif ! grep -q "$GITGUTTER_LINE" "$VIMRC"; then
    # sed -i "/$PLUG_BLOCK/a $GITGUTTER_LINE" "$VIMRC"
    sed -i "\|$PLUG_BLOCK|a\\
$GITGUTTER_LINE" "$VIMRC"

  fi

  # Add GitGutter symbols + signcolumn
  if ! grep -q "g:gitgutter_sign_added" "$VIMRC"; then
    echo -e "\n$GITGUTTER_SETTINGS" >> "$VIMRC"
  fi

  echo "Installing GitGutter via vim-plug..."
  vim +PlugInstall +qall

  echo -e "\n✅ GitGutter installed!"
  explain_usage
}

function uninstall {
  echo "Removing GitGutter from .vimrc..."

  # sed -i "/$GITGUTTER_LINE/d" "$VIMRC"
  sed -i "\|Plug 'airblade/vim-gitgutter'|d" "$VIMRC"
  sed -i '/g:gitgutter_sign_added/d' "$VIMRC"
  sed -i '/g:gitgutter_sign_modified/d' "$VIMRC"
  sed -i '/g:gitgutter_sign_removed/d' "$VIMRC"
  sed -i '/signcolumn=yes/d' "$VIMRC"

  echo "Cleaning plugins..."
  vim +PlugClean! +qall

  echo -e "\n🗑️ GitGutter uninstalled."
}

ask_toggle

