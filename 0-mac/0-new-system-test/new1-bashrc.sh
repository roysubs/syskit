#!/bin/bash
# Author: Roy Wiseman 2025-01

# Each line in 'bashrc_block' will be tested against .bashrc
# If that item exists with a different value, it will not alter it
# so by design does not mess up existing configurations (it just
# adds any elements not covered to the end of .bashrc).
#
# e.g. if 'export EDITOR=' is set (to vi or emacs or nano) the
# export EDITOR= line in here will not be added and the existing
# line will not be altered.
#
# Multi-line functions are treated as a single block; again, if a
# function with that name already exists, this script will not modify
# that, and will not add the new entry. Otherwise, the whole
# multi-line function from bashrc_block will be added to .bashrc
# so the whole function is cleanly added.

# Backup ~/.bashrc before making changes
BASHRC_FILE="$HOME/.bashrc"
if [[ -f "$BASHRC_FILE" ]]; then
    cp "$BASHRC_FILE" "$BASHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
    echo "Backed up $BASHRC_FILE to $BASHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
else
    echo "Warning: $BASHRC_FILE does not exist. A new one will be created."
fi

# If -clean is invoked, then the old block will be removed from .bashrc and replaced
CLEAN_MODE=false

# Check the number of arguments
if [[ "$#" -eq 0 ]]; then
    # No arguments, proceed with default behavior (CLEAN_MODE is already false)
    : # No operation
elif [[ "$#" -eq 1 && "$1" == "--clean" ]]; then
    # Exactly one argument and it is "--clean"
    CLEAN_MODE=true
else
    # Any other number of arguments or a different argument
    echo >&2 "Error: Invalid arguments."
    echo >&2 "Usage: $(basename "${BASH_SOURCE[0]}") [--clean]"

    # Decide whether to exit or return based on how the script was invoked
    if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
        exit 1
    else
        return 1
    fi
fi

