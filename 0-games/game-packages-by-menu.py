#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime

LOG_FILE = "/tmp/python_game_installer_menus.log"

PACKAGE_STATUS_INSTALLED = "INSTALLED"
PACKAGE_STATUS_AVAILABLE = "AVAILABLE"
PACKAGE_STATUS_NOT_AVAILABLE = "NOT_AVAILABLE"
PACKAGE_STATUS_CHECK_ERROR = "ERROR_CHECKING"

HEADER_PREFIX = "### " # Define the prefix for headers

# User should structure this dictionary with headers in the desired places.
# The order will be preserved in the menu.
AVAILABLE_GAMES = {
    "### ACTION & ARCADE": "Fast-paced, reflex-based, and classic arcade-style games.",
    "frozen-bubble": "Popular puzzle game where you shoot colorful bubbles. (~25MB)",
    "chromium-bsu": "Fast-paced, arcade-style, top-scrolling space shooter. (~5MB)",
    "supertux": "Classic 2D jump'n'run sidescroller featuring Tux. (Note: executable is 'supertux2'). (~100MB)",
    "armagetronad": "A 3D lightcycle game in the style of the movie Tron. (~10MB)",
    "xmoto": "Challenging 2D motocross platform game where physics play a big role. (~15MB)",
    "teeworlds": "Fast-paced 2D multiplayer shooter with physics and cute characters. (~10MB)",
    "xonotic": "Arena-style first-person shooter with a wide array of weapons and game modes. (~1GB)",
    "openarena": "Free and open-source first-person shooter based on the Quake III Arena engine. (~500MB)",
    "assaultcube": "Fast-paced, multiplayer first-person shooter, based on the CUBE engine. (~50MB)",
    "sl": "A classic console animation - a steam locomotive runs across your screen. (~<1MB)",
    "asciijump": "A small and funny ASCII-art ski jumping game. (~<1MB)",
    "ninvaders": "A Space Invaders clone for the Ncurses terminal. (~<1MB)",
    "pacman4console": "A PacMan clone for the console. (~<1MB)",
    "snake4": "A console-based snake game. (~<1MB)",
    "greed": "A curses-based Tron-like game where you eat numbers. (~<1MB)",
    "bombardier": "A bomber-style arcade game for the console. (~<1MB)",
    "bastet": "Ncurses Tetris clone with a nasty block selection algorithm. (~<1MB)",
    "moon-buggy": "Drive a car over the moon's surface in this classic text-mode game. (~<1MB)",
    "tint": "A Tetris-like ncurses game with color and scoring. (~<1MB)",
    "xbill": "Stop Bill from installing his evil OS on computers - a classic X11 game. (~<1MB)",
    "xgalaga": "A clone of the classic Galaga arcade game for X11. (~1MB)",
    "criticalmass": "SDL-based vertical shoot'em up, also known as Critical Mass: Stem Cell. (~5MB)",
    "lbreakout2": "Breakout-style arcade game with many levels and power-ups. (~5MB)",
    "blobby": "Blobby Volley 2 - a fun and simple volleyball game with blobs. (~2MB)",
    "supertuxkart": "A 3D open-source kart racing game with Tux and friends. (~600MB)",
    "hedgewars": "A turn-based strategy, artillery, action and comedy game (Worms-like). (~200MB)",
    "scorched3d": "A 3D turn-based artillery game based on the classic Scorched Earth. (~80MB)",
    "liquidwar6": "A unique multiplayer wargame where you control an army of liquid. (~10MB)",
    "neverball": "3D arcade game where you tilt the floor to guide a ball. (~20MB)",
    "neverputt": "A 3D miniature golf game, companion to Neverball. (~10MB)",
    "bzflag": "A 3D multi-player tank battle game (Battle Zone Flag). (~25MB)",
    "gltron": "A 3D lightcycle game based on Tron. (~2MB)",
    "xjump": "Simple X11 jumping game: try to get as high as possible. (~<1MB)",
    "jumpnbump": "Cute multiplayer game where bunnies try to jump on each other to win. (~2MB)",
    "bugsquish": "A simple but addictive game of squishing bugs with your mouse. (~<1MB)",
    "ceferino": "Action-adventure game similar to the classic arcade game Pang. (~2MB)",
    "gnujump": "Platform game where a penguin jumps on floating ice blocks. (~1MB)",
    "rocksndiamonds": "Arcade game with elements from Boulder Dash, Emerald Mine, and Supaplex. (~10MB)",
    "solarwolf": "Action/arcade game, a Solar Fox clone: collect boxes while avoiding fire. (~1MB)",
    "slimevolley": "A simple but surprisingly fun and addictive volleyball game with slimes. (~<1MB)",
    "tremulous": "Free, open source FPS with aliens vs. humans, and real-time strategy elements. (~300MB)",
    "unvanquished": "Fast-paced, futuristic FPS with RTS elements, spiritual successor to Tremulous. (~1GB+)",
    "frets-on-fire": "Music game: play guitar with the keyboard (Guitar Hero like; or 'fofix'). (~50MB)",
    "orbital-eunuchs-sniper": "Quirky 3D sniping game with a unique theme. (~10MB)",
    "circuslinux": "Arcade game: control a seesaw to propel clowns to pop balloons. (~<1MB)",
    "amphetamine": "Fast-paced 3D action game: jump between platforms in abstract worlds. (~5MB)",
    "dodgindiamond2": "Arcade-style game: collect diamonds and avoid enemies. (~1MB)",
    "rafkill": "Vertical shoot'em up with an emphasis on story and varied enemies. (~5MB)",
    "ri-li": "Arcade game where you drive a toy wooden train collecting coaches. (~10MB)",
    "trackballs": "Marble Madness-like game through a labyrinth of ramps and bridges. (~2MB)",
    "alex4": "Alex the Allegator 4 - a simple, retro-style platformer. (~1MB)",
    "polygen": "Abstract space shooter with geometric enemies. (~2MB)",
    "monster-masher": "Action game where you mash monsters with a hammer. (~1MB)",

    "### STRATEGY & TACTICS": "Games involving planning, foresight, and resource management.",
    "wesnoth-1.16": "Battle for Wesnoth - fantasy turn-based strategy (or 'wesnoth' for current). (~400MB)",
    "freeciv-client-gtk": "Freeciv - a Civilization-like turn-based strategy game (GTK client). (~50MB)",
    "freecol": "A free version of Sid Meier's Colonization, a turn-based strategy game. (~100MB)",
    "0ad": "A free, open-source real-time strategy (RTS) game of ancient warfare. (~1.5GB)",
    "triplea": "Turn-based strategy game based on Axis & Allies, with many game maps. (~150MB)",
    "glob2": "Globulation 2 - an innovative real-time strategy (RTS) game with indirect unit control. (~30MB)",
    "megaglest": "A free and open source 3D real-time strategy (RTS) game with fantasy elements. (~300MB)",
    "openttd": "OpenTTD - an open-source clone of Transport Tycoon Deluxe, a business simulation. (~50MB)",
    "pingus": "A Lemmings-like puzzle/strategy game featuring penguins. (~30MB)",
    "ufoai": "UFO: Alien Invasion - squad-based tactical strategy game inspired by X-COM. (~600MB)",
    "freeorion": "A turn-based space empire and galactic conquest (4X) game. (~100MB)",
    "warzone2100": "Post-apocalyptic real-time strategy game with a focus on technology and unit design. (~150MB)",
    "pioneers": "A simulation of the board game 'The Settlers of Catan'. (~5MB)",
    "endgame-singularity": "Successor to Singularity, guide humanity as an AI (check availability). (~2MB)",
    "empire": "The classic turn-based strategy wargame for terminals. (~<1MB)",
    "sumwars": "A free, 2D, turn-based strategy game in the spirit of Advance Wars. (~10MB)",
    "unknown-horizons": "A 2D real-time strategy simulation with an emphasis on economy and city building. (~200MB)",
    "widelands": "Free, open source real-time strategy game with a focus on settlement building. (~400MB)",
    "openclonk": "Multiplayer action game involving settlement, mining, and combat in a 2D world. (~150MB)",
    "vms-empire": "VMS-empire, a classic strategy game for text terminals (distinct from GNU Empire). (~<1MB)",

    "### PUZZLE & LOGIC": "Brain teasers, logic challenges, and matching games.",
    "gnome-games": "Meta-package for GNOME games (Mines, Sudoku, Mahjongg, etc.). (~1MB, pulls deps)",
    "gnome-mines": "The popular minesweeper puzzle game (GNOME). (~2MB)",
    "gnome-sudoku": "Play and generate Sudoku puzzles (GNOME). (~2MB)",
    "quadrapassel": "A Tetris-like falling block game (GNOME). (~1MB)",
    "aisleriot": "A collection of over 80 different solitaire card games (GNOME). (~10MB)",
    "iagno": "A Reversi/Othello game for GNOME. (~1MB)",
    "five-or-more": "GNOME game - make lines of five or more colored balls. (~<1MB)",
    "hitori": "GNOME puzzle game - eliminate numbers based on rules. (~<1MB)",
    "tali": "A sort of poker with dice and less money (GNOME Yahtzee). (~<1MB)",
    "swell-foop": "GNOME puzzle game - clear the board by removing groups of colored balls. (~<1MB)",
    "atomix": "Puzzle game where you build molecules from component atoms. (~1MB)",
    "ltris": "A very polished Tetris clone with nice graphics. (~2MB)",
    "pentobi": "A computer opponent for the board game Blokus. (~2MB)",
    "brainparty": "A collection of 36 puzzle games for training your brain. (~15MB)",
    "pathological": "A puzzle game involving routing balls along paths of colored tiles. (~1MB)",
    "monsterz": "Arcade puzzle game similar to Puyo Puyo. (~1MB)",
    "enigma": "A puzzle game inspired by Oxyd and Rock'n'Roll, with many levels. (~20MB)",
    "numptyphysics": "A crayon-drawing physics puzzle game where you draw shapes to solve levels. (~5MB)",
    "fishfillets-ng": "Puzzle game starring two fish, solving logic puzzles by moving objects. (~50MB)",
    "chromium": "An arcade-style puzzle game with rolling balls (not the browser!). (~2MB)",
    "gweled": "A 'Diamond Mine' or 'Bejeweled' style game for GNOME. (~<1MB)",
    "kmahjongg": "Mahjongg solitaire game by KDE. (~5MB)",
    "kpat": "Solitaire (Patience) card game collection by KDE. (~10MB)",
    "kreversi": "Reversi board game by KDE. (~1MB)",
    "ksudoku": "Sudoku puzzle game and generator by KDE. (~2MB)",
    "kolf": "Miniature golf game by KDE with various courses. (~10MB)",
    "kbounce": "JezzBall-like arcade game where you build walls to trap balls (KDE). (~1MB)",
    "kgoldrunner": "Lode Runner arcade game clone by KDE. (~2MB)",
    "knetwalk": "Puzzle game: connect all terminals to the central server (KDE). (~1MB)",
    "kjumpingcube": "Simple dice game where you conquer territory (KDE). (~<1MB)",
    "kshisen": "Shisen-Sho, a Mahjongg-like tile puzzle game (KDE). (~1MB)",
    "kapman": "Pac-Man clone for the KDE desktop. (~1MB)",
    "bomber": "Arcade bombing game for KDE (another Bomberman style). (~2MB)",
    "palapeli": "Jigsaw puzzle game with various features by KDE. (~10MB)",
    "picmi": "Nonogram/Picross logic puzzle game by KDE. (~1MB)",
    "klickety": "Clickomania/SameGame puzzle where you clear colored blocks (KDE). (~1MB)",
    "kubrick": "A game based on Rubik's Cube for KDE. (~1MB)",
    "kfourinline": "Connect Four game for KDE. (~<1MB)",
    "connectagram": "Word unscrambling puzzle game, form words from jumbled letters. (~1MB)",
    "gbrainy": "A brain teaser game with logic puzzles, mental calculation and memory trainers. (~5MB)",
    "gottet": "A Tetris-like falling blocks game for GNOME. (~<1MB)",
    "netris": "A networked Tetris clone that can be played over a network or against AI. (~<1MB)",
    "flobopuyo": "A Puyo Puyo clone with network play. (~1MB)",
    "primrose": "A tile-laying puzzle game about placing colored squares. (~<1MB)",

    "### BOARD & CARD GAMES (TRADITIONAL)": "Digital versions of classic board and card games.",
    "gnubg": "GNU Backgammon - a strong backgammon program with analysis capabilities. (~15MB)",
    "gnuchess": "The GNU Chess program (engine, often used with xboard or eboard). (~2MB)",
    "gnushogi": "The GNU Shogi (Japanese Chess) program. (~2MB)",
    "dreamchess": "A 3D chess game with various board sets and OpenGL graphics. (~20MB)",
    "pysolfc": "An extensive collection of more than 1000 solitaire card games. (~5MB)",
    "xboard": "A graphical chessboard that can be used as an interface for chess engines. (~1MB)",
    "eboard": "A GTK+ chessboard, alternative to XBoard. (~1MB)",
    "gtkatlantic": "A Monopoly-like game for GNOME. (~1MB)",
    "xskat": "The popular German card game Skat for X11. (~<1MB)",
    "gnugo": "The GNU Go program, a text-based Go player and analyzer. (~5MB)",
    "quarry": "User interface for several board games: Go, Amazons, Reversi. (~1MB)",
    "cgoban1": "Go board for playing and reviewing SGF Go game files (older version, still used). (~1MB)",
    "ace-of-penguins": "Collection of Unix-style penguin-themed card games. (~1MB)",
    "chessx": "Chess database and GUI, PGN viewer and editor. (~10MB)",
    "lexica": "Word puzzle game similar to Boggle. (~<1MB)", # Also fits here

    "### ROGUELIKES & TEXT-BASED": "Dungeon crawls, interactive fiction, and terminal adventures.",
    "bsdgames": "A collection of classic text-based UNIX games (adventure, rogue, worms, etc.). (~1MB)",
    "nethack-console": "The classic dungeon exploration roguelike game (console version). (~2MB)",
    "angband": "A single-player dungeon exploration roguelike game (console). (~5MB)",
    "crawl": "Dungeon Crawl Stone Soup - a popular and deep roguelike (console). (~15MB)",
    "adom-gb": "Ancient Domains Of Mystery - Classic Edition (check availability). (~10MB)",
    "cataclysm-dda-curses": "Cataclysm: Dark Days Ahead - post-apocalyptic survival roguelike (ncurses). (~50MB)",
    "doomrl": "Doom, the Roguelike - a fast-paced, turn-based roguelike based on Doom. (~5MB)",
    "brogue": "Brogue - a highly acclaimed, visually distinct roguelike (check 'brogue-ce'). (~1MB)",
    "zangband": "A variant of the roguelike game Angband. (~5MB)",
    "tomenet": "Tales of Middle Earth (ToME) - a multiplayer roguelike game. (~20MB)",
    "gearhead": "A mecha roguelike with a complex storyline and procedural generation. (~5MB)",
    "gearhead2": "Successor to GearHead, continuing the mecha roguelike themes. (~10MB)",
    "frotz": "An interpreter for Infocom and other Z-machine interactive fiction games. (~<1MB)",
    "glulxe": "An interpreter for Glulx interactive fiction games. (~<1MB)",
    "robots": "Fight off evil robots in this classic terminal game (often in bsdgames). (~<1MB)",
    "slashem": "A variant of NetHack with many more features, monsters, and items. (~5MB)",
    "unangband": "A variant of the popular roguelike game Angband. (~5MB)",
    "larn": "A classic, notoriously difficult roguelike game (try 'xlarn' for X11 version). (~<1MB)",
    "omega-rpg": "A complex text-based roguelike with a vast overworld and many features. (~1MB)",
    "nethereye": "A 'crawler' type game with a curses interface, focusing on exploration. (~<1MB)",

    "### ADVENTURE & RPG (GRAPHICAL)": "Story-driven games with exploration and character development.",
    "scummvm": "Interpreter for many classic graphical point-and-click adventure games. (~10MB, games separate)",
    "residualvm": "Game engine recreation for Grim Fandango and other 3D adventure games. (~5MB, games separate)",
    "minetest": "An open-source voxel game engine (Minecraft-like, needs game content/mods). (~30MB core)",
    "freedroidrpg": "An isometric RPG featuring Tux, inspired by Diablo. (~100MB)",
    "flare-game": "Flare: a single-player 2D action RPG engine (often comes with a demo game). (~50MB)",
    "ardentryst": "An action/RPG sidescroller with a focus on story and character development. (~30MB)",
    "valyriatear": "Open-source single-player JRPG-inspired game created with the Godot Engine. (~50MB)",
    "freedink": "Dink Smallwood adventure game engine (data separate or use 'freedink-data'). (~2MB engine)",
    "stendhal": "A fun, friendly, and free 2D multiplayer online adventure game (Arianne engine). (~20MB client)",
    "egoboo": "A 3D open-source dungeon crawling adventure in the spirit of NetHack. (~50MB)",
    "naev": "A 2D space trading and combat game, inspired by Escape Velocity. (~80MB)",
    "mana": "Client for The Mana World, a 2D FOSS MMORPG (package 'mana' or 'tmw'). (~30MB)",

    "### SIMULATION": "Games that simulate real-world or fictional systems.",
    # "openttd": "OpenTTD - an open-source clone of Transport Tycoon Deluxe.", # Already in Strategy
    # "supertuxkart": "A 3D open-source kart racing game with Tux and friends.", # Already in Arcade
    "torcs": "The Open Racing Car Simulator - a highly portable multi platform car racing simulation. (~300MB)",
    "speed-dreams": "A fork of TORCS, featuring enhanced visuals and physics in a motorsport simulator. (~700MB)",
    "dangerdeep": "WWII German submarine simulation. (~50MB)",
    "opencity": "3D city simulator. (~10MB)",
    "flightgear": "Open-source flight simulator (VERY large, modular install). (~200MB base, >10GB with scenery)",
    "vegastrike": "A 3D space combat, trading, and exploration game. (~500MB)",
    "foobillardplus": "An OpenGL-based 3D billiards (pool) game with realistic physics. (~5MB)",

    "### EDUCATIONAL & KIDS": "Games primarily designed for learning or young children.",
    "gcompris-qt": "A high-quality educational software suite, with many activities for children aged 2 to 10. (~300MB)",
    "tuxtype": "Tux Typing - an educational typing tutor game starring Tux. (~20MB)",
    "childsplay": "A suite of educational games for young children. (~50MB)",
    "ktuberling": "Potato-themed game for young children (KDE 'Potato Guy'). (~5MB)",
    "khangman": "The classic Hangman game for KDE. (~1MB)",
    "kanagram": "Anagram game for KDE. (~1MB)",
    "kgeography": "A geography learning tool for KDE. (~10MB)",
    "klettres": "Learn the alphabet and read syllables in different languages (KDE). (~15MB)",
    "kwordquiz": "Flashcard learning program, similar to Anki/Mnemosyne (KDE). (~2MB)",
    "blinken": "Simon Says memory game for KDE. (~<1MB)",

    "### MISCELLANEOUS & CLASSICS": "Fun utilities, old classics, or unique small games.",
    "gnome-nibbles": "A snake game for GNOME, also known as Worms. (~<1MB)",
    # "sl": "A classic console animation - a steam locomotive runs across your screen.", # Already in Arcade
    # "cowsay": "A configurable talking cow (or other characters) using ASCII art.", # In your essentials
    # "fortune-mod": "Provides fortune cookies (aphorisms, jokes, etc.) to your terminal.", # In your essentials
    # "figlet": "Generates large characters out of ordinary screen characters (ASCII art).", # In your essentials
    # "toilet": "Displays large colourful characters in a variety of fonts.", # In your essentials
    "xrick": "A clone of Rick Dangerous, a classic platform-puzzle game. (~1MB)", # Repeated, good here too
    "frozenfriday": "A game about surviving Friday the 13th as a camp counselor. (~1MB)",
    "oolite": "A space trading and combat game, inspired by the classic Elite. (~50MB)"
    # --- End Game List ---
}

