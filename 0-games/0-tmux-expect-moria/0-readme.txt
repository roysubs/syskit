================================================================================
 Automated Moria Stat Roller (tmux controller)
================================================================================

This project demonstrates automating character stat dice rolling to roll high
attributes (STR, INT, WIS, DEX, CON, CHR) for Moria / UMoria characters.

The roller script interacts with a detached tmux session running Moria like a
headless container, reading the screen via `tmux capture-pane` and rolling dice
via `tmux send-keys`. When the target stat is found, it locks in the character
with ESC and logs the winning roll.

We provide two scripts:
  - moria-roller.sh   : Pure Bash script (fast, portable, live on-screen status)
  - moria-roller.exp  : Expect / Tcl script (classic Expect controller)

Both scripts accept arbitrary target stats and thresholds!

--------------------------------------------------------------------------------
 Quick Start Guide
--------------------------------------------------------------------------------

1. Start a tmux session named 'moria_session':
     tmux new -s moria_session

2. Start Moria inside tmux, pick your race and class, and proceed to the dice
   roller screen:
     "Hit space to re-roll or ESC to accept characteristics:"

3. Detach from the session without closing the game:
     Press Ctrl-b, then press d

4. Run the roller script with your desired stat and target value:
     ./moria-roller.sh                     # Default: INT >= 18/20
     ./moria-roller.sh STR                 # Target STR >= 18/20
     ./moria-roller.sh STR 18/50           # Target STR >= 18/50 (Warriors)
     ./moria-roller.sh INT 18/60           # Target INT >= 18/60 (Mages)
     ./moria-roller.sh DEX 18              # Target DEX >= 18    (Rogues)
     ./moria-roller.sh CON 18/100          # Maximum possible stat in Moria!

   Note: Quotes around 18/50 are completely optional in Bash!
   Both `STR 18/50` and `STR "18/50"` work identically.

5. After the script finishes and locks in your character, re-attach to play:
     tmux attach -t moria_session

--------------------------------------------------------------------------------
 Running in Background
--------------------------------------------------------------------------------

- Run in background with nohup:
    nohup ./moria-roller.sh STR 18/50 > moria-roller.out 2>&1 &

- Or run inside a second runner tmux session:
    tmux new -s roller_runner -d
    tmux send-keys -t roller_runner "./moria-roller.sh STR 18/50" C-m

--------------------------------------------------------------------------------
 Monitoring Progress While Rolling
--------------------------------------------------------------------------------

- Live terminal status (if running foreground):
    [ROLLING] Attempt: 421 | Current STR: 16 | Highest: 18/38 | Elapsed: 00:23

- View a live snapshot of the game screen:
    tmux capture-pane -t moria_session -p

- Watch the dice rolling in real time (view-only):
    tmux attach -r -t moria_session

- Split the current window to monitor side-by-side:
    tmux split-window -t moria_session