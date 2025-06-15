#!/bin/bash
# Author: Roy Wiseman 2025-02

# Check and update ~/.vimrc and ~/.config/nvim/init.vim line by line
# Only add a line if it is not currently present.
# Adds bindings to both Vim and Neovim (nvim)
# Designed to be run by the user whose configuration is being modified.
# Automatically detects common Linux package managers (apt, apk, dnf, yum, pacman, zypper).

echo "Starting Vim/Neovim configuration update..."

# Function to install a package and verify its executable
# Args:
#   $1: pkg_name (Name of the package to install, e.g., "neovim")
#   $2: exec_name (Name of the command executable provided by the package, e.g., "nvim")
install_package() {
    local pkg_name="$1"
    local exec_name="$2"

    if [ -z "$pkg_name" ] || [ -z "$exec_name" ]; then
        echo "Error: install_package requires both package name and executable name."
        return 1
    fi

    echo "Ensuring package '$pkg_name' (providing '$exec_name') is installed..."

    # Check if executable is already installed before attempting install
    if command -v "$exec_name" &> /dev/null; then
        echo "'$exec_name' (from package '$pkg_name') is already available."
        return 0 # Executable already found
    fi

    echo "'$exec_name' not found. Attempting to install package '$pkg_name'..."

    # Determine installation commands based on package manager
    if command -v apt &> /dev/null; then
        echo "Using apt"
        if ! sudo apt update || ! sudo apt install -y "$pkg_name"; then
             echo "Error: apt installation of '$pkg_name' failed."
             return 1 # Indicate apt failure
        fi
    elif command -v apk &> /dev/null; then
        echo "Using apk"
        if ! sudo apk update || ! sudo apk add --no-cache "$pkg_name"; then
             echo "Error: apk installation of '$pkg_name' failed."
             return 1 # Indicate apk failure
        fi
    elif command -v dnf &> /dev/null; then
        echo "Using dnf"
        sudo dnf check-update || true # Ignore check-update errors
        if ! sudo dnf install -y "$pkg_name"; then
             echo "Error: dnf installation of '$pkg_name' failed."
             return 1 # Indicate dnf failure
        fi
    elif command -v yum &> /dev/null; then
        echo "Using yum"
        sudo yum check-update || true # Ignore check-update errors
        if ! sudo yum install -y "$pkg_name"; then
             echo "Error: yum installation of '$pkg_name' failed."
             return 1 # Indicate yum failure
        fi
    elif command -v pacman &> /dev/null; then
        echo "Using pacman"
        if ! sudo pacman -Sy --noconfirm || ! sudo pacman -S --noconfirm "$pkg_name"; then
             echo "Error: pacman installation of '$pkg_name' failed."
             return 1 # Indicate pacman failure
        fi
    elif command -v zypper &> /dev/null; then
        echo "Using zypper"
        if ! sudo zypper refresh || ! sudo zypper install -y "$pkg_name"; then
             echo "Error: zypper installation of '$pkg_name' failed."
             return 1 # Indicate zypper failure
        fi
    else
        echo "Error: Could not detect a supported package manager."
        echo "Please install package '$pkg_name' (providing command '$exec_name') manually."
        return 1 # Indicate failure
    fi

    # Verify installation success by checking for the executable
    if command -v "$exec_name" &> /dev/null; then
        echo "'$pkg_name' installed successfully ('$exec_name' is available)."
        return 0 # Success
    else
        echo "Error: Failed to find '$exec_name' command after installing '$pkg_name'."
        echo "Manual intervention may be required to install package '$pkg_name'."
        return 1 # Indicate failure
    fi
}


# --- Package Installation ---

# Install vim and neovim - exit if either fails
# Use the correct package names and executable names
install_package "vim" "vim" || { echo "Aborting due to failed vim installation."; exit 1; }
install_package "neovim" "nvim" || { echo "Aborting due to failed neovim installation."; exit 1; }

# --- Ensure configuration files and directories exist ---