INSTALL_COMMAND_TEMPLATE = "sudo apt-get install -y {packages}"

def log_message(message):
    try:
        with open(LOG_FILE, "a") as log_file:
            log_file.write(f"{datetime.now()}: {message}\n")
    except Exception as e:
        print(f"Error writing to log file {LOG_FILE}: {e}", file=sys.stderr)

def get_package_status(package_name, suppress_logging=False):
    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    try:
        dpkg_result = subprocess.run(['dpkg', '-l', package_name],
                                     capture_output=True, text=True, check=False, env=env)
        if dpkg_result.returncode == 0:
            for line in dpkg_result.stdout.splitlines():
                parts = line.split()
                if len(parts) > 1 and parts[0] == 'ii' and parts[1] == package_name:
                    return PACKAGE_STATUS_INSTALLED
    except FileNotFoundError:
        if not suppress_logging: log_message(f"dpkg command not found during check for {package_name}.")
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during dpkg -l check for {package_name}: {e}")

    try:
        apt_show_result = subprocess.run(['apt-cache', 'show', package_name],
                                         capture_output=True, text=True, check=False, env=env)
        if apt_show_result.returncode == 0 and apt_show_result.stdout.strip():
            return PACKAGE_STATUS_AVAILABLE
        else:
            if not suppress_logging and apt_show_result.returncode != 0 :
                 log_message(f"apt-cache show for '{package_name}' indicated not available. RC: {apt_show_result.returncode}. Stderr: {apt_show_result.stderr.strip()}")
            return PACKAGE_STATUS_NOT_AVAILABLE
    except FileNotFoundError:
        if not suppress_logging: log_message(f"apt-cache command not found during check for {package_name}.")
        return PACKAGE_STATUS_CHECK_ERROR
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during apt-cache show for {package_name}: {e}")
        return PACKAGE_STATUS_CHECK_ERROR