# Block of text to check and add to .bashrc
# Using a here document for readability and maintainability.
# The delimiter 'EOF_BASHRC_CONTENT' is quoted to prevent shell expansion
# of variables like $HOME, $PATH, etc., within this block. They will be
# written literally to .bashrc and expanded when .bashrc is sourced.
bashrc_block=$(cat <<'EOF_BASHRC_CONTENT'
# syskit definitions
####################
# Note: Put manually added .bashrc definitionas *above* this section, as
# 'new1-bashrc.sh --clean' will delete everything from the '# syskit definitions'
# to the end of the file
if ! [[ ":$PATH:" == *":$HOME/syskit:"* ]]; then export PATH="$HOME/syskit:$PATH"; fi
if ! [[ ":$PATH:" == *":$HOME/syskit/0-scripts:"* ]]; then export PATH="$HOME/syskit/0-scripts:$PATH"; fi
# Prompt before overwrite (-i interactive) for rm,cp,mv is very important to avoid disasters
# Scripts will ignore the -i switch *unless* that script is sourced at runtime in which
# case the full .bashrc environment will apply, including these -i switches
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Alias/Function/Export definitions
export EDITOR=vi
export PAGER=less
export LESS='-RFX'    # -R (ANSI colour), -F (exit if fit on one screen), X (disable clearing screen on exit)
export MANPAGER=less    # Set pager for 'man'
export CHEAT_PATHS="~/.cheat"
export CHEAT_COLORS=true
if command -v git &> /dev/null; then git config --global core.pager less; fi    # Set pager for 'git'
# glob expansion for vi, e.g. 'vi *myf*' then tab should expand *myf* to a matching file
complete -o filenames -o nospace -o bashdefault -o default vi
shopt -s checkwinsize    # At every prompt check if the window size has changed
# Extended globbing
shopt -s extglob
# Standard Globbing (enabled by default): *, ?, []
# e.g. cp *file[123] ~/   # This will match myfile1, myfile2, myfile3 etc
# Extended Globbing:
# ?(pattern), zero or one occurrence, e.g. ?(abc) matches abc or nothing.
# *(pattern), zero or more of the pattern, e.g. *(abc) matches abc, abcabc, or nothing.
# +(pattern), one or more occurrences of the pattern, e.g. +(abc) matches abc or abcabc but NOT nothing.
# @(pattern1|pattern2|...), matches exactly one of the specified patterns, e.g., @(jpg|png) matches jpg or png.
# !(pattern), matches anything except the pattern, e.g., !(abc) matches any string except abc.

# History settings and 'h' History helper function
shopt -s histappend       # Append commands to the bash history (~/.bash_history) instead of overwriting it
export HISTTIMEFORMAT="%F %T  " # Add a space for readability in history output
export HISTCONTROL=ignoreboth:erasedups # ignoreboth is a superset of ignorespace and ignoredups
export HISTSIZE=1000000
export HISTFILESIZE=1000000000    # make history very big and show date-time

# h: History Tool. Must be in .bashrc (if it is in a script, then it will be in a subshell, and so cannot view full history)
h() {
    case "$1" in
        "" )
            # The multi-line echo -e string from your function will be preserved
            echo -e "History Tool. Usage: h <option> [string]\n\
  >>> If <option> is a number N, it will act like 'h n N' and show the last N commands\n\
  >>> if <option> is a string, it will act like 'h f string' and search history\n\
  a|an|ad|ab    show all history ('a' full, 'an' numbers only, 'ad' datetime only, 'ab' bare commands)\n\
  f|fn|fd|fb    find string ('f' full, 'fn' numbers only, 'fd' datetime only, 'fb' bare commands)\n\
  n <num>       Show last N history entries (full)\n\
  help          Show extended help from 'h-history' script\n\
  clear         Clear the history\n\
  edit          Edit the history file in your editor\n\
  uniq          Show unique history entries (bare)\n\
  top           Show top 10 most frequent commands (bare roots)\n\
  topn <N>      Show top N most used commands\n\
  cmds          Show top 20 most frequent command roots (bare)\n\
  root          Show commands run with sudo (bare)\n\
  backup <filepath>  Backup history to 'filepath'" ;;
        a) history ;;
        an) history | sed 's/\s*[0-9-]\{10\}\s*[0-9:]\{8\}\s*/ /' ;;
        ad) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//' ;;
        ab) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} /#/' ;;
        f | s) history | grep -i --color=auto -e "$2" ;;
        fn | sn) history | sed 's/\s*[0-9-]\{10\}\s*[0-9:]\{8\}\s*/ /' | grep -i --color=auto -e "$2" ;;
        fd | sd) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//' | grep -i --color=auto -e "$2" ;;
        fb | sb) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} /#/' | grep -i --color=auto -e "$2" ;;
        n) [[ "$2" =~ ^[0-9]+$ ]] && history | tail -n "$2" || echo "Invalid number" ;;
        help) if command -v h-history >/dev/null 2>&1; then h-history; else echo "Error: 'h-history' script not found in your PATH."; fi ;;
        clear)
            read -r -n1 -p "Wipe all history!? Are you sure? [y/N] " r; echo
            if [[ "$r" =~ ^[yY]$ ]]; then
                history -c && echo "History cleared."
            else
                echo "History clear aborted."
            fi ;;
        edit) history -w && ${EDITOR:-vi} "$HISTFILE" ;;
        uniq) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} //' | sort -u ;;
        top) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} //' | awk '{CMD[$1]++} END {for (a in CMD) printf "%5d %s\n", CMD[a], a;}' | sort -nr | head -10 ;;
        topn) if [[ "$2" =~ ^[0-9]+$ ]]; then history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} //' | awk '{CMD[$1]++} END {for (a in CMD) printf "%5d %s\n", CMD[a], a;}' | sort -nr | head -n "$2"; else echo "Invalid number"; fi ;;
        cmds) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} //' | awk '{print $1}' | sort | uniq -c | sort -nr | head -20 ;;
        root) history | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*[0-9-]\{10\} [0-9:]\{8\} //' | grep -w sudo ;;
        backup) if [ -z "$2" ]; then echo "Please specify a filename for the backup."; else history > "$2" && echo "History backed up to $2"; fi ;;
        *) [[ "$1" =~ ^[0-9]+$ ]] && history | tail -n "$1" || history | grep -i --color=auto -e "$1" ;;
    esac;
    echo -e "\nHistory tips: !N (run cmd N), !! (run last cmd), !-N (run Nth last cmd),"
    echo -e "  !str (run last cmd starting w/str), !?str? (run last cmd containing str)."
    echo -e "Ctrl-r/s (reverse/forward history search). Note: Ctrl-s may require 'stty -ixon' to enable."
}