# Ensure Vim config file exists
vimrc_file="$HOME/.vimrc"
echo "Ensuring Vim configuration file exists..."
if [ ! -f "$vimrc_file" ]; then
    touch "$vimrc_file"
    echo "Created new $vimrc_file."
fi


# Ensure Neovim config directory and init.vim file exist
echo "Ensuring Neovim configuration directory exists..."
mkdir -p "$HOME/.config/nvim"
nvim_init_file="$HOME/.config/nvim/init.vim"
if [ ! -f "$nvim_init_file" ]; then
    touch "$nvim_init_file"
    echo "Created new $nvim_init_file."
fi


# --- Vim settings and key mappings to apply ---
vimrc_block="
syntax on              \" Syntax highlighting
colorscheme desert     \" Syntax highlighting scheme
\" Available themes: blue, darkblue, default, delek, desert, elflord, evening, habamax, industry, koehler
\" lunapeche lunaperche, morning, murphy, pablo, peachpuff, quiet, ron, shine, slate, torte, zellner
\" Disable tabs (to get a tab, Ctrl-V<Tab>), tab stops are 4 chars, indents are 4 chars
\" Set tab behavior to use spaces instead of tabs

set expandtab          \" Use spaces instead of tab characters
set tabstop=4          \" Set tab width to 4 spaces
set shiftwidth=4       \" Set indent width to 4 spaces
set softtabstop=4      \" Set the number of spaces a tab character represents in insert mode
set smarttab           \" Tab and Delete respect tab width stops throughout document
filetype plugin indent on   \" Enable built-in filetype detection, plugins, and indent rules
set autoindent         \" Auto and smart indent settings

inoremap <C-s> <Esc>:w<CR>            \" Save file while in insert mode
\" Perform :w write on a protected file even when not as sudo
cnoremap w!! execute 'silent! write !sudo tee % >/dev/null' <bar> edit

set background=dark  \" Dark background
set noerrorbells     \" Disable error bells
set novisualbell     \" Disable error screen flash
set t_vb=            \" Disable all bells
if has('termguicolors')     \" Check if 24-bit colors are available
    set termguicolors       \" Enable 24-bit RGB colors if available
    let &t_SI = \"\\e[6 q\" \" Set cursor to a steady underline in Insert mode
    let &t_SR = \"\\e[4 q\" \" Set cursor to a steady underline in Replace mode
    let &t_EI = \"\\e[2 q\" \" Set cursor to a steady block in Normal mode (often default)
endif

\" --- Visual Mode Enhancements ---
\" <C-v> is generally unavailable when connected by a terminal emulator so <C-q> was
\" also added as a core vim default due to common terminals using <C-v> but neither
\" are ideal to use. To provide options similar to Notepad++ and VS Code can make it
\" easier / more intuitive when switching between editors, but multi-key selections
\" in Vim are complex (require plugins), so we will map as follows:
\"
\" Shift+Right/Left => Visual character-wise, select the word under the cursor
\"       Replaces word jump function, but this is redundant as Ctrl+Right/Left already does
\" Shift+Up/Down     => Visual line-wise, select current and one more line
\"       Replaces half-page-up/down function, but redundant as just use PgUp/PgDn
\" Alt+Up/Down/Left/Right  => Visual block-wise, select rectangle as move around.
\" Avoiding Ctrl+Left/Right, leaving those as default navigate word actions.
\"
\" This setup works well with tmux (but not byobu, so avoid byobu).
\" Note: The default keys 'v' (Visual Character-wise) and 'V' (Visual Line-wise)
\" still work as usual and are not affected by these mappings.
\" Also add 'vb' as a key entry to go with 'v' and 'V'
nnoremap vb <C-q>  \" vb -> Enter block-wise visual mode (equivalent to 'Ctrl-v' / 'Ctrl-q')
\" So, v (VISUAL), V (VISUAL LINE), vb (VISUAL BLOCK)

