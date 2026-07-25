osascript -e 'tell application "QuickTime Player"
    set new_recording to (new screen recording)
    tell new_recording to start
    delay 5
    tell new_recording to stop
end tell'
