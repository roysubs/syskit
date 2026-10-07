#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10
#
# Interactive, idempotent picker for ~/.inputrc (readline) options.
# Affects bash and anything else linked against readline. It does NOT affect
# zsh, which has its own line editor and ignores ~/.inputrc. If you want the
# same behaviour in zsh, it needs a separate bindkey-based script.
#
# Each option is its own marked block in ~/.inputrc, so it can be enabled or
# disabled on its own without touching the others or anything you added by
# hand. Re-running this script shows the current state of every option and
# changes only what you choose.
#
# These bindings only ADD to the defaults; none of them are turned on by
# running this script. You choose each one.

INPUTRC_FILE="$HOME/.inputrc"
touch "$INPUTRC_FILE" 2>/dev/null || { echo "Error: cannot write to $INPUTRC_FILE" >&2; exit 1; }

# Order to present the options in. The history search one is first, since
# it's the one most people ask for.
OPTION_ORDER=(
    arrow-history-search
    ctrl-j-search-fwd
    ctrl-k-search-bwd
    alt-r-search-bwd
    alt-s-search-fwd
    ctrl-backspace-kill-word
    ctrl-home-kill-to-start
    ctrl-end-kill-to-end
    tab-menu-complete
    shift-tab-menu-complete-back
    show-all-if-ambiguous
    completion-ignore-case
    completion-query-items
)

declare -A OPT_SUMMARY
declare -A OPT_DETAIL
declare -A OPT_LINES

OPT_SUMMARY[arrow-history-search]="Prefix history search on Up/Down: type part of a command, Up cycles only matching history"
OPT_DETAIL[arrow-history-search]="This is the readline equivalent of what you already get in zsh (via OverKeys, not syskit). Type 'git' then press Up: it cycles only commands that started with 'git', instead of your whole history. On an empty line, Up/Down still behave exactly as before."
OPT_LINES[arrow-history-search]='# Prefix history search: type something, then Up/Down cycles only matching history
"\e[A": history-search-backward
"\e[B": history-search-forward'

OPT_SUMMARY[ctrl-j-search-fwd]="Ctrl-j: forward incremental history search"
OPT_DETAIL[ctrl-j-search-fwd]="Starts a forward incremental search (used after a backward search has begun). This OVERRIDES the default Ctrl-j, which is 'newline', the same as Enter. Ctrl-j for Enter is rarely used on purpose, but if you ever do, this changes it."
OPT_LINES[ctrl-j-search-fwd]='"\C-j": forward-i-search'

OPT_SUMMARY[ctrl-k-search-bwd]="Ctrl-k: backward incremental history search"
OPT_DETAIL[ctrl-k-search-bwd]="Starts a reverse incremental search. This OVERRIDES the default Ctrl-k, which is 'kill-line' (delete from the cursor to the end of the line). Skip this if you use Ctrl-k to delete to end of line."
OPT_LINES[ctrl-k-search-bwd]='"\C-k": backward-i-search'

OPT_SUMMARY[alt-r-search-bwd]="Alt-r: a second way to start a backward incremental search"
OPT_DETAIL[alt-r-search-bwd]="Alt-r is unbound by default (the usual binding is Ctrl-r), so this adds a second way to do the same thing without overriding anything."
OPT_LINES[alt-r-search-bwd]='"\M-r": backward-i-search'

OPT_SUMMARY[alt-s-search-fwd]="Alt-s: a second way to start a forward incremental search"
OPT_DETAIL[alt-s-search-fwd]="Alt-s is unbound by default. Adds a second way to search forward after a backward search has begun."
OPT_LINES[alt-s-search-fwd]='"\M-s": forward-i-search'

OPT_SUMMARY[ctrl-backspace-kill-word]="Ctrl-Backspace: delete the whole word before the cursor"
OPT_DETAIL[ctrl-backspace-kill-word]="Binds the DEL byte (\\C-?) to delete-whole-word. CAUTION: on many terminals, plain Backspace sends this same byte. If that's true for your terminal, this replaces normal single-character Backspace with delete-whole-word. Test it before relying on it. If it breaks plain Backspace, disable this and use Ctrl-w instead, which this option doesn't touch."
OPT_LINES[ctrl-backspace-kill-word]='"\C-?": backward-kill-word'

