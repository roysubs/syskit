#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
osascript -e 'tell application "QuickTime Player"
    set new_recording to (new screen recording)
    tell new_recording to start
    delay 5
    tell new_recording to stop
end tell'
