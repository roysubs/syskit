#!/bin/bash
# Author: Roy Wiseman 2025-05

# Script to download a selection of Z-machine games, extract them,
# find compatible game files (.z#, .dat, .blorb, etc.),
# move them to the current directory with a clean name, and clean up.
# Original requested name: zork-1-2-3-get.sh

# --- Configuration ---
# Target directory for the final game files (current working directory where the script is run)
CWD=$(pwd)
TARGET_DIR="$HOME/games/z-machine"
mkdir -p $TARGET_DIR

# Base temporary directory for downloads and extraction.
# $$ is the script's process ID, making the temp dir unique for concurrent runs.
TMP_BASE_DIR="/tmp/zmachine_games_$$"

# Game definitions: "short_name_for_output_file_prefix" = "download_url_of_zip"
declare -A GAME_DEFINITIONS
GAME_DEFINITIONS=(
    ["zork1"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FZork%20I%20-%20The%20Great%20Underground%20Empire%20v88%20%281983%29%28Infocom%29%5B840726%5D.zip" # Zork I: The Great Underground Empire
    ["zork2"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FZork%20II%20-%20The%20Wizard%20of%20Frobozz%20v48%20%281983%29%28Infocom%29%5B840904%5D.zip" # Zork II: The Wizard of Frobozz
    ["zork3"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FZork%20III%20-%20The%20Dungeon%20Master%20v17%20%281982%29%28Infocom%29%5B840727%5D.zip" # Zork III: The Dungeon Master
    ["beyondzork"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FBeyond%20Zork%20-%20The%20Coconut%20of%20Quendor%20v57%20%281987%29%28Infocom%29.zip" # Beyond Zork: The Coconut of Quendor
    ["enchanter"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FEnchanter%20v29%20%281986%29%28Infocom%29.zip" # Enchanter (Enchanter Trilogy, Book 1)
    ["hitchhiker"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FHitchhiker%27s%20Guide%20to%20the%20Galaxy%20SG%2C%20The%20v31%20%281984%29%28Infocom%29%5B871119%5D.zip" # Hitch-hikers Guide to the Galaxy
    ["minizork1"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FMini-Zork%20I%20-%20The%20Great%20Underground%20Empire%20v34%20%281988%29%28Infocom%29%5B871124%5D.zip" # Mini Zork 1
    ["zorktuu"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FZork%20-%20The%20Undiscovered%20Underground%20v16%20%281997%29%28Activision%29%5B970828%5D.zip" # Zork: The Undiscovered Underground
    ["zorkzero"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FZork%20Zero%20-%20The%20Revenge%20of%20Megaboz%20v383%20%2819xx%29%28Infocom%29%5B890602%5D.zip" # Zork Zero

# --- More Classic Infocom Titles (from archive.org) ---

    # Planetfall, Steve Meretzky (Infocom), 1983, A comedic sci-fi adventure with the memorable robot companion, Floyd.
    ["planetfall"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FPlanetfall%20v37%20%281983%29%28Infocom%29%5B840727%5D.zip"

    # Stationfall, Steve Meretzky (Infocom), 1987, The sequel to Planetfall, continuing the adventures with Floyd.
    ["stationfall"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FStationfall%20v29%20%281987%29%28Infocom%29%5B870225%5D.zip"

    # Wishbringer, Brian Moriarty (Infocom), 1985, A fantasy game with a gentler difficulty, often recommended for beginners.
    ["wishbringer"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FWishbringer%20v38%20%281985%29%28Infocom%29%5B850906%5D.zip"

    # Leather Goddesses of Phobos, Steve Meretzky (Infocom), 1986, A famously risqué and humorous sci-fi adventure.
    ["lgop"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FLeather%20Goddesses%20of%20Phobos%20v45%20%281986%29%28Infocom%29%5BR45%5D%5B860730%5D.zip"

    # Trinity, Brian Moriarty (Infocom), 1986, A complex and highly regarded Cold War-era story with time travel.
    ["trinity"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FTrinity%20v14%20%281986%29%28Infocom%29%5B860619%5D.zip"

    # A Mind Forever Voyaging, Steve Meretzky (Infocom), 1985, A serious story playing as a conscious AI in simulated realities.
    ["amfv"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FMind%20Forever%20Voyaging%2C%20A%20v111%20%281985%29%28Infocom%29%5B850822%5D.zip"

    # The Lurking Horror, Dave Lebling (Infocom), 1987, Infocom's only foray into the horror genre, set in a university.
    ["lurkinghorror"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FLurking%20Horror%2C%20The%20v105%20%281987%29%28Infocom%29%5B870501%5D.zip"

    # --- Acclaimed Modern Freeware Interactive Fiction (from ifarchive.org) ---

    # Photopia, Adam Cadre, 1998, A groundbreaking and influential work known for its narrative structure.
    ["photopia"]="https://ifarchive.org/if-archive/games/competition2000/zcode/photopia/Photopia.zip"

    # Spider and Web, Andrew Plotkin, 1998, A highly acclaimed spy thriller with an inventive "interrogation" mechanic.
    ["spiderweb"]="https://ifarchive.org/if-archive/games/zcode/Spider.zip"

    # Lost Pig, Admiral Jota (pen name for Grunk), 2007, A humorous and charming game where you play as an orc trying to find a lost pig.
    ["lostpig"]="https://ifarchive.org/if-archive/games/ulx/LostPig.zip"

    # Curses, Graham Nelson, 1993, One of the first large games written in Inform, a sprawling puzzle-fest.
    ["curses"]="https://ifarchive.org/if-archive/games/zcode/curses.zip"

    # Anchorhead, Michael S. Gentry, 1998, A substantial and very well-regarded Lovecraftian horror game (classic Z-code version).
    ["anchorhead"]="https://ifarchive.org/if-archive/games/zcode/anchor.zip"

    # Violet, Jeremy Freese, 2008, A poignant story about a graduate student trying to write, with a unique time mechanic.
    ["violet"]="https://ifarchive.org/if-archive/games/glulx/Violet.zip"

)

# Missing:
#     Sorcerer (Enchanter Trilogy, Book 2)
#     Spellbreaker (Enchanter Trilogy, Book 3)
# Not working:
#     ["arthur"]="https://archive.org/download/Infocom_Z-Machine_TOSEC_2012_04_23/Infocom_Z-Machine_TOSEC_2012_04_23.zip/Infocom%20Z-Machine%20%5BTOSEC%5D%2FGames%2FArthur%20-%20The%20Quest%20for%20Excaliber%20v74%20%281989%29%28Infocom%29.zip" # Arthur

# The main Zork series games developed by Infocom, in chronological order of their original release:
# 
# Zork I: The Great Underground Empire
# Original mainframe version: c. 1977-1979 (as "Dungeon" / "Zork") by Tim Anderson, Marc Blank, Bruce Daniels, and Dave Lebling at MIT.
# Commercial Release (Part 1): 1980 (for personal computers)
# 
# Zork II: The Wizard of Frobozz
# Release Date: 1981
# 
# Zork III: The Dungeon Master
# Release Date: 1982
# 
# Enchanter (Start of the "Enchanter Trilogy," set in the Zork universe)
# Release Date: 1983
# (While not titled "Zork," it's a core part of the Zork timeline and lore).
# 
# Sorcerer (Enchanter Trilogy, Book 2)
# Release Date: 1984
# 
# Spellbreaker (Enchanter Trilogy, Book 3)
# Release Date: 1985
# 
# Beyond Zork: The Coconut of Quendor
# Release Date: 1987
# 
# Zork Zero: The Revenge of Megaboz
# Release Date: 1988 (This was a prequel with graphics).
# 
# Other Zork-related titles from Infocom:
# ==========
# 
# Mini-Zork I: A shortened, promotional version of Zork I, released around 1987/1988. (Your script successfully downloaded this as minizork1.z3).
# 
# Post-Infocom Zork Games (Activision and others):
# ==========
#
# After Infocom ceased developing games, Activision (who had acquired Infocom) and other companies released further games in the Zork series. These are generally graphical adventures rather than pure text adventures.
# 
# Return to Zork (Activision, 1993)
# 
# Zork Nemesis: The Forbidden Lands (Activision, 1996)
# 
# Zork: The Undiscovered Underground (Activision, 1997) - This was a free text adventure prequel to Zork Grand Inquisitor, written by original Infocom implementors Marc Blank and Michael Berlyn.
# 
# Zork Grand Inquisitor (Activision, 1997)
# 
# Legends of Zork (Jolt Online Gaming, 2009) - A browser-based online adventure game.

# Game file patterns to search for (case-insensitive).
# These are common extensions for Z-machine and Glulx interpreters like Frotz or Gargoyle.
CANDIDATE_PATTERNS=(
    "*.z5" "*.z3" "*.z4" "*.z8" "*.z2" "*.z1" "*.z6" "*.z7" # Z-machine story files (common versions first)
    "*.dat"                                                 # Infocom data files (often master files)
    "*.zblorb" "*.zlb"                                      # Z-machine Blorb packaged files
    "*.blorb" "*.blb"                                       # Generic Blorb files
    "*.ulx"                                                 # Glulx game files
    "*.glb" "*.gblorb"                                      # Glulx Blorb packaged files
)
# --- End Configuration ---

# --- Sanity Checks ---
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' command not found. Please install it." >&2
    exit 1
fi
if ! command -v unzip &> /dev/null; then
    echo "Error: 'unzip' command not found. Please install it." >&2
    exit 1
fi
# --- End Sanity Checks ---

# --- Main Logic ---
# Create the base temporary directory; script exits if this fails.
mkdir -p "$TMP_BASE_DIR"
if [ ! -d "$TMP_BASE_DIR" ]; then
    echo "Error: Failed to create temporary base directory $TMP_BASE_DIR. Aborting." >&2
    exit 1
fi

# Set up a trap to ensure the temporary directory is cleaned up when the script exits.
trap 'echo "Cleaning up temporary directory $TMP_BASE_DIR..."; rm -rf "$TMP_BASE_DIR"' EXIT

echo "Z-Machine Game Downloader & Extractor"
echo "Output directory for game files: $TARGET_DIR"
echo "Temporary work directory: $TMP_BASE_DIR (will be deleted on exit)"
echo "---"

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_GAMES=${#GAME_DEFINITIONS[@]}

# Construct the 'find' command's pattern arguments for efficiency.
FIND_PATTERNS_ARGS=()
first_pattern=true
for pattern in "${CANDIDATE_PATTERNS[@]}"; do
    if [ "$first_pattern" = false ]; then
        FIND_PATTERNS_ARGS+=("-o") # OR operator for find
    fi
    FIND_PATTERNS_ARGS+=("-iname" "$pattern") # -iname for case-insensitive search
    first_pattern=false
done


for GAME_KEY in "${!GAME_DEFINITIONS[@]}"; do
    GAME_URL="${GAME_DEFINITIONS[$GAME_KEY]}"
    # Use the GAME_KEY for the temporary zip filename and subdirectory for clarity.
    DOWNLOADED_ZIP_FILENAME="${GAME_KEY}.zip"
    GAME_TMP_DIR="$TMP_BASE_DIR/$GAME_KEY"

    echo "Processing '$GAME_KEY'..."

    mkdir -p "$GAME_TMP_DIR"
    if [ ! -d "$GAME_TMP_DIR" ]; then
        echo "  Error: Failed to create temporary directory $GAME_TMP_DIR for $GAME_KEY. Skipping." >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    DOWNLOADED_ZIP_PATH="$GAME_TMP_DIR/$DOWNLOADED_ZIP_FILENAME"
    echo "  Downloading game data..." # URL is long, so not printing it here.
    # curl: -L follows redirects, -s is silent, --fail exits with error on server error, -o specifies output file.
    if curl --fail -L -s -o "$DOWNLOADED_ZIP_PATH" "$GAME_URL"; then
        echo "  Download successful: $DOWNLOADED_ZIP_PATH"

        echo "  Extracting $DOWNLOADED_ZIP_FILENAME..."
        # unzip: -q is quiet, -o overwrites files without prompting, -d specifies extraction directory.
        if unzip -q -o "$DOWNLOADED_ZIP_PATH" -d "$GAME_TMP_DIR"; then
            echo "  Extraction successful."

            echo "  Searching for game files in $GAME_TMP_DIR..."
            # Find all files matching any of the patterns.
            mapfile -t POTENTIAL_FILES < <(find "$GAME_TMP_DIR" -type f \( "${FIND_PATTERNS_ARGS[@]}" \) -print)

            if [ ${#POTENTIAL_FILES[@]} -gt 0 ]; then
                # Simple strategy: pick the first game file found by 'find'.
                # 'find' doesn't guarantee order if multiple patterns match, but this is usually sufficient.
                SELECTED_GAME_FILE="${POTENTIAL_FILES[0]}"
                FOUND_BASENAME=$(basename "$SELECTED_GAME_FILE")
                # Extract the extension from the found file (e.g., "z5", "dat").
                FILE_EXTENSION="${FOUND_BASENAME##*.}"
                # Construct target filename, e.g., "zork1.z5" (ensuring lowercase extension).
                TARGET_FILENAME="$TARGET_DIR/${GAME_KEY}.${FILE_EXTENSION,,}"

                echo "    Found game file: '$FOUND_BASENAME' (full path: $SELECTED_GAME_FILE)"
                if [ ${#POTENTIAL_FILES[@]} -gt 1 ]; then
                    echo "    Warning: Multiple potential game files were found. Using the first one: '$FOUND_BASENAME'."
                    echo "    Other files found:"
                    for (( i=1; i<${#POTENTIAL_FILES[@]}; i++ )); do
                        echo "      - $(basename "${POTENTIAL_FILES[$i]}")"
                    done
                fi
                
                echo "    Moving '$FOUND_BASENAME' to '$TARGET_FILENAME'"
                if mv "$SELECTED_GAME_FILE" "$TARGET_FILENAME"; then
                    echo "    Successfully retrieved '$TARGET_FILENAME'"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                else
                    echo "    Error: Failed to move game file to '$TARGET_FILENAME'." >&2
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                fi
            else
                echo "    Error: No compatible game file found for '$GAME_KEY'." >&2
                echo "    (Searched for patterns like: ${CANDIDATE_PATTERNS[0]}, ${CANDIDATE_PATTERNS[1]}, etc.)"
                echo "    Contents of '$GAME_TMP_DIR' (if any files were extracted):"
                ls -R "$GAME_TMP_DIR" # List extracted contents for debugging purposes.
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        else
            echo "  Error: Failed to extract '$DOWNLOADED_ZIP_FILENAME'." >&2
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        # Print curl's exit code for download troubleshooting.
        echo "  Error: Failed to download from $GAME_URL. (curl exit code: $?)" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Individual game's temporary directory ($GAME_TMP_DIR) will be removed by the main trap.
    echo "  Finished processing '$GAME_KEY'."
    echo "---"
done

echo "All processing finished."
echo "Successfully retrieved $SUCCESS_COUNT game file(s) out of $TOTAL_GAMES."
if [ $FAIL_COUNT -gt 0 ]; then
    echo "Failed to retrieve or process $FAIL_COUNT game(s)." >&2
    echo "Please check the output above for error details."
    # The script will still exit with 0 unless you want to explicitly signal overall failure.
    # For CI/automation, you might add 'exit 1' here if FAIL_COUNT > 0.
fi

# The 'trap' command set earlier will now execute, cleaning up $TMP_BASE_DIR.
exit 0
