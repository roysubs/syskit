#!/bin/bash
# Author: Roy Wiseman 2025-04

# Check zangband exists, install if missing (silent)
command -v zangband >/dev/null 2>&1 || sudo apt install -y zangband

SESSION="zangband_session"

# If session exists, attach to it
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach-session -t "$SESSION"
  exit
fi

# Create new session that:
# 1. Disables tmux status bar
# 2. Runs zangband
# 3. On exit, kills the session automatically
tmux new-session -s "$SESSION" -n game bash -c "
  tmux set-option status off;
  zangband;
  tmux kill-session -t '$SESSION'
"

# Some roguelikes can alter screen colours that affect the console session, particularly
# if connected over SSH. This might not affect all sessions, but if it happens, the
# only fix is to quit the terminal. Using tome-gcu-mux.sh gets around this by isolating
# the roguelike inside a dedicated tmux session.
#
# 'set-option status off' suppresses the green tmux status bar when in game.
# '-g status' would suppress the tmux bar globally for all tmux sessions.
