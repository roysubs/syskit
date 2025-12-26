#!/bin/zsh
# Author: Roy Wiseman 2025-01
# Adapted for Zsh

# Each line in 'zshrc_block' will be tested against .zshrc
# If that item exists with a different value, it will not alter it.

# Backup ~/.zshrc before making changes
ZSHRC_FILE="$HOME/.zshrc"
if [[ -f "$ZSHRC_FILE" ]]; then
    cp "$ZSHRC_FILE" "$ZSHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
    echo "Backed up $ZSHRC_FILE to $ZSHRC_FILE.$(date +'%Y-%m-%d_%H-%M-%S').bak"
else
    echo "Warning: $ZSHRC_FILE does not exist. A new one will be created."
fi

# If -clean is invoked, then the old block will be removed from .zshrc and replaced
CLEAN_MODE=false

# Check the number of arguments
if [[ "$#" -eq 0 ]]; then
    : # No operation
elif [[ "$#" -eq 1 && "$1" == "--clean" ]]; then
    CLEAN_MODE=true
else
    echo >&2 "Error: Invalid arguments."
    echo >&2 "Usage: $(basename "${0}") [--clean]"
    if [[ "${0}" -ef "$0" ]]; then exit 1; else return 1; fi
fi

# Block of text to check and add to .zshrc
# Using a here document for readability.
zshrc_block=$(cat <<'EOF_ZSHRC_CONTENT'
# syskit definitions
####################
# Note: Put manually added .zshrc definitions *above* this section
# 'new1-zshrc.sh --clean' will delete everything from the '# syskit definitions'
# to the end of the file

# Path definitions
if [[ ":$PATH:" != *":$HOME/syskit:"* ]]; then export PATH="$HOME/syskit:$PATH"; fi
if [[ ":$PATH:" != *":$HOME/syskit/0-scripts:"* ]]; then export PATH="$HOME/syskit/0-scripts:$PATH"; fi

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Alias/Function/Export definitions
export EDITOR=vi
export PAGER=less
export LESS='-RFX'
export MANPAGER=less
export CHEAT_PATHS="~/.cheat"
export CHEAT_COLORS=true
if (( $+commands[git] )); then git config --global core.pager less; fi

# Zsh specific options
setopt no_beep              # Don't beep on error
setopt auto_cd              # If command is a path, cd into it
setopt interactive_comments # Allow comments in interactive shell

# Completion
autoload -Uz compinit
compinit
# Use bash completion support if needed
autoload -Uz bashcompinit && bashcompinit

# Globbing
setopt extended_glob        # Extended globbing
# Standard globs *, ?, [] are default
# Zsh Extended Globs:
# ^pat      -> Match anything except pattern
# pat1~pat2 -> Match pat1 but not pat2
# (pat1|pat2) -> Match pat1 or pat2
# <x-y>     -> Match number range
# **        -> Recursive match

# History settings
setopt append_history       # Append history to the history file
setopt extended_history     # Save timestamp and duration
setopt inc_append_history   # Append commands immediately
setopt share_history        # Share history between sessions
export HISTSIZE=1000000
export SAVEHIST=1000000

# h: History Tool adapted for Zsh
# Note: 'history' in zsh is an alias for 'fc -l', but behavior varies.
# We explicitly use 'fc -li 1' to get full history with time, or 'fc -l 1' for short.
h() {
    local cmd="$1"
    local arg="$2"
    
    # Helper to get history stream. 
    # 'fc -li 1' gives: "  123  2024-01-01 12:00  command"
    # 'fc -l 1' gives:  "  123  command"
    # standard 'history' (alias) might truncate.
    
    case "$cmd" in
        "" )
            # Zsh 'print' handles newlines better than echo sometimes, but echo -e is essentially same
            print -l "History Tool. Usage: h <option> [string]" \
            "  >>> If <option> is a number N, acts like 'h n N' (last N commands)" \
            "  >>> If <option> is a string, acts like 'h f string' (search)" \
            "  a|an|ad|ab    show all ('a' full, 'an' nums, 'ad' time, 'ab' bare)" \
            "  f|fn|fd|fb    find string ('f' full, ...)" \
            "  n <num>       Show last N history entries" \
            "  help          Show extended help (h-history script)" \
            "  clear         Clear the history" \
            "  edit          Edit history file" \
            "  uniq          Show unique history entries (bare)" \
            "  top           Top 10 commands" \
            "  topn <N>      Top N commands" \
            "  cmds          Top 20 command roots" \
            "  root          Sudo commands" \
            "  backup <file> Backup history" ;;
            
        a) fc -li 1 ;;
        an) fc -li 1 | sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}//' ;; # Remove Date
        ad) fc -li 1 | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//' ;; # Remove ID
        ab) fc -l -n 1 ;; # Bare commands (no ID, no time if -n used correctly with -l? No, -n suppresses numbers.)
                          # Actually 'fc -l -n 1' gives just command? NO. 'fc -ln 1'
        
        # Search
        f|s) fc -li 1 | grep -i --color=auto -- "$arg" ;;
        fn|sn) fc -li 1 | sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}//' | grep -i --color=auto -- "$arg" ;;
        fd|sd) fc -li 1 | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//' | grep -i --color=auto -- "$arg" ;;
        fb|sb) fc -ln 1 | grep -i --color=auto -- "$arg" ;;

        # Last N
        n) [[ "$arg" =~ ^[0-9]+$ ]] && fc -li -"$arg" || echo "Invalid number" ;;

        help) if (( $+commands[h-history] )); then h-history; else echo "Error: 'h-history' script not found."; fi ;;
        
        clear)
            if read -q "choice?Wipe all history!? Are you sure? [y/N] "; then
                echo
                # Zsh way to clear history memory and file
                fc -p "$HISTFILE" 0 0 # switch to new empty history
                rm "$HISTFILE" 2>/dev/null
                touch "$HISTFILE"
                fc -P # restore
                fc -R # read (empty)
                echo "History cleared."
            else
                echo "\nHistory clear aborted."
            fi ;;
            
        edit) fc -W; ${EDITOR:-vi} "$HISTFILE"; fc -R ;;
        
        uniq) fc -ln 1 | sort -u ;;
        top)  fc -ln 1 | awk '{CMD[$1]++} END {for (a in CMD) printf "%5d %s\n", CMD[a], a;}' | sort -nr | head -10 ;;
        topn) if [[ "$arg" =~ ^[0-9]+$ ]]; then fc -ln 1 | awk '{CMD[$1]++} END {for (a in CMD) printf "%5d %s\n", CMD[a], a;}' | sort -nr | head -n "$arg"; else echo "Invalid number"; fi ;;
        cmds) fc -ln 1 | awk '{print $1}' | sort | uniq -c | sort -nr | head -20 ;;
        root) fc -ln 1 | grep -w sudo ;;
        backup) if [[ -z "$arg" ]]; then echo "Specify filename."; else fc -ln 1 > "$arg" && echo "Backed up to $arg"; fi ;;
        
        *) if [[ "$cmd" =~ ^[0-9]+$ ]]; then fc -li -"$cmd"; else fc -li 1 | grep -i --color=auto -- "$cmd"; fi ;;
    esac
}