\" --- Map Shift+Right and Shift+Left for Visual Word Selection ---
\" These mappings will override the default word-jumping behaviour (W and B for Normal mode) as that already
\" exists with Ctrl+Right/Left.
\" The original W and B jumps are still available directly in Normal mode.
\" Shift+Right: Select word under/after cursor
\" In Normal mode: Enter visual mode (v), move one word forward (w). Selects from cursor to start of next word.
nmap <S-Right> vw
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (vw).
imap <S-Right> <Esc>vw
\" Shift+Left: Select word under/before cursor
\" In Normal mode: Jump back one word (b), enter visual mode (v), select inner word (iw).
\" Selects the word you just jumped back into/past.
nmap <S-Left> bviw
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (bviw).
imap <S-Left> <Esc>bviw
\" In Visual mode (vmap): Do NOT remap <S-Right> and <S-Left>.
\" Their default behaviour (extending selection by WORD forwards/backwards) is useful
\" and aligns with extending a word-based selection.

\" --- Map Shift+Home and Shift+End for Visual Line Start/End Selection ---
\" Shift+Home: Visual select from cursor to beginning of line
\" In Normal mode: Enter visual mode (v), move to start of line (0).
nmap <S-Home> v0
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (v0).
imap <S-Home> <Esc>v0
\" In Visual mode (vmap): Move to start of line (0). Selection extends automatically.
vmap <S-Home> 0

\" Shift+End: Visual select from cursor to end of line
\" In Normal mode: Enter visual mode (v), move to end of line ($).
nmap <S-End> v$
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (v$).
imap <S-End> <Esc>v$
\" In Visual mode (vmap): Move to end of line ($). Selection extends automatically.
vmap <S-End> $

\" --- Map Alt+Up and Alt+Down for Visual Block-wise Selection ---
\" <C-o> drops back to Insert mode after each step, cancelling selection, so use <Esc> to
\" leave Insert mode permanently when starting selection, and vmap for continuous selection.
\" Alt+Up in Insert mode: Exit Insert, Enter Block Visual, Move Up.
\" <Esc>: Exit Insert mode permanently. <C-v>: Enter block-wise Visual mode.
\" k: Move cursor up (extends selection in Visual mode).
inoremap <M-Up> <Esc><C-v>k
\" Alt+Down in Insert mode: Exit Insert, Enter Block Visual, Move Down.
\" <Esc>: Exit Insert mode permanently. <C-v>: Enter block-wise Visual mode.
\" j: Move cursor down (extends selection in Visual mode).
inoremap <M-Down> <Esc><C-v>j
\" Now, handle Alt+Up/Down when already in Normal or Visual mode.
\" If you're already in Normal mode, just go straight to Visual Block and move.
\" If you're already in ANY Visual mode (char, line, or block), just perform the move,
\" which will extend the current selection.
\" Alt+Up in Normal mode: Enter Block Visual, Move Up.
nmap <M-Up> <C-v>k
\" Alt+Down in Normal mode: Enter Block Visual, Move Down.
nmap <M-Down> <C-v>j
\" Alt+Up in Visual mode (any type): Just move Up. Selection extends automatically.
vmap <M-Up> k
\" Alt+Down in Visual mode (any type): Just move Down. Selection extends automatically.
vmap <M-Down> j

