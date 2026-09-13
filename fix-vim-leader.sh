#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
VIMRC="$HOME/.vimrc"
echo "Fixing Leader Key in $VIMRC..."

# Check if mapleader is set
if ! grep -q "let mapleader" "$VIMRC"; then
    echo "adding mapleader definition..."
    # Create temp file with header
    {
        echo 'set nocompatible       " Use Vim defaults instead of Vi compatibility'
        echo 'let mapleader = "\\"   " Set Leader key to backslash explicitly'
        echo ''
        cat "$VIMRC"
    } > "${VIMRC}.tmp" && mv "${VIMRC}.tmp" "$VIMRC"
    echo "Fixed: Prepend mapleader definition."
else
    echo "Check: mapleader already defined."
fi

# Check if mappings exist
if ! grep -q "<Leader>n" "$VIMRC"; then
    echo "Adding fallback mappings..."
    cat <<EOF >> "$VIMRC"

" --- macOS / Layout Friendly Fallbacks ---
nnoremap <Leader>n :set invnumber<CR>
nnoremap <Leader>w :set wrap!<CR>
nnoremap <Leader>h :call ToggleHiddenAndStatusBar()<CR>
EOF
    echo "Fixed: Appended mappings."
else
    echo "Check: Mappings already present."
fi

echo "Done. Please restart Vim."
