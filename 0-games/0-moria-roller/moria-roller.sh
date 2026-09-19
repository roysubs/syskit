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
LOCK_IN=1
AUTO_START=0
NEW_RACE=""
NEW_CLASS=""
NEW_SEX=""

# Ensure log directory is in ~/.moria-roller to keep syskit repo clean
LOG_DIR="${HOME}/.moria-roller"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/moria-roller.log"

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
  --new [RACE] [CLASS] [SEX]
                      Automatically create a new tmux session and start Moria!
                      Steps 1, 2, and 3 are completely automated.
                      Example: ./moria-roller.sh --new troll warrior male STR 18/50
                      If arguments omitted, prompts interactively.
  -s, --session NAME  tmux session name (default: moria_session)
  -d, --delay SECS    Delay between rolls in seconds (default: 0.06)
  -m, --max ROLLS     Maximum attempts before stopping (default: 0 = unlimited)
  -l, --log FILE      Custom log file (default: ~/.moria-roller/moria-roller.log)
  --no-lock           Do not send ESC to lock in characteristics on match
  -h, --help          Show this help message and exit

Moria Stat Rolling Mechanics Note:
  In Moria, race and class modifiers apply to your base roll!
  - Mages have a -5 STR penalty (Elf Mage has -6 STR), so starting STR is
    capped at ~12-14. An Elf Mage will NEVER roll STR 18/XX!
  - To roll STR 18/XX, choose a race/class with STR bonuses:
      Half-Troll Warrior (+5 STR) -> Can roll up to 18/70+ STR!
      Dwarf Warrior      (+4 STR) -> Easily rolls 18/50+ STR!
  - To roll INT 18/XX, choose Elf Mage or Gnome Mage (+5 INT).

Examples:
  ./moria-roller.sh INT 18/50                       # Roll in existing session
  ./moria-roller.sh --new troll warrior male STR 18/50 # Full 1-step automation!
  ./moria-roller.sh --new elf mage male INT 18/60   # Full 1-step automation for Mage!
EOF
}

resolve_race_key() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|human|h)               echo "a" ;;
        2|half-elf|halfelf|he)   echo "b" ;;
        3|elf|e)                 echo "c" ;;
        4|halfling|hf)           echo "d" ;;
        5|gnome|g)               echo "e" ;;
        6|dwarf|d)               echo "f" ;;
        7|half-orc|halforc|ho)   echo "g" ;;
        8|half-troll|halftroll|troll|ht|t) echo "h" ;;
        *)                       echo "" ;;
    esac
}

resolve_class_key() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|warrior|w) echo "a" ;;
        2|mage|m)    echo "b" ;;
        3|priest|p)  echo "c" ;;
        4|rogue|ro)  echo "d" ;;
        5|ranger|ra) echo "e" ;;
        6|paladin|pa) echo "f" ;;
        *)           echo "" ;;
    esac
}

resolve_sex_key() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|m|male)   echo "m" ;;
        2|f|female) echo "f" ;;
        *)          echo "m" ;;
    esac
}

# Parse options
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --new|--auto)
            AUTO_START=1
            shift
            # Check if race/class/sex were supplied as parameters
            if [[ $# -gt 0 && ! "$1" =~ ^- && ! "$1" =~ ^(STR|INT|WIS|DEX|CON|CHR)$ ]]; then
                NEW_RACE="$1"; shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- && ! "$1" =~ ^(STR|INT|WIS|DEX|CON|CHR)$ ]]; then
                NEW_CLASS="$1"; shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- && ! "$1" =~ ^(STR|INT|WIS|DEX|CON|CHR)$ ]]; then
                NEW_SEX="$1"; shift
            fi
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

# Function to convert Moria stat string to integer score
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

# Automate Steps 1, 2, 3 if requested or if session is missing
start_moria_automatically() {
    echo "=========================================================="
    echo " Automated Moria Character Setup (Steps 1, 2, 3)"
    echo "=========================================================="

    if [[ -z "$NEW_RACE" ]]; then
        echo "Select Race:"
        echo "  1) Human      2) Half-Elf   3) Elf       4) Halfling"
        echo "  5) Gnome      6) Dwarf      7) Half-Orc  8) Half-Troll"
        read -r -p "Enter choice [1-8] (default: 3 Elf): " r_choice
        NEW_RACE="${r_choice:-3}"
    fi
    RACE_KEY=$(resolve_race_key "$NEW_RACE")
    [[ -z "$RACE_KEY" ]] && RACE_KEY="c"

    if [[ -z "$NEW_SEX" ]]; then
        read -r -p "Select Sex [m/f] (default: m): " s_choice
        NEW_SEX="${s_choice:-m}"
    fi
    SEX_KEY=$(resolve_sex_key "$NEW_SEX")

    if [[ -z "$NEW_CLASS" ]]; then
        echo "Select Class:"
        echo "  1) Warrior    2) Mage       3) Priest"
        echo "  4) Rogue      5) Ranger     6) Paladin"
        read -r -p "Enter choice [1-6] (default: 2 Mage): " c_choice
        NEW_CLASS="${c_choice:-2}"
    fi
    CLASS_KEY=$(resolve_class_key "$NEW_CLASS")
    [[ -z "$CLASS_KEY" ]] && CLASS_KEY="b"

    echo "-> Step 1: Spawning background tmux session '$SESSION'..."
    tmux new-session -d -s "$SESSION" "moria"
    sleep 0.6

    echo "-> Step 2: Passing intro and selecting character..."
    # Clear intro / title screen
    tmux send-keys -t "$SESSION" " "
    sleep 0.3
    # Send Race
    tmux send-keys -t "$SESSION" "$RACE_KEY"
    sleep 0.3
    # Send Sex
    tmux send-keys -t "$SESSION" "$SEX_KEY"
    sleep 0.3
    # Send Class
    tmux send-keys -t "$SESSION" "$CLASS_KEY"
    sleep 0.5

    # Verify we reached the dice rolling screen
    READY=0
    for i in {1..10}; do
        PANE=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)
        if [[ "$PANE" =~ "Hit space to re-roll or ESC to accept" ]]; then
            READY=1
            break
        fi
        sleep 0.3
    done

    if [[ "$READY" -eq 1 ]]; then
        echo "-> Step 3: [SUCCESS] Moria is ready at the dice roller screen!"
    else
        echo "-> [NOTICE] Session created. Waiting for Moria prompt..."
    fi
}

# Verify tmux session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    if [[ "$AUTO_START" -eq 1 ]]; then
        start_moria_automatically
    elif [ -t 0 ]; then
        echo "tmux session '$SESSION' not found."
        read -r -p "Would you like to automatically launch Moria and create a character? [Y/n] " ans
        if [[ "$ans" =~ ^[Yy]?$ ]]; then
            start_moria_automatically
        else
            echo "Aborted."
            exit 1
        fi
    else
        cat << EOF >&2
Error: tmux session '$SESSION' does not exist!

To automate setup completely, run:
  $0 --new [race] [class] [sex] $STAT $TARGET
Example:
  $0 --new troll warrior male STR 18/50

Or manually start Moria:
  1) tmux new -s $SESSION moria
  2) Pick race & class to reach stat roller
  3) Detach with Ctrl-b d
  4) Run: $0 $STAT $TARGET
EOF
        exit 1
    fi
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

        # Log entry to ~/.moria-roller/moria-roller.log
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