\" --- Map Shift+Up and Shift+Down for Visual Line-wise Selection ---
\" Overrides default half-page scrolling behavior for <S-Up>/<S-Down>
\" Shift+Up in Insert mode: Exit Insert, Enter Line Visual, Select Line Above
\" <Esc>: Exit Insert mode permanently.
\" V: Enter Line-wise Visual mode.
\" k: Move cursor up. When in Line Visual mode, this extends the selection to the line above.
inoremap <S-Up> <Esc>Vk
\" Shift+Down in Insert mode: Exit Insert, Enter Line Visual, Select Line Below
\" <Esc>: Exit Insert mode permanently.
\" V: Enter Line-wise Visual mode.
\" j: Move cursor down. When in Line Visual mode, this extends the selection to the line below.
inoremap <S-Down> <Esc>Vj
\" Shift+Up in Normal mode: Enter Line Visual, Select Line Above
\" V: Enter Line-wise Visual mode.
\" k: Move cursor up.
nmap <S-Up> Vk
\" Shift+Down in Normal mode: Enter Line Visual, Select Line Below
\" V: Enter Line-wise Visual mode.
\" j: Move cursor down.
nmap <S-Down> Vj
\" Shift+Up in Visual mode (any type): Move Selection Up by a Line
\" When you are already in Visual mode and press S-Up, just move up.
\" In line-wise visual, this reduces the bottom boundary or extends the top boundary.
vmap <S-Up> k
\" Shift+Down in Visual mode (any type): Move Selection Down by a Line
\" When you are already in Visual mode and press S-Down, just move down.
\" In line-wise visual, this extends the bottom boundary or reduces the top boundary.
vmap <S-Down> j

\" --- Map Shift+PgUp and Shift+PgDown for Visual Line-wise Selection ---
\" Shift + PgUp: Enter visual line select and scroll up a page
\" In Normal mode: Enter Visual Line mode (V), then scroll page up (<C-B>)
nnoremap <S-PageUp> V<C-B>
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (V<C-B>)
inoremap <S-PageUp> <Esc>V<C-B>
\" In Visual mode: Just scroll page up (<C-B>), selection extends automatically
vmap <S-PageUp> <C-B>
\" Shift + PgDn: Enter visual line select and scroll down a page
\" In Normal mode: Enter Visual Line mode (V), then scroll page down (<C-F>)
nnoremap <S-PageDown> V<C-F>
\" In Insert mode: Exit Insert mode (<Esc>), then do the Normal mode action (V<C-F>)
inoremap <S-PageDown> <Esc>V<C-F>
\" In Visual mode: Just scroll page down (<C-F>), selection extends automatically
vmap <S-PageDown> <C-F>

\" --- TAB Key Enhancements ---
\" In normal mode, a TAB should go into insert mode, insert a tab, then go back to normal mode.
\" This provides a quick way to insert a tab without staying in insert mode.
nnoremap <Tab> i<Tab><Esc>

\" In visual mode, a TAB should indent the selected block using the standard '>' command,
\" and then re-select the same area using 'gv'.
vmap <Tab> >gv

\" Shift + Tab: Dedent selected lines/block ONLY in Visual mode
\" Applies to Visual Character, Visual Line, and Visual Block modes.
\" Uses the '<' command for dedent, then 'gv' to re-select the block.
vmap <S-Tab> <gv

\" Toggle line numbers with F2 or Ctrl+L
set nonumber    \" Start with no line numbers when starting Vim
nnoremap <C-L> :set invnumber<CR>
inoremap <C-L> <Esc>:set invnumber<CR>a
nnoremap <F2> :set invnumber<CR>
inoremap <F2> <Esc>:set invnumber<CR>a
\" Toggle line wrap with F3
nnoremap <F3> :set wrap!<CR>
inoremap <F3> <Esc>:set wrap!<CR>a
\" Toggle 'list' (invisible characters) AND 'laststatus' (statusline) with F4
set laststatus=0        \" Start vim sessions with statusline hidden
set statusline=         \" Set up a custom statusline (used to be only when laststatus is activated)
set statusline+=%F      \" Add Full file path
set statusline+=%m      \" Add Modified flag [+]
set statusline+=%r      \" Add Readonly flag
set statusline+=%h      \" Add Help file flag
set statusline+=%w      \" Add Preview window flag
set statusline+=\\ [FORMAT=%{&ff}]   \" Add File format: unix/dos/mac
set statusline+=\\ [ENC=%{&enc}]     \" Add Encoding (e.g., utf-8)
set statusline+=\\ [TYPE=%Y]         \" Add File type (e.g., sh, conf)
set statusline+=\\ %l/%L             \" Add Current line / total lines
set statusline+=\\ %P                \" Add Percentage through file
\" \" Enable 'list' and 'laststatus' via F4 in normal or insert mode
\" nnoremap <F4> :set list! listchars=tab:→\\ ,trail:·,eol:¶<CR>
\"         \\ :let &laststatus = (&laststatus == 0 ? 2 : 0)<CR>
\"         \\ :echo \"Hidden chars \" . (&list ? \"ON\" : \"OFF\") . \", Statusline \" . (&laststatus == 2 ? \"ON\" : \"OFF\")<CR>
\" inoremap <F4> <Esc>:set list! listchars=tab:→\ ,trail:·,eol:¶<CR> \
\"         \\ :let &laststatus = (&laststatus == 0 ? 2 : 0)<CR> \
\"         \\ :echo \"Hidden chars \" . (&list ? \"ON\" : \"OFF\") . \", Statusline \" . (&laststatus == 2 ? \"ON\" : \"OFF\")<CR>a