# def: Show function/alias/built-ins/scripts definitions
def() {
    if [[ -z "$1" ]]; then
        print -l "Usage: def <name>"
        return
    fi
    local PAGER_CMD="cat"
    if (( $+commands[batcat] )); then PAGER_CMD="batcat -pp -l zsh"; 
    elif (( $+commands[bat] )); then PAGER_CMD="bat -pp -l zsh"; fi
    
    local found=0
    
    # Check function
    if (( ${+functions[$1]} )); then
        print -P "%F{green}Function:%f"
        functions[$1] | ${(z)PAGER_CMD}
        found=1
    fi
    # Check alias
    if (( ${+aliases[$1]} )); then
        print -P "%F{green}Alias:%f"
        alias "$1"
        found=1
    fi
    # Check builtin
    if whence -w "$1" | grep -q "builtin"; then
        print -P "%F{green}Built-in:%f $1"
        found=1
    fi
    # Check external script (only if not one of the above, usually)
    local p
    p=$(whence -p "$1")
    if [[ -f "$p" ]]; then
        print -P "%F{green}Script:%f $p"
        if (( ! found )); then ${(z)PAGER_CMD} "$p"; fi
        found=1
    fi
    
    if (( ! found )); then echo "No definition found for '$1'."; fi
}

# Config Helpers
alias zshrc='vi ~/.zshrc'
alias zshrcsource='source ~/.zshrc'
alias inputrc='vi ~/.inputrc'
alias vimrc='vi ~/.vimrc'
alias vimrcroot='sudo vi /etc/vim/vimrc'
alias vimrcsudo='sudo vi /etc/vim/vimrc'
config() { cd $HOME/.config || return; ls; }
mnt() { cd /mnt || return; ls; }
alias sudoers='sudo visudo'
alias initvim='vi ~/.config/nvim/init.vim'
alias nvimrc='vi ~/.config/nvim/init.vim'
alias tmuxconf='vi ~/.tmux.conf'

