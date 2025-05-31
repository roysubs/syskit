#!/usr/bin/expect -f
# Author: Roy Wiseman 2025-03
# Start session with 'tmux new -s moria_session'.
# Start moria and get to the character stat rolling screen.
# C-b d (detach from session).
# After Expect completes, 'tmux attach' to return to the session.

# Attach to the tmux session and start rerolling
spawn tmux send-keys -t moria_session " " C-m

# Function to handle the rerolling process
proc reroll {} {
    expect {
        -re {INT\s+:\s+18\/([0-9]{2})} {
            set int_value $expect_out(1,string)
            if {[string length $int_value] == 2 && [string range $int_value 0 0] >= 5} {
                send_user "Value of '18/$int_value' found.\n"
                exit 0
            }
        }
        "Hit space to re-roll or ESC to accept characteristics:" {
            send " "
            exp_continue
        }
    }
}

# Loop to keep rerolling until the desired stat is found
while {1} {
    reroll
}