# def: Show function/alias/built-ins/scripts definitions. This must be in .bashrc to have visibility of all loaded shell functions and aliases
def() {
    if [ -z "$1" ]; then
        declare -F; printf "\nAll defined functions ('declare -F').\n"
        printf "Usage: def <name> - show definition of a function, alias, built-in, or script called 'name'.\n"
        return
    fi
    local OVERLAPS=()    # Track overlaps in an array, i.e. where the item is in more than one category
    local PAGER_CMD="cat"    # Use 'cat' by default
    if command -v batcat >/dev/null 2>&1; then    # Prefer 'batcat' if available
        PAGER_CMD="batcat -pp -l bash"
    elif command -v bat >/dev/null 2>&1; then # Fallback to 'bat' if 'batcat' is not found
        PAGER_CMD="bat -pp -l bash"
    fi
    if declare -F "$1" >/dev/null 2>&1; then    # check for a 'Function'
        declare -f "$1" | $PAGER_CMD; OVERLAPS+=("Function"); echo; echo "'$1' is a function.";
    fi
    if alias "$1" >/dev/null 2>&1; then    # check for an 'Alias'
        alias "$1" | $PAGER_CMD; OVERLAPS+=("Alias"); echo; echo "'$1' is an alias."
    fi
    if type -t "$1" | grep -q "builtin"; then    # check for a 'built-in command'
        help "$1" | $PAGER_CMD; OVERLAPS+=("Built-in"); echo; echo "'$1' is a built-in command."
    fi
    # Check for an 'external script' only if not already found as a function or alias to avoid redundancy with shell builtins/keywords
    if ! (declare -F "$1" >/dev/null 2>&1 || alias "$1" >/dev/null 2>&1 || type -t "$1" | grep -q "builtin"); then
      if command -v "$1" >/dev/null 2>&1; then
        local SCRIPT_PATH
        SCRIPT_PATH=$(command -v "$1")
        if [[ -f "$SCRIPT_PATH" ]]; then
            $PAGER_CMD "$SCRIPT_PATH"; OVERLAPS+=("Script"); echo; echo "'$1' is a script, located at '$SCRIPT_PATH'."
        fi
      fi
    fi
    # Display overlaps
    if [ ${#OVERLAPS[@]} -gt 1 ]; then
        local joined_overlaps
        joined_overlaps=$(printf ", %s" "${OVERLAPS[@]}")
        joined_overlaps=${joined_overlaps:2} # Remove leading ", "
        echo -e "\033[0;31mWarning: '$1' has multiple types: ${joined_overlaps}.\033[0m"
    fi
    # If no matches were found
    if [ ${#OVERLAPS[@]} -eq 0 ]; then echo "No function, alias, built-in, or script found for '$1'."; fi;
}

# Helpers for various configuration scripts:
alias bashrc='vi ~/.bashrc'          # Edit .bashrc (user)
alias inputrc='vi ~/.inputrc'        # Edit .inputrc (user)
alias vimrc='vi ~/.vimrc'            # Edit .vimrc (user)
alias vimrcroot='sudo vi /etc/vim/vimrc'     # Edit vimrc (system)
alias vimrcsudo='sudo vi /etc/vim/vimrc'     # Edit vimrc (system)
config() { cd $HOME/.config || return; ls; } # Jump to ~/.config
mnt() { cd /mnt || return; ls; }             # Jump to /mnt
alias sudoers='sudo visudo'                  # Edit /etc/sudoers
alias initvim='vi ~/.config/nvim/init.vim'   # Edit neovim configuration
alias nvimrc='vi ~/.config/nvim/init.vim'    # Edit neovim configuration
alias tmuxconf='vi ~/.tmux.conf'             # Edit tmux configuration

# Helpers for SMB, NFS, and mount 
alias fstab='sudo vi /etc/fstab'             # Edit Filesystem Table
alias hosts='sudo vi /etc/hosts'             # Edit /etc/hosts
alias smb='sudo vi /etc/samba/smb.conf'      # Edit Samba configuration
alias samba='sudo vi /etc/samba/smb.conf'    # Edit Samba configuration
alias smbconf='sudo vi /etc/samba/smb.conf'  # Edit Samba configuration
alias exports='sudo vi /etc/exports'         # Edit NFS exports
alias nfs-fs='sudo exportfs'          # Shows the current list of directories exported via NFS. Requires sudo
alias nfs-fs-a='sudo exportfs -a'     # Exports all directories listed in the /etc/exports file
alias nfs-fs-r='sudo exportfs -r'     # Re-exports all directories listed in /etc/exports, applying any changes
alias nfs-fs-u='sudo exportfs -u'     # Requires directory path as argument; stops exporting the specified directory
alias nfs-fs-v='sudo exportfs -v'     # Shows the current list of exported directories with verbose details
alias nfs-mount='sudo showmount'      # Shows as non-existent command if run without sudo
nfs-server() { local action=${1:-status}; sudo systemctl "$action" nfs-server; }  # or start, stop, restart, enable, disable
alias nfs-mount-e='showmount -e'      # Requires <server_ip_or_hostname>
alias nfs-mount-a='showmount -a'      # Requires <server_ip_or_hostname>
alias nfs-mount-t='sudo mount -t nfs' # Requires <server_ip_or_hostname>:/remote/path /local/mountpoint
alias unmount='sudo umount'           # Requires path: /path/to/local/mountpoint
alias rpc='rpcinfo -p'                # Requires <server_ip_or_hostname>
# Note also 'nfsstat'

# Simple helpers, cd.., cx, cxx, ls., ll., etc
alias u1='cd ..';          alias cd..='u1'  # cd.. is a common typo in Linux for Windows users
alias u2='u1;u1';          alias cd...='u2'  # cd up 2 directories
alias u3='u1;u1;u1';       alias cd....='u3'  # cd up 3 directories
alias u4='u1;u1;u1;u1';    alias cd.....='u4'  # cd up 4 directories
alias u5='u1;u1;u1;u1;u1'; alias cd......='u5'  # cd up 5 directories
alias cx='chmod +x'             # Quickyly 'chmod +x' (add the execute permission) to a file
cxx() { chmod +x "$1" && "./$1"; } # chmod +x then run $1 (add quoting and ./ for safety)
alias ls='ls --color=auto'      # Add color output by default
alias ls.='ls -d .[!.]* ..?*'   # More robust ls for hidden files/dirs in current dir
alias ll='ls -alh'              # -a includes hidden, -h human-readable
alias ll.='ls -ald .[!.]* ..?*' # -a includes hidden, -d for dirs, -l long
alias l='ls -CF'
alias ifconfig='sudo ifconfig'    # 'ifconfig' (apt install net-tools) causes 'command not found' if run without sudo
alias ipconfig='sudo ifconfig'    # Common typo for Windows users, just try ifconfig instead
alias venvh='source $HOME/syskit/0-scripts/venv-helper.sh'   # Uses 0-scripts/venv-helper.sh to manage Python venv's

# tmux helpers (using 't' script) and git helpers (using 'g' script)
alias tt='tmux'
alias td='tmux detach'   # ta detach current session, ta attach last *or* named session
ta() { if [ -n "$2" ]; then tmux attach-session -t "$2"; else tmux attach; fi; }
alias th='t nh'; alias tv='t nv'
alias tf='tmux select-pane -t :.+' # Jump to next pane
alias tb='tmux select-pane -t :.-' # Jump to previous pane
# tl+, tr+, tu+, td+ resize pane left, right, up, down
alias tl+='tmux resize-pane -L 5'  ; alias tr+='tmux resize-pane -R 5'
alias tu+='tmux resize-pane -U 5'  ; alias td+='tmux resize-pane -D 5'

alias gacp='git add -A && git commit -m "Various" && git push'
if [ -f $HOME/syskit/0-scripts/g ]; then alias gacp='g acp'; fi

# Create 'bat' alias for 'batcat' (apt install bat) *unless* 'bat' from bluez-tools package (Bluetooth Audio Tool) is present
if ! dpkg -s bluez-tools &> /dev/null && command -v batcat &> /dev/null && ! command -v bat &> /dev/null; then alias bat='batcat'; fi # Use batcat as bat on Debian/Ubuntu if 'bat' isn't the bluetooth tool

# The below will load ~/.bashrc_personal if it is present. This is more for personal jump
# locations and personal functions and aliases that don't fit as more generic. A sample set
# of these are available in a bashrc_personal script in the 0-new-system folder.
if [ -f ~/.bashrc_personal ]; then . ~/.bashrc_personal; fi

# Jump functions for syskit, cannot be in scripts as have to be dotsourced.
00()  { cd "$HOME/syskit" || return; ls; }             # Jump to syskit project root
0d()  { cd "$HOME/syskit/0-docker" || return; ls; }        # Jump to syskit/0-docker
0g()  { cd "$HOME/syskit/0-games" || return; ls; }         # Jump to syskit/0-games
0h()  { cd "$HOME/syskit/0-help" || return; ls; }          # Jump to syskit/0-help
0i()  { cd "$HOME/syskit/0-install" || return; ls; }       # Jump to syskit/0-install
0n()  { cd "$HOME/syskit/0-new-system" || return; ls; }    # Jump to syskit/0-new-system
0s()  { cd "$HOME/syskit/0-scripts" || return; ls; }       # Jump to syskit/0-scripts
0w()  { cd "$HOME/syskit/0-web-apps" || return; ls; }      # Jump to syskit/0-web-apps
0ms() { cd "$HOME/syskit/0-docker/0-media-stack" || return; ls; }    # Jump to docker media-stack setup folder
0mc() { cd "$HOME/.config/media-stack/" || return; ls; }      # Jump to ~/.config/media-stack, all config folders for media-stack
0v()  { cd "$HOME/.vnc" || return; ls; }                      # Jump to ~/.vnc

EOF_BASHRC_CONTENT
)

# Capture the first non-empty line of $bashrc_block, this is the header line
first_non_empty_line=$(echo "$bashrc_block" | sed -n '/[^[:space:]]/s/^[[:space:]]*//p' | head -n 1)

# Ensure the variable is not empty
if [[ -z "$first_non_empty_line" ]]; then
    echo "Error: No valid content found in bashrc_block. Exiting."
    exit 1 # Exit if the block is empty, as something is wrong.
fi

# Check if this line exists in .bashrc
# Only attempt cleanup if the marker is found and CLEAN_MODE is true
if [[ "$CLEAN_MODE" == true ]]; then
    if grep -Fxq "$first_non_empty_line" "$BASHRC_FILE"; then
        echo "CLEAN_MODE: Performing cleanup. Deleting block from '$first_non_empty_line' to end of $BASHRC_FILE."
        # Escape the marker line for sed address
        escaped_marker=$(printf '%s\n' "$first_non_empty_line" | sed 's/[.[\*^$]/\\&/g')
        sed -i "/^${escaped_marker}$/,\$d" "$BASHRC_FILE"
        echo "Removed block from $BASHRC_FILE."
    else
        echo "CLEAN_MODE: Marker line '$first_non_empty_line' not found in $BASHRC_FILE. No cleanup performed."
    fi
fi

# Function to check and add lines/functions
# This function will now be called by the main loop that processes $bashrc_block
# It determines the type of line and checks if it (or its identifier) already exists.
add_entry_if_not_exists() {
    local entry_block="$1" # Can be a single line or a full function block
    local first_line_of_entry
    first_line_of_entry=$(echo "$entry_block" | head -n 1)
    local entry_type=""
    local identifier=""

    # Determine entry type and identifier (e.g., alias name, export variable name, function name)
    if [[ "$first_line_of_entry" =~ ^[[:space:]]*alias[[:space:]]+([^=]+)= ]]; then
        entry_type="alias"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*(export|declare[[:space:]]+-x)[[:space:]]+([^=]+)= ]]; then
        entry_type="export"
        identifier="${BASH_REMATCH[2]}"
        # Special handling for PATH to allow multiple unique additions
        if [[ "$identifier" == "PATH" ]]; then
            if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
                echo "Exact PATH definition already exists: $first_line_of_entry. Skipping."
                return
            fi
            # If not exact match, proceed to add (handled by general "add now" logic)
        fi
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*\{ ]]; then # func() {
        entry_type="function"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*([\{\(]) ]]; then # function func { or function func () {
        entry_type="function"
        identifier="${BASH_REMATCH[1]}"
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*# ]]; then
        entry_type="comment"
         # For comments, shopt, complete, if, fi, and other simple lines, check for exact line existence
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
            # Silently skip if exact comment already exists
            return
        fi
    elif [[ "$first_line_of_entry" =~ ^[[:space:]]*(shopt|complete|if|fi) ]]; then
        entry_type="directive" # Generic type for shopt, complete etc.
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
             # Silently skip if exact directive already exists
            return
        fi
    elif [[ -z "${first_line_of_entry// }" ]]; then # Check if line is blank or only whitespace
        entry_type="blank"
        # Blank lines will be added directly by the main loop
    else
        entry_type="other"
        if grep -Fxq "$first_line_of_entry" "$BASHRC_FILE"; then
            # Silently skip if exact other line already exists
            return
        fi
    fi

    # Check for existence based on identifier for alias, export (non-PATH), function
    if [[ "$entry_type" == "alias" ]]; then
        # Trim whitespace from identifier for grep
        local trimmed_identifier=$(echo "$identifier" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if grep -qE "^[[:space:]]*alias[[:space:]]+${trimmed_identifier}=" "$BASHRC_FILE"; then
            echo "Alias ${trimmed_identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    elif [[ "$entry_type" == "export" && "$identifier" != "PATH" ]]; then # PATH is handled above
        if grep -qE "^[[:space:]]*(export|declare[[:space:]]+-x)[[:space:]]+${identifier}=" "$BASHRC_FILE"; then
            echo "Export ${identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    elif [[ "$entry_type" == "function" ]]; then
        # More robust check for function definition start
        if grep -qE "(^|[[:space:]])${identifier}[[:space:]]*\(\)[[:space:]]*\{|^\s*function\s+${identifier}" "$BASHRC_FILE"; then
            echo "Function ${identifier} already defined in $BASHRC_FILE. Skipping block."
            return
        fi
    fi

    # If we reach here, the entry (or its unique part) doesn't exist, or it's a type that should be added if not an exact match
    echo "Adding to $BASHRC_FILE:"
    echo "$entry_block" # For logging what's being added
    echo "$entry_block" >> "$BASHRC_FILE"
    echo # Add a newline for better separation in .bashrc if adding multiple blocks
}

# Ensure the main marker line is present if it was cleaned or never existed
if ! grep -Fxq "$first_non_empty_line" "$BASHRC_FILE"; then
    echo "Adding main marker: $first_non_empty_line"
    echo "$first_non_empty_line" >> "$BASHRC_FILE"
fi


# Process the bashrc_block, identifying functions and other entries
current_block=""
in_function_block=false
first_line_of_block="" # Not strictly needed here anymore with current logic but kept for now

# Use process substitution to feed the main block processing loop,
# skipping the first line (marker line) which is handled separately.
# This avoids issues with the last line of input sometimes being missed by `while read` from a variable.
while IFS= read -r line; do
    # Detect start of a function (e.g., func() { or function func {)
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\)[[:space:]]*\{ || "$line" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
        if $in_function_block && [[ -n "$current_block" ]]; then # We were in a function, and it's ending implicitly by starting a new one
            add_entry_if_not_exists "$current_block"
        fi
        current_block="$line"
        in_function_block=true
    elif $in_function_block; then
        current_block+=$'\n'"$line"
        # Detect end of a function block
        if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            add_entry_if_not_exists "$current_block"
            current_block=""
            in_function_block=false
        fi
    else # Not in a function block, treat as a single-line entry or a non-function multi-line (e.g. comments)
        if [[ -n "${line// }" ]]; then # If line is not blank (handles lines with only spaces correctly)
             add_entry_if_not_exists "$line" # Process single lines or start of non-function blocks
        else # Preserve blank lines from the here-doc
            echo >> "$BASHRC_FILE"
        fi
        # current_block="" # Not needed here as single lines are processed immediately
    fi
done < <(echo "$bashrc_block" | sed '1d') # Process block, skipping the first_non_empty_line (marker)

# If the loop finishes and we were still accumulating a function block (e.g., file ends mid-function without a closing brace on its own line)
if $in_function_block && [[ -n "$current_block" ]]; then
    add_entry_if_not_exists "$current_block"
fi

# Remove trailing blank lines that might have been introduced
if [[ -s "$BASHRC_FILE" ]]; then # Only run sed if file is not empty
    # This sed command removes all trailing blank lines from the file
    sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$BASHRC_FILE"
    # Additionally, ensure there's exactly one newline at the very end if the file is not empty
    if [[ $(tail -c1 "$BASHRC_FILE" | wc -l) -eq 0 ]]; then
        echo >> "$BASHRC_FILE"
    fi
fi


echo
echo "Finished updating $BASHRC_FILE."

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Script is sourced
    echo
    echo "This script was sourced. Sourcing $BASHRC_FILE to apply changes to the current environment..."
    # Ensure BASHRC_FILE is sourced correctly even if path contains spaces
    # shellcheck source=/dev/null
    source "$BASHRC_FILE"
    echo "Environment updated."
else
    # Script is executed
    echo
    echo "This script was executed directly. To apply changes to the current environment, run:"
    echo "    source $BASHRC_FILE"
    echo "Or open a new terminal session."
fi

