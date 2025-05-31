This script will demonstrate automating stat dice rolling to get a very high
INT for a mage character in Moria. The expect script will perform keypresses
*inside* a tmux session that runs in the background like a container, while
the tmux session is a subshell process of the current shell. This is also
just in general a good example of using tmux sessions like subshell containers.
 
- Start a tmux session with 'tmux new -s moria_session' so that expect can
  use this name to control the session.

- Start Moria, pick race, sex, and get to the dice roller screen.
  i.e., the "Hit space to re-roll or ESC to accept characteristics:" prompt.

- Do not kill or background Moria, just detach from the tmux session with
  'C-b d' (C-b means Ctrl-b, the tmux control key).

- Run the expect script which will start automating the dice rolls until it
  rolls at least 18/20 in INT as set in the .exp script, when it will stop.
    nohup ./moria-roller.exp &     # Run in the background with no nohup (nohangups).
  An alternative way to run the expect is from within its own tmux session:
    tmux new -s expect_runner -d   # Creates a new session named expect_runner.
    -d: Starts the session detached (in the background).
  To send the expect command to run the expect script into this new tmux session:
    tmux send-keys -t expect_runner "./moria-roller.exp" C-m
    -t expect_runner: Specifies the target session.
    C-m: Sends the Enter key to execute the command.
  Or, enter the new tmux session, start the command, then detach:
    tmux new -s expect_runner   # Enter new tmux session
    ./moria_roller.exp          # Run, then detach from this session (Ctrl-b d)

- You can watch the progress of the automation while it is running:
  To see a snapshot of the tmux session:      tmux capture-pane -t moria_session -p
  To attach view-only and watch the rolling:  tmux attach -t moria_session
  Or, to start with split-window view output: tmux split-window -t moria_session

- After the script completes, 'tmux attach' to return to the session.
