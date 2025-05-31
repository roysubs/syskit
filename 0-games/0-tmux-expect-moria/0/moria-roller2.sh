#!/usr/bin/expect -f
# Author: Roy Wiseman 2025-05
# Ensure the tmux session is set up and Moria is at the rolling screen before running.
# Start session with 'tmux new -s moria_session'.
# Start moria and get to the character stat rolling screen.
# C-b d (detach from session).
# After Expect completes, 'tmux attach' to return to the session.
#
# To watch the progress within tmux:
# Option A: To see a snapshot of the tmux session:     tmux capture-pane -t moria_session -p
# To attach view-only and watch the rolling:           tmux attach -t moria_session
# Alternatively, start with split-window view output:  tmux split-window -t moria_session

# Attach to the tmux session and send initial keypress
exec tmux send-keys -t moria_session " " C-m

# Function to capture pane output and reroll
proc reroll {} {
    # Capture the current tmux pane output
    set pane_output [exec tmux capture-pane -t moria_session -p]
    
    # Check for the desired stat pattern
    if {[regexp {INT\s+:\s+18\/([0-9]{2})} $pane_output match int_value]} {
        # Extract INT value
        if {[string length $int_value] == 2 && [string range $int_value 0 0] >= 5} {
            send_user "Value of '18/$int_value' found.\n"
            exit 0
        }
    }
    
    # If not found, send space to reroll
    exec tmux send-keys -t moria_session " " C-m
}

# Loop to keep rerolling until the desired stat is found
while {1} {
    reroll
    # Small delay to allow Moria to render the new roll
    sleep 0.1
}

