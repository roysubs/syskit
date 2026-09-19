#!/usr/bin/env bash
# Author: Roy Wiseman
# Automated character stat roller for Moria inside a tmux session

set -e

# Default settings
SESSION="moria_session"
STAT="INT"
TARGET="18/20"
DELAY="0.06"
MAX_ROLLS=0
LOG_FILE="moria-roller.log"
LOCK_IN=1

show_help() {
    cat << 'EOF'
Usage: moria-roller.sh [OPTIONS] [STAT] [TARGET]

Automate character stat rolling for Moria inside a tmux session.

Arguments:
  STAT                Attribute to target: STR, INT, WIS, DEX, CON, CHR (default: INT)
  TARGET              Minimum desired value (default: 18/20)
                      Quotes are optional! Both 'STR 18/50' and 'STR "18/50"' work.
                      Examples: 17, 18, 18/20, 18/50, 18/75, 18/100

Options:
  -s, --session NAME  tmux session name (default: moria_session)
  -d, --delay SECS    Delay between rolls in seconds (default: 0.06)
  -m, --max ROLLS     Maximum attempts before stopping (default: 0 = unlimited)
  -l, --log FILE      Custom log file (default: moria-roller.log)
  --no-lock           Do not send ESC to lock in characteristics on match
  -h, --help          Show this help message and exit

Workflow:
  1. Start a tmux session:
       tmux new -s moria_session
  2. Inside tmux, start Moria, select race and class, and proceed to the
     dice rolling screen: "Hit space to re-roll or ESC to accept characteristics:"
  3. Detach from tmux using: Ctrl-b d
  4. Run this script:
       ./moria-roller.sh INT 18/30
  5. When finished, re-attach to your character:
       tmux attach -t moria_session

Examples:
  ./moria-roller.sh                   # Target INT >= 18/20
  ./moria-roller.sh STR               # Target STR >= 18/20
  ./moria-roller.sh STR 18/50         # Target STR >= 18/50
  ./moria-roller.sh DEX 18            # Target DEX >= 18
  ./moria-roller.sh CON 18/100        # Target CON == 18/100 (Maximum!)
  ./moria-roller.sh -d 0.03 INT 18/50 # Fast rolling mode (30ms delay)
EOF
}

# Parse options
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--session)
            SESSION="$2"
            shift 2
            ;;
        -d|--delay)
            DELAY="$2"
            shift 2
            ;;
        -m|--max)
            MAX_ROLLS="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        --no-lock)
            LOCK_IN=0
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -ge 1 ]]; then
    STAT=$(echo "${POSITIONAL[0]}" | tr '[:lower:]' '[:upper:]')
fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then
    TARGET="${POSITIONAL[1]}"
fi

# Validate STAT name
case "$STAT" in
    STR|INT|WIS|DEX|CON|CHR) ;;
    *)
        echo "Error: Unknown stat '$STAT'. Choose from: STR, INT, WIS, DEX, CON, CHR" >&2
        exit 1
        ;;
esac

