#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10

# finder-hidden-files-mac.sh — show or hide hidden files in Finder (macOS only; this
# toggles a Finder preference, which doesn't exist on Linux).
#
# Usage:
#   finder-hidden-files-mac.sh            Toggle (show if hidden, hide if shown)
#   finder-hidden-files-mac.sh on|show    Show hidden files
#   finder-hidden-files-mac.sh off|hide   Hide hidden files (the default)
#   finder-hidden-files-mac.sh status     Show the current state, change nothing
#
# Restarts Finder to apply the change, which closes any open Finder windows.

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This toggles a Finder preference, so it's macOS only." >&2
    exit 1
fi

current_raw=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)
case "$current_raw" in
    1|true|YES) current_state="on" ;;
    *)          current_state="off" ;;
esac

case "${1:-toggle}" in
    status)
        echo "Hidden files in Finder: $current_state"
        exit 0
        ;;
    on|show)
        new_state="on" ;;
    off|hide)
        new_state="off" ;;
    toggle)
        if [[ "$current_state" == "on" ]]; then new_state="off"; else new_state="on"; fi
        ;;
    -h|--help)
        echo "Usage: $(basename "$0") [on|off|status]"
        exit 0
        ;;
    *)
        echo "Usage: $(basename "$0") [on|off|status]" >&2
        exit 1
        ;;
esac

if [[ "$new_state" == "$current_state" ]]; then
    echo "Hidden files in Finder already $current_state."
    exit 0
fi

if [[ "$new_state" == "on" ]]; then
    defaults write com.apple.finder AppleShowAllFiles -bool true
else
    defaults write com.apple.finder AppleShowAllFiles -bool false
fi

echo "Hidden files in Finder: $new_state"
echo "Restarting Finder to apply this (closes any open Finder windows)..."
killall Finder 2>/dev/null || true