# Helpers for SMB, NFS, and mount 
alias fstab='sudo vi /etc/fstab'
alias hosts='sudo vi /etc/hosts'
alias smb='sudo vi /etc/samba/smb.conf'
alias samba='sudo vi /etc/samba/smb.conf'
alias smbconf='sudo vi /etc/samba/smb.conf'
alias exports='sudo vi /etc/exports'
alias nfs-fs='sudo exportfs'
alias nfs-fs-a='sudo exportfs -a'
alias nfs-fs-r='sudo exportfs -r'
alias nfs-fs-u='sudo exportfs -u'
alias nfs-fs-v='sudo exportfs -v'
alias nfs-mount='sudo showmount'
nfs-server() { local action=${1:-status}; sudo systemctl "$action" nfs-server; }
alias nfs-mount-e='showmount -e'
alias nfs-mount-a='showmount -a'
alias nfs-mount-t='sudo mount -t nfs'
alias unmount='sudo umount'
alias rpc='rpcinfo -p'

# Navigation
alias u1='cd ..';          alias cd..='u1'
alias u2='u1;u1';          alias cd...='u2'
alias u3='u1;u1;u1';       alias cd....='u3'
alias u4='u1;u1;u1;u1';    alias cd.....='u4'
alias u5='u1;u1;u1;u1;u1'; alias cd......='u5'

# Tools
alias cx='chmod +x'
cxx() { chmod +x "$1" && "./$1"; }
alias ls='ls -G' # -G for color in macOS/BSD ls, --color=auto for GNU. Zsh usually detects.
# Better to check system type? MacOS 'ls' is BSD. 'ls -G'. Linux 'ls' is GNU.
if ls --color >/dev/null 2>&1; then alias ls='ls --color=auto'; else alias ls='ls -G'; fi

alias ls.='ls -d .[!.]* ..?*'
alias ll='ls -alh'
alias ll.='ls -ald .[!.]* ..?*'
alias l='ls -CF'

alias ifconfig='sudo ifconfig'
alias ipconfig='sudo ifconfig'
alias venvh='source $HOME/syskit/0-scripts/venv-helper.sh'

# Tmux
alias tt='tmux'
alias td='tmux detach'
ta() { if [[ -n "$1" ]]; then tmux attach-session -t "$1"; else tmux attach; fi; }
alias thh='t nh'; alias tvv='t nv'
alias tf='tmux select-pane -t :.+'
alias tb='tmux select-pane -t :.-'
alias tl+='tmux resize-pane -L 5'; alias tr+='tmux resize-pane -R 5'
alias tu+='tmux resize-pane -U 5'; alias td+='tmux resize-pane -D 5'

alias gacp='git add -A && git commit -m "Various" && git push'
if [[ -f $HOME/syskit/0-scripts/g ]]; then alias gacp='g acp'; fi

# Batcat compatibility
if ! dpkg -s bluez-tools >/dev/null 2>&1 && (( $+commands[batcat] )) && ! (( $+commands[bat] )); then alias bat='batcat'; fi