function! ToggleHiddenAndStatusBar()
    \" Toggle the 'list' setting to show/hide hidden characters
    set list!

    \" Set the characters to use for tabs, trailing spaces, etc.
    \" The '\ ' here correctly sets the tab to be an arrow plus a space.
    set listchars=tab:→\ ,trail:·,eol:¶

    \" Toggle the statusline. 0=default, 1=never, 2=always.
    let &laststatus = (&laststatus == 0 ? 2 : 0)

    \" Echo the current state to the command line
    echo \"Hidden chars \" . (&list ? \"ON\" : \"OFF\") . \", Statusline \" . (&laststatus == 2 ? \"ON\" : \"OFF\")
endfunction

nnoremap <F4> :call ToggleHiddenAndStatusBar()<CR>
inoremap <F4> <Esc>:call ToggleHiddenAndStatusBar()<CR>a

"

# \" Alternatively, to just do 'list' on F4:
# nnoremap <F4> :set list! listchars=tab:→\\ ,trail:·,eol:¶<CR>

# Having problems with persistent undo (global undo history between sessions), so leaving off for now
# \" Enable persistent undo, so that undo will operate between different edit sessions of files
# set undofile
# \" Set the directory where undo files will be stored
# \" Create this directory if it doesn't exist
# \" Use a path within your home directory
# set undodir=\$HOME/.vim/undodir,\$HOME/.config/nvim/undodir,/tmp/undodir
# \" Optional: Set undolevels to -1 for potentially unlimited undo history (disk space permitting)
# \" set undolevels=-1
# \" There is no way to cycle old undos, so be cautious with very large files and histories, as this can consume disk space.
# \" Periodically clean, e.g. remove anything older than 90 days:   find /home/boss/.vim/undodir -type f -mtime +90 -delete

# Neovim-specific settings block
nvim_block="
\" Neovim-specific settings
\" Disable mouse support if it's causing issues in your terminal/container
set mouse=
"

# Function to update a target configuration file by adding missing lines (Revised & Corrected Blank Removal)
# This version reads existing content, combines with new block, filters for unique lines, and writes.
update_config_file() {
    local target_file="$1"
    local config_block="$2"
    echo "Updating $target_file..."

    local temp_file=$(mktemp)
    # Read existing content robustly. Use '|| true' in case cat fails (e.g. file didn't exist, though touch should prevent this)
    # Redirect stderr to /dev/null in case cat complains about empty file or non-existent file (less likely after touch)
    local current_content
    if [ -f "$target_file" ]; then
      current_content=$(cat "$target_file")
    else
      current_content=""
    fi


    # Combine existing content with the new block, filter for unique lines, and clean internal/leading blanks
    # Remove blank lines first, then filter for unique lines
    {
        echo "$current_content"
        echo "$config_block"
    } | grep -v '^[[:space:]]*$' | awk '!x[$0]++' > "$temp_file" # Remove blank lines, then remove duplicates

    # --- DEBUG: Show temporary file content (after unique+blank filtering) ---
    echo "--- Content of temporary file ($temp_file) after processing ---"
    cat "$temp_file"
    echo "-------------------------------------------------"
    # --- End Debug ---

    # Remove trailing blank lines using corrected logic
    # This will remove *all* blank lines from the end of the file.
    # Ensure the temporary file is not empty before processing
    if [ -s "$temp_file" ]; then # Check if temp_file is not empty
        tac "$temp_file" | sed '/^[[:space:]]*$/d' | tac > "${temp_file}.cleaned" # Corrected: Removed 'q'
        command mv "${temp_file}.cleaned" "$temp_file" # Move cleaned back to temp_file
    fi


    # Replace the original file with the updated content from the temporary file
    # The original file is guaranteed to exist (or be created by the initial touch)
    command mv "$temp_file" "$target_file"

    echo "Finished processing $target_file."
}


