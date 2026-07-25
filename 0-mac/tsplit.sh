#!/bin/bash

# tsplit.sh - Opens a new Terminal window and splits screen 50/50 with the current one.
# Can be run from command line: ./tsplit.sh

osascript -e '
tell application "Terminal"
    if not (exists window 1) then reopen
    set win1 to window 1
    
    -- Get screen dimensions dynamically
    tell application "Finder" to set screen_bounds to bounds of window of desktop
    set screen_width to item 3 of screen_bounds
    set screen_height to item 4 of screen_bounds

    -- Resize current window to Left Half
    set bounds of win1 to {0, 0, screen_width / 2, screen_height}
    
    -- Open new window
    do script "" 
    set win2 to window 1
    
    -- Resize new window to Right Half
    set bounds of win2 to {screen_width / 2, 0, screen_width, screen_height}
    
    activate
end tell'