# Personal overwrite
if [[ -f ~/.zshrc_personal ]]; then . ~/.zshrc_personal; fi

# Syskit Jumps
00()  { cd "$HOME/syskit" || return; ls; }
0d()  { cd "$HOME/syskit/0-docker" || return; ls; }
0g()  { cd "$HOME/syskit/0-games" || return; ls; }
0h()  { cd "$HOME/syskit/0-help" || return; ls; }
0i()  { cd "$HOME/syskit/0-install" || return; ls; }
0n()  { cd "$HOME/syskit/0-new-system" || return; ls; }
0s()  { cd "$HOME/syskit/0-scripts" || return; ls; }
0w()  { cd "$HOME/syskit/0-web-apps" || return; ls; }
0ms() { cd "$HOME/syskit/0-docker/0-media-stack" || return; ls; }
0mc() { cd "$HOME/.config/media-stack/" || return; ls; }
0v()  { cd "$HOME/.vnc" || return; ls; }

# 'c' Jump Tool
c() {
    if [[ -z "$1" ]]; then
        cat <<EOF
'c' quick jump. Usage: c [destination]
-- syskit --
  0, k syskit : \$HOME/syskit
  n, new      : syskit/0-new-system
  s, scripts  : syskit/0-scripts
  hp, help    : syskit/0-help
  dk, docker  : syskit/0-docker
  g, games    : syskit/0-games
  i, install  : syskit/0-install
  w, web      : syskit/0-web-apps
-- custom --
  ms          : syskit/0-docker/0-media-stack
  q, qbit, qc : ~/.config/media-stack/qbittorrent
-- System --
  h            : \$HOME
  d, down      : \$HOME/Downloads
  docs         : \$HOME/Documents
  etc          : /etc
  c, cf, conf  : \$HOME/.config
  t, tmp, temp : /tmp
  l, log       : /var/log
  b bin        : /usr/local/bin
EOF
        return
    fi
    
    local dest="${1:l}" # Lowercase
    
    case "$dest" in
        0|k|syskit)  cd "$HOME/syskit" ;;
        n|new)       cd "$HOME/syskit/0-new-system" ;;
        s|scripts)   cd "$HOME/syskit/0-scripts" ;;
        hp|help)     cd "$HOME/syskit/0-help" ;;
        dk|docker)   cd "$HOME/syskit/0-docker" ;;
        g|games)     cd "$HOME/syskit/0-games" ;;
        i|install)   cd "$HOME/syskit/0-install" ;;
        w|web)       cd "$HOME/syskit/0-web-apps" ;;
        ms)          cd "$HOME/syskit/0-docker/0-media-stack" ;;
        q|qbit|qc)   cd "$HOME/.config/media-stack/qbittorrent" ;;
        d|down|downloads) cd "$HOME/Downloads" ;;
        docs)        cd "$HOME/Documents" ;;
        h|home)      cd "$HOME" ;;
        etc)         cd "/etc" ;;
        c|cf|conf)   cd "$HOME/.config" ;;
        t|tmp|temp)  cd "/tmp" ;;
        l|log)       cd "/var/log" ;;
        b|bin)       cd "/usr/local/bin" ;;
        *)           
            if [[ -d "$1" ]]; then cd "$1"; else echo "Unknown destination: '$1'" >&2; return 1; fi
            ;;
    esac
}
alias cs='c s'

EOF_ZSHRC_CONTENT
)

# Extract first non-empty line (marker)
first_non_empty_line=$(echo "$zshrc_block" | sed -n '/[^[:space:]]/s/^[[:space:]]*//p' | head -n 1)

if [[ -z "$first_non_empty_line" ]]; then
    echo "Error: Empty zshrc block."
    exit 1
fi

# Clean logic
if [[ "$CLEAN_MODE" == true ]]; then
    if grep -Fxq "$first_non_empty_line" "$ZSHRC_FILE"; then
        echo "CLEAN_MODE: Removing old block..."
        escaped_marker=$(printf '%s\n' "$first_non_empty_line" | sed 's/[.[\*^$]/\\&/g')
        sed -i '' "/^${escaped_marker}$/,\$d" "$ZSHRC_FILE"
        echo "Removed."
    else
        echo "CLEAN_MODE: Marker not found, nothing to clean."
    fi