# --- Apply settings to user configuration files ---

# Ensure Vim config file exists
vimrc_file="$HOME/.vimrc"
echo "Ensuring Vim configuration file exists..."
if [ ! -f "$vimrc_file" ]; then
    touch "$vimrc_file"
    echo "Created new $vimrc_file."
fi
# Update the user's vimrc located in their home directory
echo "Processing $vimrc_file..."
# --- Call to update_config_file ---
update_config_file "$vimrc_file" "$vimrc_block"

# Ensure Neovim config directory and init.vim file exist
echo "Ensuring Neovim configuration directory exists..."
mkdir -p "$HOME/.config/nvim"
nvim_init_file="$HOME/.config/nvim/init.vim"
if [ ! -f "$nvim_init_file" ]; then
    touch "$nvim_init_file"
    echo "Created new $nvim_init_file."
fi

# Update the user's nvim init.vim - Apply vimrc_block first, then nvim_block
echo "Processing $nvim_init_file..."
# First pass: Add common vimrc_block settings
# --- Call to update_config_file ---
update_config_file "$nvim_init_file" "$vimrc_block"
# Second pass: Add Neovim-specific settings
# --- Call to update_config_file ---
update_config_file "$nvim_init_file" "$nvim_block"


echo -e "\nConfiguration update complete! Reopen vi/vim/nvim to see the updates."



# Simplified code logic:
# 
# # Inside update_config_file (Stream Processing Approach)
# # Read *all* existing content ONCE
# local current_content=$(cat "$target_file" 2>/dev/null || true)
# 
# # Combine, filter, unique, and redirect to temp_file
# {
#     echo "$current_content" # Put existing content into the stream
#     echo "$config_block"    # Append new block into the stream
# } | grep -v '^[[:space:]]*$' | awk '!x[$0]++' > "$temp_file"
# # Stream: existing lines + new lines -> remove blanks -> remove duplicates -> temp_file
# 
# # ... corrected blank removal and mv $temp_file ...
#
# Why Stream Processing is Generally Better Here:
# 
# Efficiency: It reads the original file only once. The filtering and unique processing are handled very efficiently by standard Unix pipeline tools (grep, awk) designed for this. This is much faster than repeatedly calling grep on the file.
# Robustness: This approach relies on the fundamental Unix principle of processing streams of text through pipelines. It avoids the potential instability or inefficiency of repeatedly accessing the file from within a loop for checks. awk '!x[$0]++' is a standard and reliable method for obtaining unique lines.
# Simplicity of Logic: Although the command string looks complex, the logic is straightforward: collect all lines, clean blanks, keep only unique ones. This replaces the more complex state management (appending to a temp file while checking against the original) and the problematic line-by-line grep calls.
# Handles Edge Cases Better: It naturally handles cases where the original file is empty (the cat outputs nothing, the pipeline just processes the new block) and ensures that duplicates between existing and new lines are removed.
# In your case, the stream processing approach likely worked because it circumvented the specific issues you were facing with repeated file access or cat's behavior in your container environment by reading the original content once and performing the filtering in a standard pipeline. Combined with the corrected blank line removal, it produced the desired, correct configuration file content.