OPT_SUMMARY[ctrl-home-kill-to-start]="Ctrl-Home: delete from the cursor to the start of the line"
OPT_DETAIL[ctrl-home-kill-to-start]="The escape sequence for Ctrl-Home (\\e[1;5H here) is terminal-dependent. If it doesn't do anything in your terminal, run 'showkey -a' or 'cat -v', press Ctrl-Home, and use the code it actually sends."
OPT_LINES[ctrl-home-kill-to-start]='"\e[1;5H": backward-kill-line'

OPT_SUMMARY[ctrl-end-kill-to-end]="Ctrl-End: delete from the cursor to the end of the line"
OPT_DETAIL[ctrl-end-kill-to-end]="Same caveat as Ctrl-Home: the sequence (\\e[1;5F here) is terminal-dependent. The standard Ctrl-k already does this without needing a special sequence."
OPT_LINES[ctrl-end-kill-to-end]='"\e[1;5F": kill-line'

OPT_SUMMARY[tab-menu-complete]="Tab cycles through completions directly, instead of listing them"
OPT_DETAIL[tab-menu-complete]="Default bash: Tab completes the common prefix, a second Tab lists every match. This changes Tab itself to cycle through each match one at a time, like Windows cmd.exe. This changes something you use constantly: only turn it on if you already know you want it. Some people like it, some find it gets in the way."
OPT_LINES[tab-menu-complete]='TAB: menu-complete'

OPT_SUMMARY[shift-tab-menu-complete-back]="Shift-Tab cycles backward through completions"
OPT_DETAIL[shift-tab-menu-complete-back]="Only useful together with the Tab-cycles option above, to step back if you cycled past the one you wanted."
OPT_LINES[shift-tab-menu-complete-back]='"\e[Z": menu-complete-backward'

OPT_SUMMARY[show-all-if-ambiguous]="List every match on the first Tab press, instead of the second"
OPT_DETAIL[show-all-if-ambiguous]="Default bash: the first Tab with several matches just beeps; the second Tab lists them. This lists them straight away on the first press."
OPT_LINES[show-all-if-ambiguous]='set show-all-if-ambiguous on'

OPT_SUMMARY[completion-ignore-case]="Case-insensitive tab completion"
OPT_DETAIL[completion-ignore-case]="Typing 'doc' and pressing Tab will also match 'Documents'. Some people rely on this; others actively dislike it, since it can complete to a name in a different case than you typed. Decide for yourself; don't assume everyone wants it."
OPT_LINES[completion-ignore-case]='set completion-ignore-case on'

OPT_SUMMARY[completion-query-items]="Don't ask \"Display all possibilities?\" until there are 200+ matches"
OPT_DETAIL[completion-query-items]="Default bash asks for confirmation before listing more than 100 matches. This raises that to 200, so wide directories prompt less often."
OPT_LINES[completion-query-items]='set completion-query-items 200'

block_marker_begin() { echo "# >>> syskit-inputrc: $1 >>>"; }
block_marker_end()   { echo "# <<< syskit-inputrc: $1 <<<"; }

is_enabled() {
    grep -qF "$(block_marker_begin "$1")" "$INPUTRC_FILE" 2>/dev/null
}

remove_block() {
    local id="$1" tmp
    tmp=$(mktemp) || return 1
    awk -v b="$(block_marker_begin "$id")" -v e="$(block_marker_end "$id")" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip == 1 { next }
        { print }
    ' "$INPUTRC_FILE" > "$tmp" && mv "$tmp" "$INPUTRC_FILE"
}

add_block() {
    local id="$1"
    remove_block "$id"   # idempotent: never leaves a duplicate copy
    {
        echo ""
        block_marker_begin "$id"
        printf '%s\n' "${OPT_LINES[$id]}"
        block_marker_end "$id"
    } >> "$INPUTRC_FILE"
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
    ' "$INPUTRC_FILE" > "$tmp" && mv "$tmp" "$INPUTRC_FILE"
}

echo "Readline (~/.inputrc) option picker. Affects bash, not zsh."
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
echo "To apply this in your CURRENT bash session: bind -f ~/.inputrc"
echo "New bash sessions pick it up automatically. zsh is not affected."