fi

# Function to add entry uniquely
add_entry_if_not_exists() {
    local entry_block="$1"
    local first_line=$(echo "$entry_block" | head -n 1)
    
    # Simple check for existing line (exact match mostly safe for these types of configs)
    # Zshrc usually shorter than bashrc logic because we can rely on Zsh features or users often just append.
    # However, mimicking the bashrc script robustness:
    
    local id=""
    local type=""
    
    if [[ "$first_line" =~ ^[[:space:]]*alias[[:space:]]+([^=]+)= ]]; then
        type="alias" # ${match[1]} in Zsh or use BASH_REMATCH if enabled (zsh usually doesn't by default use BASH_REMATCH without setopt RE_MATCH_PCRE or similar? No, standard zsh regex needs 'setopt KSH_ARRAYS' or using match array)
        # We can use zsh regex matching or just grep for simplicity across shells
        # Let's simple grep the file for the key definition
        id=$(echo "$first_line" | sed 's/^[[:space:]]*alias[[:space:]]*//;s/=.*//')
        if grep -qE "^[[:space:]]*alias[[:space:]]+${id}=" "$ZSHRC_FILE"; then return; fi
        
    elif [[ "$first_line" =~ ^[[:space:]]*export[[:space:]]+([^=]+)= ]]; then
        type="export"
        id=$(echo "$first_line" | sed 's/^[[:space:]]*export[[:space:]]*//;s/=.*//')
        if [[ "$id" == "PATH" ]]; then
             if grep -Fxq -- "$first_line" "$ZSHRC_FILE"; then return; fi
        else
             if grep -qE -- "^[[:space:]]*export[[:space:]]+${id}=" "$ZSHRC_FILE"; then return; fi
        fi
        
    elif [[ "$first_line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)\(\)[[:space:]]*\{ ]]; then
        type="function"
        id=$(echo "$first_line" | sed 's/().*//')
        if grep -qE "(^|[[:space:]])${id}[[:space:]]*\(\)[[:space:]]*\{" "$ZSHRC_FILE"; then return; fi
        
    elif [[ "$first_line" =~ ^[[:space:]]*# ]]; then
        if grep -Fxq "$first_line" "$ZSHRC_FILE"; then return; fi
    else
        # directives, blanks
        if grep -Fxq -- "$first_line" "$ZSHRC_FILE"; then return; fi
    fi
    
    echo "Adding to $ZSHRC_FILE: $first_line"
    echo "$entry_block" >> "$ZSHRC_FILE"
}

# Ensure marker exists if we are about to add things (or if we cleaned it, we add it back)
if ! grep -Fxq "$first_non_empty_line" "$ZSHRC_FILE"; then
    echo "Adding main marker: $first_non_empty_line"
    echo "$first_non_empty_line" >> "$ZSHRC_FILE"
fi

# Main Processing Loop
current_block=""
in_function=false

echo "$zshrc_block" | sed '1d' | while IFS= read -r line; do
    # Function start detector using grep for robustness against shell regex differences
    if echo "$line" | grep -qE "^[[:space:]]*[a-zA-Z0-9_]+\(\)[[:space:]]*\{"; then
        if $in_function && [[ -n "$current_block" ]]; then add_entry_if_not_exists "$current_block"; fi
        current_block="$line"
        in_function=true
    elif $in_function; then
        current_block+=$'\n'"$line"
        if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            add_entry_if_not_exists "$current_block"
            current_block=""
            in_function=false
        fi
    else
        if [[ -n "${line// }" ]]; then
            add_entry_if_not_exists "$line"
        else
            echo >> "$ZSHRC_FILE"
        fi
    fi
done

if $in_function && [[ -n "$current_block" ]]; then
    add_entry_if_not_exists "$current_block"
fi

echo "Finished updating $ZSHRC_FILE."
echo "Please restart your shell or run 'source ~/.zshrc' to apply."