def get_formatted_header_text(item_name_key):
    header_content = item_name_key[len(HEADER_PREFIX):].strip().upper()
    return f"--- {header_content} ---"


def run_menu_session_with_cache_build(stdscr, item_definitions, status_cache, build_done_flag_container):
    if not curses.has_colors():
        raise RuntimeError("Terminal does not support colors.")
    try:
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
        curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal / Available / Header
        curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # Error text
        curses.init_pair(4, curses.COLOR_GREEN, curses.COLOR_BLACK)  # Installed Item Name / Legend
        curses.init_pair(5, curses.COLOR_YELLOW, curses.COLOR_BLACK) # Yellow Key Hint
        # Pair 6 for Green Legend text (can reuse pair 4 if needed)
        # For Dimmed text, we use Pair 2 + A_DIM
    except curses.error as e:
        raise RuntimeError(f"Error initializing colors: {e}.")

    if not build_done_flag_container[0]: # Check flag
        stdscr.clear()
        h_loader, w_loader = stdscr.getmaxyx()
        loading_line_y = h_loader // 2
        title_message = "Building package status cache. This may take a moment..."
        title_x = max(0, (w_loader - len(title_message)) // 2)

        def safe_addstr_loader(y, x, text, attr=0):
            if 0 <= y < h_loader and 0 <= x < w_loader and x + len(text) <= w_loader:
                stdscr.addstr(y, x, text, attr)
            elif 0 <= y < h_loader and 0 <= x < w_loader :
                 stdscr.addstr(y, x, text[:w_loader-x-1], attr)
        
        if loading_line_y > 0 : safe_addstr_loader(loading_line_y -1 , title_x, title_message)
        elif loading_line_y >=0 : safe_addstr_loader(loading_line_y , title_x, title_message)

        # Filter out headers for cache building and progress count
        items_to_check_status_for = [name for name in item_definitions.keys() if not name.startswith(HEADER_PREFIX)]
        total_items_to_check = len(items_to_check_status_for)
        checked_count = 0
        
        log_message("Building item status cache (first run)...")
        initial_cache_build_start_time = time.time()

        if total_items_to_check > 0: # Only show progress if there are items to check
            for item_name_key in items_to_check_status_for:
                checked_count += 1
                progress_percent = (checked_count * 100) // total_items_to_check
                bar_width = 20; filled_len = int(bar_width * progress_percent // 100)
                bar = '#' * filled_len + '-' * (bar_width - filled_len)
                progress_prefix = f"[{bar}] {progress_percent}% "
                checking_text = "Checking: "
                available_for_name = w_loader - len(progress_prefix) - len(checking_text) - 4
                display_item_name_progress = item_name_key
                if len(item_name_key) > available_for_name and available_for_name > 0:
                    display_item_name_progress = item_name_key[:available_for_name] + "..."
                elif available_for_name <=0: display_item_name_progress = ""; checking_text = ""
                
                if loading_line_y < h_loader :
                    stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
                    full_progress_message = f"{progress_prefix}{checking_text}{display_item_name_progress}"
                    safe_addstr_loader(loading_line_y, 0, full_progress_message[:w_loader-1])
                stdscr.refresh()
                status_cache[item_name_key] = get_package_status(item_name_key, suppress_logging=True)
        
        cache_build_duration = time.time() - initial_cache_build_start_time
        log_message(f"Item status cache built in {cache_build_duration:.2f}s for {checked_count} items.")
        if loading_line_y < h_loader:
            stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
            final_cache_message = f"Cache built: {checked_count} items in {cache_build_duration:.2f}s."
            msg_x_final = max(0, (w_loader - len(final_cache_message)) // 2)
            safe_addstr_loader(loading_line_y, msg_x_final, final_cache_message[:w_loader-1])
            stdscr.refresh()
            time.sleep(1.0)
        build_done_flag_container[0] = True
        
    return display_menu(stdscr, item_definitions, status_cache)


def display_menu(stdscr, item_definitions, status_cache):
    curses.curs_set(0) # Already set by wrapper, but safe

    item_names = list(item_definitions.keys()) # Preserve definition order
    if not item_names:
        stdscr.addstr(0,0, "No items loaded."); stdscr.refresh(); time.sleep(1); stdscr.getch()
        return None

    checked_items = {name: False for name in item_names if not name.startswith(HEADER_PREFIX)}
    select_all_items = False
    highlighted_linear_idx = 0
    display_column_offset = 0

    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            footer_content_height = 8 
            footer_height_needed = footer_content_height + 1
            
            if height < footer_height_needed + 1 or width < 50:
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(0, 0, "Terminal too small.")
                stdscr.addstr(1,0, "Press Q to quit or resize.")
                stdscr.attroff(curses.color_pair(3))
                stdscr.refresh()
                key = stdscr.getch()
                if key == ord('q') or key == ord('Q'): return None
                continue

            # Calculate max_text_len_for_item considering games and formatted headers
            max_len_game_name_only = 0
            game_item_names = [n for n in item_names if not n.startswith(HEADER_PREFIX)]
            if game_item_names:
                max_len_game_name_only = max(len(name) for name in game_item_names)
            max_game_line_len = 4 + max_len_game_name_only + 2 # "[X] " + name + " ✓"

            max_len_formatted_header = 0
            header_item_names = [n for n in item_names if n.startswith(HEADER_PREFIX)]
            if header_item_names:
                 max_len_formatted_header = max(len(get_formatted_header_text(h_name)) for h_name in header_item_names)
            
            max_text_len_for_item = max(max_game_line_len, max_len_formatted_header, 10) # Min width 10
            
            option_padding = 2 
            option_width_on_screen = max_text_len_for_item + option_padding
            num_display_columns_on_screen = max(1, width // option_width_on_screen)
            num_display_rows = height - footer_height_needed 
            if num_display_rows < 1: num_display_rows = 1

            total_logical_columns = (len(item_names) + num_display_rows - 1) // num_display_rows if num_display_rows > 0 else 1
            max_possible_offset = max(0, total_logical_columns - num_display_columns_on_screen)
            display_column_offset = max(0, min(display_column_offset, max_possible_offset))

            highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(item_names) -1 if item_names else 0))
            current_highlighted_logical_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0
            current_highlighted_row_in_col = highlighted_linear_idx % num_display_rows if num_display_rows > 0 else 0

            for idx, item_name in enumerate(item_names):
                is_header = item_name.startswith(HEADER_PREFIX)
                logical_col_of_item = idx // num_display_rows if num_display_rows > 0 else 0
                display_row_of_item = idx % num_display_rows if num_display_rows > 0 else 0
                screen_col_to_draw_in = logical_col_of_item - display_column_offset

                if not (0 <= screen_col_to_draw_in < num_display_columns_on_screen): continue
                if display_row_of_item >= num_display_rows: continue

                screen_x = screen_col_to_draw_in * option_width_on_screen
                screen_y = display_row_of_item
                if screen_x + max_text_len_for_item > width : continue

                display_string = ""
                current_attributes = curses.color_pair(2) # Default

                if is_header:
                    display_string = get_formatted_header_text(item_name)
                    current_attributes |= curses.A_BOLD # Make headers bold
                else: # It's a game/package
                    checkbox = "[X]" if checked_items.get(item_name, False) else "[ ]" # Use .get for safety
                    status = status_cache.get(item_name, PACKAGE_STATUS_CHECK_ERROR)
                    item_marker = ""
                    if status == PACKAGE_STATUS_INSTALLED:
                        current_attributes = curses.color_pair(4) # Green
                        item_marker = " ✓"
                    elif status == PACKAGE_STATUS_AVAILABLE:
                        current_attributes = curses.color_pair(2) # Normal
                    elif status == PACKAGE_STATUS_NOT_AVAILABLE or status == PACKAGE_STATUS_CHECK_ERROR:
                        current_attributes = curses.color_pair(2) | curses.A_DIM # Dimmed
                    display_string = f"{checkbox} {item_name}{item_marker}"
                
                display_string_padded = display_string.ljust(max_text_len_for_item)
                
                final_attributes_to_apply = current_attributes
                if idx == highlighted_linear_idx:
                    final_attributes_to_apply = curses.color_pair(1) # Highlighted
                    if is_header: # Optionally make highlighted headers also bold
                        final_attributes_to_apply |= curses.A_BOLD
                
                if 0 <= screen_y < height and 0 <= screen_x < width:
                     stdscr.addstr(screen_y, screen_x, display_string_padded[:width-screen_x], final_attributes_to_apply)

            # ... (Footer drawing logic - same as previous full script, ensure it uses safe_addstr_footer) ...
            # Make sure footer section correctly calculates its y positions based on num_display_rows
            air_gap_line = num_display_rows 
            instruction_y_base = air_gap_line + 1
            instr_line_y = instruction_y_base
            
            def draw_line_safely(y, content_parts): # Helper for footer
                if y < height:
                    stdscr.move(y, 0)
                    current_x = 0
                    for part_text, part_attr in content_parts:
                        if current_x < width -1:
                           drawable_len = min(len(part_text), width - 1 - current_x)
                           stdscr.addstr(part_text[:drawable_len], part_attr)
                           current_x += drawable_len
                        else: break
                    stdscr.clrtoeol()

            draw_line_safely(instr_line_y, [("Arrows/PgUp/PgDn/Home/End. Space=toggle. Ctrl+A=all.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("", curses.A_BOLD), ("'I'", curses.color_pair(5) | curses.A_BOLD),(" to install ", curses.A_BOLD), ("selected", curses.color_pair(2) | curses.A_BOLD),(". ", curses.A_BOLD), ("'Q'", curses.color_pair(5) | curses.A_BOLD),(" to quit.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("Green text ✓", curses.color_pair(4) | curses.A_BOLD),(" = Installed.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("Dimmed text", curses.color_pair(2) | curses.A_DIM | curses.A_BOLD),(" = Not in repos / Error.", curses.A_BOLD)])
            instr_line_y+=1
            page_info_text = f"Cols: 1-{total_logical_columns} of {total_logical_columns}"
            if total_logical_columns > num_display_columns_on_screen:
                start_col_num = display_column_offset + 1
                end_col_num = min(display_column_offset + num_display_columns_on_screen, total_logical_columns)
                page_info_text = f"Cols: {start_col_num}-{end_col_num} of {total_logical_columns} (Left/Right to page)"
            draw_line_safely(instr_line_y, [(page_info_text, curses.A_BOLD)])
            instr_line_y+=1

            description_area_y_start = instr_line_y
            if item_names and 0 <= highlighted_linear_idx < len(item_names):
                current_item_name = item_names[highlighted_linear_idx]
                is_current_header = current_item_name.startswith(HEADER_PREFIX)
                
                status_desc_marker = ""
                if not is_current_header:
                    current_status = status_cache.get(current_item_name, PACKAGE_STATUS_CHECK_ERROR)
                    if current_status == PACKAGE_STATUS_INSTALLED: status_desc_marker = " (INSTALLED)"
                    elif current_status == PACKAGE_STATUS_NOT_AVAILABLE: status_desc_marker = " (NOT IN REPOS)"
                    elif current_status == PACKAGE_STATUS_CHECK_ERROR: status_desc_marker = " (STATUS CHECK ERROR)"

                desc_display_name = current_item_name[len(HEADER_PREFIX):].strip() if is_current_header else current_item_name
                desc_header = f"Desc of {desc_display_name}{status_desc_marker}:"
                if description_area_y_start < height: stdscr.addstr(description_area_y_start, 0, desc_header[:width-1])
                
                actual_desc_text = item_definitions.get(current_item_name, "No description available.")
                if description_area_y_start + 1 < height: stdscr.addstr(description_area_y_start + 1, 0, actual_desc_text[:width-1])
            stdscr.refresh()

            key = stdscr.getch()
            num_items = len(item_names)
            if not num_items: continue
            
            # --- Key handling ---
            if key == curses.KEY_UP:
                if current_highlighted_row_in_col > 0: highlighted_linear_idx -= 1
                elif current_highlighted_logical_col > 0: 
                    highlighted_linear_idx = (current_highlighted_logical_col - 1) * num_display_rows + (num_display_rows -1)
                    highlighted_linear_idx = min(highlighted_linear_idx, num_items -1) 
            elif key == curses.KEY_DOWN:
                if current_highlighted_row_in_col < num_display_rows - 1 and highlighted_linear_idx + 1 < num_items: highlighted_linear_idx += 1
                elif current_highlighted_logical_col + 1 < total_logical_columns and \
                     (current_highlighted_logical_col + 1) * num_display_rows < num_items : highlighted_linear_idx = (current_highlighted_logical_col + 1) * num_display_rows
            elif key == curses.KEY_LEFT:
                if current_highlighted_logical_col > 0:
                    new_idx_target = (current_highlighted_logical_col - 1) * num_display_rows + current_highlighted_row_in_col
                    max_idx_in_prev_col = min( (current_highlighted_logical_col * num_display_rows) -1 , num_items -1)
                    highlighted_linear_idx = min(new_idx_target, max_idx_in_prev_col)
            elif key == curses.KEY_RIGHT:
                if current_highlighted_logical_col < total_logical_columns - 1:
                    new_idx_target = (current_highlighted_logical_col + 1) * num_display_rows + current_highlighted_row_in_col
                    highlighted_linear_idx = min(new_idx_target, num_items - 1)
            elif key == curses.KEY_PPAGE: highlighted_linear_idx = max(0, highlighted_linear_idx - num_display_rows)
            elif key == curses.KEY_NPAGE: highlighted_linear_idx = min(num_items - 1, highlighted_linear_idx + num_display_rows)
            elif key == curses.KEY_HOME: highlighted_linear_idx = 0
            elif key == curses.KEY_END: highlighted_linear_idx = num_items - 1
            elif key == ord(" "): 
                if 0 <= highlighted_linear_idx < num_items:
                    item_to_toggle = item_names[highlighted_linear_idx]
                    if not item_to_toggle.startswith(HEADER_PREFIX): # Can't toggle headers
                        status_toggle = status_cache.get(item_to_toggle, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle == PACKAGE_STATUS_INSTALLED or status_toggle == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_to_toggle] = not checked_items[item_to_toggle]
                        else: curses.flash()
                    else: curses.flash() # Flash if trying to toggle header
            elif key == 1:  # Ctrl+A
                select_all_items = not select_all_items
                for item_name_iter in item_names:
                    if not item_name_iter.startswith(HEADER_PREFIX): # Only select/deselect actual items
                        status_toggle_all = status_cache.get(item_name_iter, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle_all == PACKAGE_STATUS_INSTALLED or status_toggle_all == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_name_iter] = select_all_items
                        elif not select_all_items: # If deselecting all, ensure it's deselected
                           checked_items[item_name_iter] = False
            elif key == ord("i") or key == ord("I") : 
                selected_to_install = [item for item, is_checked in checked_items.items() if is_checked and not item.startswith(HEADER_PREFIX)]
                return selected_to_install 
            elif key == ord("q") or key == ord("Q"):
                return None 
            elif key == curses.KEY_RESIZE: pass

            if num_items > 0: # Auto-paging logic
                highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_items - 1))
                new_curr_hl_logical_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0
                
                if new_curr_hl_logical_col >= display_column_offset + num_display_columns_on_screen:
                    display_column_offset = min(max_possible_offset, display_column_offset + num_display_columns_on_screen)
                elif new_curr_hl_logical_col < display_column_offset:
                    display_column_offset = max(0, display_column_offset - num_display_columns_on_screen)
                
                if key == curses.KEY_HOME: display_column_offset = 0
                elif key == curses.KEY_END:
                    if num_display_rows > 0:
                        last_item_logical_col = (num_items - 1) // num_display_rows
                        display_column_offset = max(0, last_item_logical_col - num_display_columns_on_screen + 1)
                        display_column_offset = min(display_column_offset, max_possible_offset)
        except curses.error as e: 
            log_message(f"Curses error in display_menu: {e}")
            if "ERR" in str(e) or "addwstr" in str(e) or "addstr" in str(e) or "waddwstr" in str(e): time.sleep(0.05) 
            else: raise 
        except Exception as e: 
            log_message(f"Unexpected error in display_menu: {e}, {type(e)}")
            raise

# (install_selected_items function remains the same as the one that takes status_cache_to_update)
def install_selected_items(selected_items_list, item_definitions_dict, status_cache_to_update):
    if not selected_items_list:
        print("No items were selected for installation.")
        return

    items_to_actually_install = []
    successfully_installed_in_batch = [] 
    already_installed_skipped = []
    not_available_skipped = []
    error_checking_skipped = []

    log_message("Verifying selected item statuses before attempting installation...")
    for item_name in selected_items_list:
        current_status_in_cache = status_cache_to_update.get(item_name, PACKAGE_STATUS_CHECK_ERROR)
        if item_name.startswith(HEADER_PREFIX): continue # Should not happen if selection logic is correct

        if current_status_in_cache == PACKAGE_STATUS_INSTALLED:
            already_installed_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_NOT_AVAILABLE:
            not_available_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_CHECK_ERROR:
            error_checking_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_AVAILABLE:
            items_to_actually_install.append(item_name)
        else:
             log_message(f"Unknown status '{current_status_in_cache}' for {item_name} during install prep. Skipping.")
             error_checking_skipped.append(f"{item_name} (unknown status: {current_status_in_cache})")
    
    if already_installed_skipped: print(f"Skipping (already installed): {', '.join(already_installed_skipped)}")
    if not_available_skipped: print(f"Skipping (not in repos): {', '.join(not_available_skipped)}")
    if error_checking_skipped: print(f"Skipping (error/unknown status): {', '.join(error_checking_skipped)}")

    if not items_to_actually_install:
        print("No new items left to install from selection.")
        return
    
    overall_start_time = time.time()
    print(f"\nPreparing to install {len(items_to_actually_install)} item(s): {', '.join(items_to_actually_install)}")
    items_string = " ".join(items_to_actually_install)
    install_command = INSTALL_COMMAND_TEMPLATE.format(packages=items_string)
    print(f"Command: {install_command}\n")
    
    try:
        process = subprocess.Popen(install_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        if process.stdout:
            for line in iter(process.stdout.readline, ''): print(line, end='')
            process.stdout.close()
        process.wait()

        if process.returncode == 0:
            log_message(f"Apt install command potentially successful for: {', '.join(items_to_actually_install)}")
            print("\n✓ Installation process completed for attempted items. Verifying statuses...")
            for item_name_verify in items_to_actually_install: 
                new_status = get_package_status(item_name_verify)
                status_cache_to_update[item_name_verify] = new_status 
                if new_status == PACKAGE_STATUS_INSTALLED:
                    print(f"  ✓ {item_name_verify} is now INSTALLED.")
                    successfully_installed_in_batch.append(item_name_verify)
                else:
                    print(f"  ✗ {item_name_verify} still not INSTALLED (status: {new_status}). Apt reported success but verification failed or it's in a different state.")
        else:
            print(f"\n✗ Installation command failed (RC:{process.returncode}) for: {', '.join(items_to_actually_install)}")
            log_message(f"Command failed (code {process.returncode}): {install_command}")
            print("Re-checking status of items that apt reported errors for...")
            for item_name_failed in items_to_actually_install: # Re-check all attempted if batch failed
                 status_cache_to_update[item_name_failed] = get_package_status(item_name_failed, suppress_logging=True)
    except Exception as e:
        print(f"An unexpected error occurred during installation: {e}")
        log_message(f"Exception during installation command '{install_command}': {e}")
    
    total_runtime = time.time() - overall_start_time
    print(f"\nInstallation attempt finished for batch. Runtime: {total_runtime:.2f} seconds.")

# (main function remains the same as the one with the 'Install More?' loop and session cache)
def main():
    def graceful_signal_handler(sig, frame):
        if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
            try: curses.nocbreak(); curses.echo(); curses.endwin()
            except: pass
        print("\nProgram terminated by user (Ctrl+C).")
        log_message("Program terminated by SIGINT.")
        sys.exit(0)

    signal.signal(signal.SIGINT, graceful_signal_handler)

    active_item_collection = AVAILABLE_GAMES 
    collection_name_for_messages = "AVAILABLE_GAMES" 

    if not active_item_collection:
        print(f"No items defined in {collection_name_for_messages}. Nothing to do.")
        log_message(f"{collection_name_for_messages} dictionary is empty.")
        return

    session_item_status_cache = {}
    cache_build_done_flag_container = [False] 

    while True: 
        selected_items_for_action = None
        try:
            # run_menu_session_with_cache_build calls display_menu
            # display_menu now returns a single list (selected) or None (quit)
            selected_items_for_action = curses.wrapper(
                run_menu_session_with_cache_build, 
                active_item_collection, 
                session_item_status_cache, 
                cache_build_done_flag_container
            )
        except RuntimeError as e: 
            print(f"Error: {e}")
            log_message(f"RuntimeError from menu session: {e}")
            break 
        except Exception as e: 
            if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
                try: curses.endwin()
                except: pass
            print(f"An unexpected error occurred running the menu: {e}")
            log_message(f"Unhandled exception in main around curses.wrapper: {e}, {type(e)}")
            break 

        if selected_items_for_action is None: 
            log_message("User quit the menu.")
            break 
        elif not selected_items_for_action: 
            log_message("User proceeded from menu but no items were checked.")
            if not ask_to_continue("No items checked. Return to menu?"):
                break
            else:
                continue 
        else:
            print("\nThe following items were marked for installation:")
            for item_name in selected_items_for_action: print(f"- {item_name}")

            if not ask_to_continue("Proceed with installation?"):
                log_message("User cancelled installation at confirmation prompt.")
                if not ask_to_continue("Return to menu?"): 
                    break
                else:
                    continue 
            
            log_message(f"User confirmed. Selected items for installation: {selected_items_for_action}")
            install_selected_items(selected_items_for_action, active_item_collection, session_item_status_cache)

        if not ask_to_continue("Would you like to install more items?"):
            break 

    print("Exiting program.")
    log_message(f"Script {os.path.basename(__file__)} finished.")

# (ask_to_continue function remains the same)
def ask_to_continue(prompt_message):
    while True:
        try:
            response = input(f"{prompt_message} (y/N): ").strip().lower()
            if response in ['y', 'yes']: return True
            elif response in ['', 'n', 'no']: return False
            else: print("Invalid input. Please enter 'y' or 'n'.")
        except EOFError: print("\nNo input received, assuming No."); return False
        except KeyboardInterrupt: print("\nSelection cancelled by user."); return False

if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    try:
        log_dir = os.path.dirname(LOG_FILE)
        if log_dir and not os.path.exists(log_dir): 
            os.makedirs(log_dir, exist_ok=True)
        with open(LOG_FILE, "a") as f: 
            f.write(f"{datetime.now()}: === {script_name} session started ===\n")
    except Exception as e: 
        print(f"Warning: Could not initialize logging for {LOG_FILE}: {e}", file=sys.stderr)

    if not sys.stdout.isatty():
        print("Error: This script uses curses and must be run in a terminal.", file=sys.stderr)
        log_message("Script aborted: Not running in a TTY.")
        sys.exit(1)
        
    log_message(f"Starting {script_name} script.") 
    main()