# Function to convert Moria stat string (e.g. 17, 18, 18/20, 18/100) to an integer score
stat_to_score() {
    local val="$1"
    if [[ "$val" =~ 18/([0-9]+) ]]; then
        local sub="${BASH_REMATCH[1]}"
        sub=$((10#$sub))
        echo $((1800 + sub))
    elif [[ "$val" =~ ^([0-9]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        echo $((10#$num * 100))
    else
        echo 0
    fi
}

TARGET_SCORE=$(stat_to_score "$TARGET")
if [[ "$TARGET_SCORE" -eq 0 ]]; then
    echo "Error: Invalid target stat format '$TARGET'. Use values like 17, 18, 18/20, 18/50, 18/100." >&2
    exit 1
fi

# Verify tmux session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    cat << EOF >&2
Error: tmux session '$SESSION' does not exist!

To set it up:
  1) Start tmux: tmux new -s $SESSION
  2) Run Moria, choose your race/class, and reach the dice rolling screen.
  3) Detach: press Ctrl-b then d
  4) Run: $0 $STAT $TARGET
EOF
    exit 1
fi

echo "=========================================================="
echo " Moria Stat Roller (tmux controller)"
echo " Session : $SESSION"
echo " Target  : $STAT >= $TARGET (score: $TARGET_SCORE)"
echo " Delay   : ${DELAY}s per roll"
echo " Log file: $LOG_FILE"
echo "=========================================================="

START_TIME=$(date +%s)
ROLLS=0
HIGHEST_SCORE=0
HIGHEST_STR="N/A"

# Graceful exit on Ctrl+C
trap 'echo -e "\n\nAborted by user. Total rolls: $ROLLS"; exit 130' INT TERM

while true; do
    PANE=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)

    if [[ -z "$PANE" ]]; then
        echo -e "\nWarning: Failed to capture tmux pane. Retrying in 1s..."
        sleep 1
        continue
    fi

    # Check if Moria is currently on the dice rolling screen
    if [[ ! "$PANE" =~ "Hit space to re-roll or ESC to accept" ]]; then
        echo -e "\n[PAUSED] Waiting for Moria stat rolling prompt in '$SESSION'..."
        sleep 1
        continue
    fi

    ((ROLLS++))

    # Extract target stat
    CURRENT_VAL=""
    if [[ "$PANE" =~ $STAT[[:space:]]*:[[:space:]]*([1-9][0-9]*(/[0-9]+)?) ]]; then
        CURRENT_VAL="${BASH_REMATCH[1]}"
    fi

    CURRENT_SCORE=$(stat_to_score "$CURRENT_VAL")

    if (( CURRENT_SCORE > HIGHEST_SCORE )); then
        HIGHEST_SCORE=$CURRENT_SCORE
        HIGHEST_STR="$CURRENT_VAL"
    fi

    # Format elapsed time
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    MINS=$((ELAPSED / 60))
    SECS=$((ELAPSED % 60))
    TIME_STR=$(printf "%02d:%02d" $MINS $SECS)

    # Live status line
    printf "\r[ROLLING] Attempt: %d | Current %s: %-6s | Highest: %-6s | Elapsed: %s" \
        "$ROLLS" "$STAT" "$CURRENT_VAL" "$HIGHEST_STR" "$TIME_STR"

    # Check target reached
    if (( CURRENT_SCORE >= TARGET_SCORE )); then
        echo -e "\n\n=========================================================="
        echo -e " [SUCCESS] Found target $STAT = $CURRENT_VAL on attempt #$ROLLS!"
        echo -e " Time elapsed: ${MINS}m ${SECS}s"

        if [[ "$LOCK_IN" -eq 1 ]]; then
            tmux send-keys -t "$SESSION" Escape
            echo " Character characteristics locked in with ESC."
        else
            echo " Characteristics left open at prompt (--no-lock specified)."
        fi

        # Extract full stats for summary & logging
        STR_VAL=$(echo "$PANE" | grep -oP 'STR\s*:\s*\K\S+' || echo "N/A")
        INT_VAL=$(echo "$PANE" | grep -oP 'INT\s*:\s*\K\S+' || echo "N/A")
        WIS_VAL=$(echo "$PANE" | grep -oP 'WIS\s*:\s*\K\S+' || echo "N/A")
        DEX_VAL=$(echo "$PANE" | grep -oP 'DEX\s*:\s*\K\S+' || echo "N/A")
        CON_VAL=$(echo "$PANE" | grep -oP 'CON\s*:\s*\K\S+' || echo "N/A")
        CHR_VAL=$(echo "$PANE" | grep -oP 'CHR\s*:\s*\K\S+' || echo "N/A")

        echo " --------------------------------------------------------"
        echo " STR: $STR_VAL | INT: $INT_VAL | WIS: $WIS_VAL"
        echo " DEX: $DEX_VAL | CON: $CON_VAL | CHR: $CHR_VAL"
        echo " =========================================================="
        echo " To play your character, attach to tmux:"
        echo "   tmux attach -t $SESSION"
        echo " =========================================================="

        # Log entry
        TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
        {
            echo "[$TIMESTAMP] SUCCESS: Found $STAT=$CURRENT_VAL (Target: $TARGET) after $ROLLS rolls ($TIME_STR)"
            echo "  STR: $STR_VAL | INT: $INT_VAL | WIS: $WIS_VAL | DEX: $DEX_VAL | CON: $CON_VAL | CHR: $CHR_VAL"
            echo "----------------------------------------------------------------------------------"
        } >> "$LOG_FILE"

        # Audible terminal alert
        printf "\a"
        exit 0
    fi

    # Check max rolls safety cutoff
    if (( MAX_ROLLS > 0 && ROLLS >= MAX_ROLLS )); then
        echo -e "\n\nReached maximum configured rolls ($MAX_ROLLS) without finding $STAT >= $TARGET."
        exit 1
    fi

    # Send space to reroll
    tmux send-keys -t "$SESSION" " "
    sleep "$DELAY"
done