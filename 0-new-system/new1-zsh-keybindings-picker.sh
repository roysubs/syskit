#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10
#
# Interactive, idempotent picker for zsh keybindings (zle/bindkey), written
# to ~/.zshrc. This is the zsh counterpart to new1-inputrc-picker.sh, which
# only affects bash: zsh has its own line editor and ignores ~/.inputrc.
#
# IMPORTANT: new1-zshrc.sh --clean deletes everything from its
# "# syskit definitions" marker to the end of the file, then rewrites that
# block fresh. So this script inserts its own blocks ABOVE that marker,
# in the zone new1-zshrc.sh already treats as yours to keep. That means a
# later run of setup-syskit-zsh.sh / new1-zshrc.sh --clean will not remove
# what you enable here. If the marker isn't there yet, the block is just
# appended to the end of the file.
#
# Nothing here is turned on by running this script. You choose each option.

ZSHRC_FILE="$HOME/.zshrc"
MARKER="# syskit definitions"
touch "$ZSHRC_FILE" 2>/dev/null || { echo "Error: cannot write to $ZSHRC_FILE" >&2; exit 1; }

OPTION_ORDER=(
    arrow-history-search
)

declare -A OPT_SUMMARY
declare -A OPT_DETAIL
declare -A OPT_LINES

OPT_SUMMARY[arrow-history-search]="Prefix history search on Up/Down: type part of a command, Up cycles only matching history"
OPT_DETAIL[arrow-history-search]="Type 'git' then press Up: it cycles only commands that started with 'git', instead of your whole history. On an empty line, Up/Down still behave exactly as before. If you already use OverKeys, you may already have this; enabling it here is harmless (same function, just bound twice) and makes it work even without OverKeys installed."
OPT_LINES[arrow-history-search]='# Prefix history search: type something, then Up/Down cycles only matching history
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search'

block_marker_begin() { echo "# >>> syskit-zsh-keybindings: $1 >>>"; }
block_marker_end()   { echo "# <<< syskit-zsh-keybindings: $1 <<<"; }

is_enabled() {
    grep -qF "$(block_marker_begin "$1")" "$ZSHRC_FILE" 2>/dev/null
}

find_marker_line() {
    grep -n -Fx "$MARKER" "$ZSHRC_FILE" 2>/dev/null | head -1 | cut -d: -f1
}

remove_block() {
    local id="$1" tmp
    tmp=$(mktemp) || return 1
    awk -v b="$(block_marker_begin "$id")" -v e="$(block_marker_end "$id")" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip == 1 { next }
        { print }
    ' "$ZSHRC_FILE" > "$tmp" && mv "$tmp" "$ZSHRC_FILE"
}

add_block() {
    local id="$1" tmp line bodyfile
    remove_block "$id"   # idempotent: never leaves a duplicate copy
    bodyfile=$(mktemp) || return 1
    {
        echo ""
        block_marker_begin "$id"
        printf '%s\n' "${OPT_LINES[$id]}"
        block_marker_end "$id"
    } > "$bodyfile"
    line=$(find_marker_line)
    if [[ -n "$line" ]]; then
        tmp=$(mktemp) || { rm -f "$bodyfile"; return 1; }
        # Read the (possibly multi-line) block from a file with getline, rather than
        # passing it through awk -v, which chokes on embedded newlines ("newline in string").
        awk -v n="$line" -v bf="$bodyfile" '
            NR == n { while ((getline l < bf) > 0) print l }
            { print }
        ' "$ZSHRC_FILE" > "$tmp" && mv "$tmp" "$ZSHRC_FILE"
    else
        cat "$bodyfile" >> "$ZSHRC_FILE"
    fi
    rm -f "$bodyfile"
}

# Drops leading blank lines and collapses runs of blank lines to one, so
# repeated enable/disable cycles don't pile up empty lines over time.
squeeze_blank_lines() {
    local tmp
    tmp=$(mktemp) || return 1
    awk '
        BEGIN { started = 0; blank = 0 }
        /^[[:space:]]*$/ {
            if (!started) next
            blank++
            if (blank > 1) next
            print ""
            next
        }
        { started = 1; blank = 0; print }
    ' "$ZSHRC_FILE" > "$tmp" && mv "$tmp" "$ZSHRC_FILE"
}

echo "Zsh keybinding (~/.zshrc) option picker. Affects zsh, not bash."
echo "Blocks are inserted above the '$MARKER' marker, so new1-zshrc.sh --clean won't remove them."
echo "Nothing changes until you choose e or d for an option."
echo

for id in "${OPTION_ORDER[@]}"; do
    if is_enabled "$id"; then state="enabled"; else state="disabled"; fi
    echo "-------------------------------------------------------------------"
    echo "${OPT_SUMMARY[$id]}"
    echo "${OPT_DETAIL[$id]}" | fold -s -w 78
    echo
    echo "Currently: $state"
    read -r -p "[e]nable, [d]isable, [s]kip (default), [q]uit: " ans
    case "$ans" in
        e|E) add_block "$id";    echo "-> enabled" ;;
        d|D) remove_block "$id"; echo "-> disabled" ;;
        q|Q) echo "Stopping. Later options left unchanged."; break ;;
        *)   echo "-> left as $state" ;;
    esac
    echo
done

squeeze_blank_lines

echo "Done."
echo "To apply this in your CURRENT zsh session: source ~/.zshrc"
echo "New zsh sessions pick it up automatically. bash is not affected."
