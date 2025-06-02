#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime
import json # <-- Add this import

LOG_FILE = "/tmp/python_game_installer_menus.log" # Consider moving to ~/.cache/your_script_name/ for persistence

# --- Constants for Caching ---
try:
    # Get the base name of the script (e.g., "games-console-by-menu.py")
    script_basename = os.path.basename(__file__)
    # Get the name without the .py extension (e.g., "games-console-by-menu")
    script_name_no_ext = os.path.splitext(script_basename)[0]
    
    CACHE_DIR = os.path.expanduser(os.path.join("~/.cache", script_name_no_ext))
except NameError:
    # Fallback if __file__ is not defined (e.g., running in an interactive interpreter snippet)
    # This is unlikely for a standalone script but good for robustness.
    print("Warning: Could not determine script name dynamically for cache path. Using default.", file=sys.stderr)
    log_message("Warning: __file__ not defined, falling back to default cache directory name 'generic_script_cache'.")
    CACHE_DIR = os.path.expanduser("~/.cache/generic_script_cache")

CACHE_FILE = os.path.join(CACHE_DIR, "statuses.json")

PACKAGE_STATUS_INSTALLED = "INSTALLED"
PACKAGE_STATUS_AVAILABLE = "AVAILABLE"
PACKAGE_STATUS_NOT_AVAILABLE = "NOT_AVAILABLE"
PACKAGE_STATUS_CHECK_ERROR = "ERROR_CHECKING"

HEADER_PREFIX = "### "

AVAILABLE_GAMES = {
    "### ACTION & ARCADE (Graphical)": "Fast-paced, reflex-based, and classic arcade-style games with graphical UIs.",
    "a7xpg": "Alpha-7-XPG - an arcade shooter. Part of Debian's finest games selection. (~2MB)",
    "abe": "Abe's Amazing Adventure - a platformer game. Part of Debian's finest games selection. (~5MB)",
    "alex4": "Alex the Allegator 4 - a simple, retro-style platformer. (~1MB)",
    "amphetamine": "Fast-paced 3D action game: jump between platforms in abstract worlds. (~5MB)",
    "armagetronad": "A 3D lightcycle game in the style of the movie Tron. (~10MB)",
    "assaultcube": "Fast-paced, multiplayer first-person shooter, based on the CUBE engine. (~50MB)",
    "atanks": "Atomic Tanks - a graphical tank battle game, similar to Scorched Earth. Part of Debian's games-strategy selection. (~5MB)",
    "blobby": "Blobby Volley 2 - a fun and simple volleyball game with blobs. (~2MB)",
    "bloboats": "Physics-based boat racing and action game. Part of Debian's finest games selection. (~5MB)",
    "blobwars": "Blob Wars: Metal Blob Solid - a 2D platform shooter. Part of Debian's finest games selection. (~20MB)",
    "btanks": "Battle Tanks - a 2D arcade tank shooter with multiplayer. Part of Debian's finest games selection. (~10MB)",
    "bugsquish": "A simple but addictive game of squishing bugs with your mouse. (~<1MB)",
    "burgerspace": "BurgerSpace - an arcade game clone of BurgerTime. Part of Debian's finest games selection. (~1MB)",
    "bzflag": "A 3D multi-player tank battle game (Battle Zone Flag). (Debian package: bzflag-client) (~25MB)",
    "caveexpress": "Physics-based platformer with a caveman in a wagon. Part of Debian's finest games selection. (~10MB)",
    "ceferino": "Action-adventure game similar to the classic arcade game Pang. (~2MB)",
    "chromium-bsu": "Fast-paced, arcade-style, top-scrolling space shooter. (~5MB)",
    "circuslinux": "Arcade game: control a seesaw to propel clowns to pop balloons. (~<1MB)",
    "criticalmass": "SDL-based vertical shoot'em up, also known as Critical Mass: Stem Cell. (~5MB)",
    "dodgindiamond2": "Arcade-style game: collect diamonds and avoid enemies. (~1MB)",
    "extremetuxracer": "3D downhill racing game featuring Tux. Part of Debian's finest games selection. (~60MB)",
    "frets-on-fire": "Music game: play guitar with the keyboard (Guitar Hero like; or 'fofix'). (~50MB)",
    "frozen-bubble": "Popular puzzle game where you shoot colorful bubbles. (~25MB)", # Also Puzzle
    "funnyboat": "Arcade boat action game. Part of Debian's finest games selection. (~2MB)",
    "funguloids": "Arcade game where you navigate a mushroom in space. Part of Debian's finest games selection. (~1MB)",
    "gltron": "A 3D lightcycle game based on Tron. (~2MB)",
    "gnujump": "Platform game where a penguin jumps on floating ice blocks. (~1MB)",
    "hedgewars": "A turn-based strategy, artillery, action and comedy game (Worms-like). (~200MB)", # Also Strategy
    "jumpnbump": "Cute multiplayer game where bunnies try to jump on each other to win. (~2MB)",
    "kobodeluxe": "Arcade shooter, a more dynamic version of XKobo. Part of Debian's finest games selection. (~2MB)",
    "koules": "Abstract arcade game where you push opponents off the screen. Part of Debian's finest games selection. (~1MB)",
    "lbreakout2": "Breakout-style arcade game with many levels and power-ups. (~5MB)",
    "liquidwar": "Unique multiplayer wargame controlling armies of liquid (older version of liquidwar6). Part of Debian's finest games selection. (~5MB)", # Also Strategy
    "liquidwar6": "A unique multiplayer wargame where you control an army of liquid. (~10MB)", # Also Strategy
    "lugaru": "Lugaru HD - a 3D third-person action game starring an anthropomorphic rabbit. Part of Debian's finest games selection. (~150MB)",
    "marsshooter": "Arcade-style 2D space shooter. Part of Debian's finest games selection. (~1MB)",
    "monster-masher": "Action game where you mash monsters with a hammer. (~1MB)",
    "netpanzer": "Online multiplayer tactical warfare game with tanks. Part of Debian's games-strategy selection. (~20MB)",
    "neverball": "3D arcade game where you tilt the floor to guide a ball. (~20MB)",
    "neverputt": "A 3D miniature golf game, companion to Neverball. (~10MB)",
    "nexuiz": "Classic arena-style first-person shooter (Xonotic is a fork). Part of Debian's finest games selection. (~400MB)",
    "open-invaders": "Space Invaders clone with nice graphics. Part of Debian's finest games selection. (~2MB)",
    "openarena": "Free and open-source first-person shooter based on the Quake III Arena engine. (~500MB)",
    "orbital-eunuchs-sniper": "Quirky 3D sniping game with a unique theme. (~10MB)",
    "pacman": "The classic Pac-Man arcade game. Part of Debian's finest games selection. (~<1MB)",
    "parsec47": "Retro-style vertical scrolling shoot'em up (bullet hell). Part of Debian's finest games selection. (~2MB)",
    "pax-britannica": "One-button real-time strategy game with underwater theme. Part of Debian's games-strategy selection. (~30MB)", # Also Strategy
    "pinball": "Emilia Pinball Emulator - a pinball game. Part of Debian's finest games selection. (~20MB)",
    "polygen": "Abstract space shooter with geometric enemies. (~2MB)",
    "powermanga": "Arcade 2D shoot-em-up with a manga aesthetic. Part of Debian's finest games selection. (~10MB)",
    "rafkill": "Vertical shoot'em up with an emphasis on story and varied enemies. (~5MB)",
    "redeclipse": "Free and open-source first-person shooter, using the Cube 2 engine. Part of Debian's finest games selection. (~600MB)",
    "ri-li": "Arcade game where you drive a toy wooden train collecting coaches. (~10MB)",
    "rocksndiamonds": "Arcade game with elements from Boulder Dash, Emerald Mine, and Supaplex. (~10MB)",
    "scorched3d": "A 3D turn-based artillery game based on the classic Scorched Earth. (~80MB)", # Also Strategy
    "slimevolley": "A simple but surprisingly fun and addictive volleyball game with slimes. (~<1MB)",
    "solarwolf": "Action/arcade game, a Solar Fox clone: collect boxes while avoiding fire. (~1MB)",
    "sopwith": "Classic side-scrolling airplane combat game. Part of Debian's finest games selection. (~<1MB)",
    "supertransball2": "Arcade game inspired by Thrust and Gravitar. Part of Debian's finest games selection. (~2MB)",
    "supertux": "Classic 2D jump'n'run sidescroller featuring Tux. (Note: executable is 'supertux2'). (~100MB)",
    "tecnoballz": "Breakout-style game with many levels and power-ups. Part of Debian's finest games selection. (~2MB)",
    "teeworlds": "Fast-paced 2D multiplayer shooter with physics and cute characters. (~10MB)",
    "torus-trooper": "Abstract 3D tunnel shooter. Part of Debian's finest games selection. (~2MB)",
    "trackballs": "Marble Madness-like game through a labyrinth of ramps and bridges. (~2MB)",
    "tremulous": "Free, open source FPS with aliens vs. humans, and real-time strategy elements. (~300MB)", # Also Strategy
    "tuxfootball": "Arcade-style football (soccer) game with Tux. Part of Debian's finest games selection. (~5MB)",
    "tuxpuck": "Air hockey style game featuring Tux and other characters. Part of Debian's finest games selection. (~2MB)",
    "unvanquished": "Fast-paced, futuristic FPS with RTS elements, spiritual successor to Tremulous. (~1GB+)", # Also Strategy
    "warmux": "Turn-based artillery game featuring mascots of free software projects (Worms-like). Part of Debian's finest games selection. (~150MB)", # Also Strategy
    "xbill": "Stop Bill from installing his evil OS on computers - a classic X11 game. (~<1MB)",
    "xgalaga": "A clone of the classic Galaga arcade game for X11. (~1MB)",
    "xjump": "Simple X11 jumping game: try to get as high as possible. (~<1MB)",
    "xmoto": "Challenging 2D motocross platform game where physics play a big role. (~15MB)",
    "xonotic": "Arena-style first-person shooter with a wide array of weapons and game modes. (~1GB)",
    "xscorch": "XScorched - a clone of Scorched Earth for X11. Part of Debian's games-strategy selection. (~1MB)", # Also Strategy

    "### STRATEGY & TACTICS (Graphical)": "Graphical games involving planning, foresight, and resource management.",
    "0ad": "A free, open-source real-time strategy (RTS) game of ancient warfare. (~1.5GB)",
    "7kaa": "Seven Kingdoms: Ancient Adversaries - a real-time strategy game. Part of Debian's finest games selection. (~50MB)",
    "asc": "Advanced Strategic Command - a turn-based strategy wargame (supports X11/ncurses). Part of Debian's finest games selection. (~10MB)",
    "biloba": "Turn-based strategy board game on a hexagonal map. Part of Debian's games-strategy selection. (~2MB)",
    "boswars": "Futuristic real-time strategy (RTS) game. Part of Debian's games-strategy selection. (~100MB)",
    "crimson": "Crimson Fields - a turn-based tactical war game. Part of Debian's games-strategy selection. (~10MB)",
    "curseofwar": "Real-time strategy game with tower defense elements and map exploration. Part of Debian's games-strategy selection. (~20MB)",
    "endgame-singularity": "Successor to Singularity, guide humanity as an AI (check availability). (~2MB)", # Graphical/complex UI assumed over basic singularity
    "freeciv": "Freeciv - a Civilization-like turn-based strategy game (metapackage). Part of Debian's finest games selection. (~2MB, pulls clients/server)",
    "freeciv-client-gtk": "Freeciv - a Civilization-like turn-based strategy game (GTK client). (~50MB)",
    "freecol": "A free version of Sid Meier's Colonization, a turn-based strategy game. (~100MB)",
    "freeorion": "A turn-based space empire and galactic conquest (4X) game. (~100MB)",
    "gigalomania": "2D real-time strategy game, inspired by Populous and Mega-Lo-Mania. Part of Debian's games-strategy selection. (~10MB)",
    "glob2": "Globulation 2 - an innovative real-time strategy (RTS) game with indirect unit control. (~30MB)",
    # "hedgewars": Already in Action, can be here too.
    "ironseed": "Sci-fi strategy and trading game (DOS game, often run via emulator). Part of Debian's games-strategy selection. (~10MB)",
    "lgeneral": "Turn-based strategy game inspired by Panzer General. Part of Debian's games-strategy selection. (~5MB)",
    "lightyears": "Turn-based space strategy game. Part of Debian's games-strategy selection. (~2MB)",
    # "liquidwar": Already in Action
    "lordsawar": "Turn-based strategy game, a clone of Warlords II. Part of Debian's games-strategy selection. (~5MB)",
    "megaglest": "A free and open source 3D real-time strategy (RTS) game with fantasy elements. (~300MB)",
    "netrek-client-cow": "Client for Netrek, a graphical real-time multiplayer space battle game. Part of Debian's games-strategy selection. (~5MB)",
    "openclonk": "Multiplayer action game involving settlement, mining, and combat in a 2D world. (~150MB)", # Also Action/Sim
    "openttd": "OpenTTD - an open-source clone of Transport Tycoon Deluxe, a business simulation. (~50MB)", # Also Sim
    # "pax-britannica": Already in Action
    "pingus": "A Lemmings-like puzzle/strategy game featuring penguins. (~30MB)", # Also Puzzle
    "pioneers": "A simulation of the board game 'The Settlers of Catan'. (~5MB)", # Also Board
    "planetblupi": "Strategy and puzzle game starring Blupi (Eggbert). Part of Debian's games-strategy selection. (~10MB)", # Also Puzzle
    "qonk": "Abstract strategy game about conquering planets. Part of Debian's games-strategy selection. (~2MB)",
    "spacezero": "Real-time multiplayer space strategy game. Part of Debian's games-strategy selection. (~5MB)",
    "spring": "Powerful open source 3D RTS game engine. Part of Debian's games-strategy selection. (~50MB engine, games vary)",
    "springlobby": "Lobby client for the Spring RTS engine and its games. Part of Debian's finest games selection. (~10MB)",
    "teg": "Turn-based strategy game, similar to Risk. Part of Debian's games-strategy selection. (~2MB)",
    "triplea": "Turn-based strategy game based on Axis & Allies, with many game maps. (~150MB)",
    "ufoai": "UFO: Alien Invasion - squad-based tactical strategy game inspired by X-COM. (~600MB)",
    "unknown-horizons": "A 2D real-time strategy simulation with an emphasis on economy and city building. (~200MB)", # Also Sim
    # "warmux": Already in Action
    "warzone2100": "Post-apocalyptic real-time strategy game with a focus on technology and unit design. (~150MB)",
    "wesnoth": "Battle for Wesnoth - fantasy turn-based strategy. (~600MB)",
    "widelands": "Free, open source real-time strategy game with a focus on settlement building. (~400MB)",
    "xfrisk": "X11 client for playing the board game Risk. Part of Debian's games-strategy selection. (~<1MB)", # Also Board
    # "xscorch": Already in Action

    "### PUZZLE & LOGIC (Graphical)": "Graphical brain teasers, logic challenges, and matching games.",
    "aisleriot": "A collection of over 80 different solitaire card games (GNOME). (~10MB)", # Also Card
    "atomix": "Puzzle game where you build molecules from component atoms. (~1MB)",
    "berusky": "Logic puzzle game where you move Sokoban-like boxes in a 3D environment. Part of Debian's finest games selection. (~10MB)",
    "biniax2": "Puzzle game with arcade elements. Part of Debian's finest games selection. (~1MB)",
    "blockattack": "Block Attack - Rise of the Blocks: a puzzle game similar to Tetris Attack. Part of Debian's finest games selection. (~2MB)",
    "brainparty": "A collection of 36 puzzle games for training your brain. (~15MB)",
    "chromium": "An arcade-style puzzle game with rolling balls (not the browser!). (~2MB)",
    "connectagram": "Word unscrambling puzzle game, form words from jumbled letters. (~1MB)",
    "enigma": "A puzzle game inspired by Oxyd and Rock'n'Roll, with many levels. (~20MB)",
    "epiphany": "Puzzle game with falling blocks and chain reactions. Part of Debian's finest games selection. (~2MB)",
    "fishfillets-ng": "Puzzle game starring two fish, solving logic puzzles by moving objects. (~50MB)",
    "five-or-more": "GNOME game - make lines of five or more colored balls. (~<1MB)",
    "flobopuyo": "A Puyo Puyo clone with network play. (~1MB)",
    "gbrainy": "A brain teaser game with logic puzzles, mental calculation and memory trainers. (~5MB)",
    "gnome-games": "Meta-package for GNOME games (Mines, Sudoku, Mahjongg, etc.). (~1MB, pulls deps)",
    "gnome-mines": "The popular minesweeper puzzle game (GNOME). (~2MB)",
    "gnome-sudoku": "Play and generate Sudoku puzzles (GNOME). (~2MB)",
    "gottet": "A Tetris-like falling blocks game for GNOME. (~<1MB)",
    "gweled": "A 'Diamond Mine' or 'Bejeweled' style game for GNOME. (~<1MB)",
    "hitori": "GNOME puzzle game - eliminate numbers based on rules. (~<1MB)",
    "holotz-castle": "Holotz's Castle - a puzzle game with Sokoban-like elements. Part of Debian's finest games selection. (~5MB)",
    "iagno": "A Reversi/Othello game for GNOME. (~1MB)", # Also Board
    "kapman": "Pac-Man clone for the KDE desktop. (~1MB)", # Also Action
    "kbounce": "JezzBall-like arcade game where you build walls to trap balls (KDE). (~1MB)", # Also Action
    "kfourinline": "Connect Four game for KDE. (~<1MB)", # Also Board
    "kgoldrunner": "Lode Runner arcade game clone by KDE. (~2MB)", # Also Action
    "kjumpingcube": "Simple dice game where you conquer territory (KDE). (~<1MB)", # Also Board
    "klickety": "Clickomania/SameGame puzzle where you clear colored blocks (KDE). (~1MB)",
    "kmahjongg": "Mahjongg solitaire game by KDE. (~5MB)", # Also Board
    "knetwalk": "Puzzle game: connect all terminals to the central server (KDE). (~1MB)",
    "kolf": "Miniature golf game by KDE with various courses. (~10MB)", # Also Sim/Sports
    "kpat": "Solitaire (Patience) card game collection by KDE. (~10MB)", # Also Card
    "kreversi": "Reversi board game by KDE. (~1MB)", # Also Board
    "kshisen": "Shisen-Sho, a Mahjongg-like tile puzzle game (KDE). (~1MB)", # Also Board
    "ksudoku": "Sudoku puzzle game and generator by KDE. (~2MB)",
    "kubrick": "A game based on Rubik's Cube for KDE. (~1MB)",
    "lmemory": "A memory game (Concentration) - graphical version. Part of Debian's finest games selection. (~<1MB)", # Assuming graphical unless specified as console
    "ltris": "A very polished Tetris clone with nice graphics. (~2MB)",
    "monsterz": "Arcade puzzle game similar to Puyo Puyo. (~1MB)",
    "netris": "A networked Tetris clone that can be played over a network or against AI (graphical version assumed here). (~<1MB)",
    "numptyphysics": "A crayon-drawing physics puzzle game where you draw shapes to solve levels. (~5MB)",
    "palapeli": "Jigsaw puzzle game with various features by KDE. (~10MB)",
    "pathological": "A puzzle game involving routing balls along paths of colored tiles. (~1MB)",
    "pentobi": "A computer opponent for the board game Blokus. (~2MB)", # Also Board
    "picmi": "Nonogram/Picross logic puzzle game by KDE. (~1MB)",
    # "pingus": Already in Strategy
    # "planetblupi": Already in Strategy
    "primrose": "A tile-laying puzzle game about placing colored squares. (~<1MB)",
    "pybik": "A Rubik's cube (Pyraminx, Megaminx etc.) game. Part of Debian's finest games selection. (~1MB)",
    "quadrapassel": "A Tetris-like falling block game (GNOME). (~1MB)",
    "raincat": "Physics-based puzzle platformer where you guide a cat with rain. Part of Debian's finest games selection. (~5MB)",
    "sgt-puzzles": "Simon Tatham's Portable Puzzle Collection - many small logic games (graphical frontend). Part of Debian's finest games selection. (~2MB)",
    "swell-foop": "GNOME puzzle game - clear the board by removing groups of colored balls. (~<1MB)",
    "tali": "A sort of poker with dice and less money (GNOME Yahtzee). (~<1MB)", # Also Board

    "### BOARD & CARD (Graphical)": "Digital versions of classic board and card games with graphical UIs.",
    "ace-of-penguins": "Collection of Unix-style penguin-themed card games. (~1MB)",
    # "aisleriot": Already in Puzzle
    # "biloba": Already in Strategy
    "cgoban": "Go board for playing and reviewing SGF Go game files (current version). Part of Debian's finest games selection. (~2MB)",
    "cgoban1": "Go board for playing and reviewing SGF Go game files (older version, still used). (~1MB)",
    "chessx": "Chess database and GUI, PGN viewer and editor. (~10MB)",
    "dreamchess": "A 3D chess game with various board sets and OpenGL graphics. (~20MB)",
    "eboard": "A GTK+ chessboard, alternative to XBoard. (~1MB)",
    "gnubg": "GNU Backgammon - a strong backgammon program with analysis capabilities (usually with graphical interface). (~15MB)",
    "gnuchess": "The GNU Chess program (engine, often used with xboard or eboard - implies graphical use here). (~2MB)",
    "gnushogi": "The GNU Shogi (Japanese Chess) program (engine, often used with graphical interface). (~2MB)",
    "gtkatlantic": "A Monopoly-like game for GNOME. (~1MB)",
    # "iagno": Already in Puzzle
    # "kfourinline": Already in Puzzle
    # "kjumpingcube": Already in Puzzle
    # "kmahjongg": Already in Puzzle
    # "kpat": Already in Puzzle
    # "kreversi": Already in Puzzle
    # "kshisen": Already in Puzzle
    "lexica": "Word puzzle game similar to Boggle. (~<1MB)", # Also Puzzle
    # "pentobi": Already in Puzzle
    # "pioneers": Already in Strategy
    "pokerth": "Texas Hold'em poker game with online play. Part of Debian's finest games selection. (~50MB)",
    "pysolfc": "An extensive collection of more than 1000 solitaire card games. (~5MB)",
    "quarry": "User interface for several board games: Go, Amazons, Reversi. (~1MB)",
    # "tali": Already in Puzzle
    # "teg": Already in Strategy
    "xboard": "A graphical chessboard that can be used as an interface for chess engines. (~1MB)",
    # "xfrisk": Already in Strategy
    "xskat": "The popular German card game Skat for X11. (~<1MB)",

    "### ADVENTURE & RPG (Graphical)": "Story-driven games with exploration and character development with graphical UIs.",
    "ardentryst": "An action/RPG sidescroller with a focus on story and character development. (~30MB)",
    "egoboo": "A 3D open-source dungeon crawling adventure in the spirit of NetHack. (~50MB)",
    "endless-sky": "2D space trading and combat game, similar to Escape Velocity. Part of Debian's games-strategy selection. (~100MB)",
    "flare-game": "Flare: a single-player 2D action RPG engine (often comes with a demo game). (~50MB)",
    "freedink": "Dink Smallwood adventure game engine (data separate or use 'freedink-data'). (~2MB engine)",
    "freedroidrpg": "An isometric RPG featuring Tux, inspired by Diablo. (~100MB)",
    "mana": "Client for The Mana World, a 2D FOSS MMORPG (package 'mana' or 'tmw'). (~30MB)",
    "manaplus": "Client for 2D MMORPGs like The Mana World and Evol Online. Part of Debian's finest games selection. (~30MB)",
    "minetest": "An open-source voxel game engine (Minecraft-like, needs game content/mods). (~30MB core)",
    "naev": "A 2D space trading and combat game, inspired by Escape Velocity. Part of Debian's finest games selection. (~80MB)",
    "residualvm": "Game engine recreation for Grim Fandango and other 3D adventure games. (~5MB, games separate)",
    "scummvm": "Interpreter for many classic graphical point-and-click adventure games. (~10MB, games separate)",
    "stendhal": "A fun, friendly, and free 2D multiplayer online adventure game (Arianne engine). (~20MB client)",
    "valyriatear": "Open-source single-player JRPG-inspired game created with the Godot Engine. (~50MB)",

    "### SIMULATION (Graphical)": "Graphical games that simulate real-world or fictional systems.",
    "bygfoot": "Bygfoot Football Manager - a football (soccer) management game. Part of Debian's games-strategy selection. (~10MB)",
    "colobot": "Educational strategy game teaching programming through robotic missions. Part of Debian's games-strategy selection. (~150MB)", # Also Educational
    "cultivation": "Experimental game about a lonely gardener in a small community. Part of Debian's finest games selection. (~2MB)",
    "dangerdeep": "WWII German submarine simulation. (~50MB)",
    "flightgear": "Open-source flight simulator (VERY large, modular install). (~200MB base, >10GB with scenery)",
    "foobillardplus": "An OpenGL-based 3D billiards (pool) game with realistic physics. (~5MB)",
    # "ironseed": Already in Strategy
    "lincity-ng": "City simulation game, a polished version of LinCity. Part of Debian's finest games selection. (~30MB)",
    "micropolis": "Open source release of the original SimCity game code. Part of Debian's finest games selection. (~2MB)",
    "opencity": "3D city simulator. (~10MB)",
    # "openttd": Already in Strategy
    "searchandrescue": "Search and Rescue - helicopter rescue simulation game. Part of Debian's finest games selection. (~100MB)",
    "speed-dreams": "A fork of TORCS, featuring enhanced visuals and physics in a motorsport simulator. (~700MB)",
    "supertuxkart": "A 3D open-source kart racing game with Tux and friends. (~600MB)", # Also Action
    "torcs": "The Open Racing Car Simulator - a highly portable multi platform car racing simulation. (~300MB)",
    # "unknown-horizons": Already in Strategy
    "vegastrike": "A 3D space combat, trading, and exploration game. (~500MB)",

    "### EDUCATIONAL & KIDS (Graphical)": "Graphical games primarily designed for learning or young children.",
    "blinken": "Simon Says memory game for KDE. (~<1MB)",
    "childsplay": "A suite of educational games for young children. (~50MB)",
    # "colobot": Already in Simulation
    "gcompris-qt": "A high-quality educational software suite, with many activities for children aged 2 to 10. (~300MB)",
    "kanagram": "Anagram game for KDE. (~1MB)",
    "kgeography": "A geography learning tool for KDE. (~10MB)",
    "khangman": "The classic Hangman game for KDE. (~1MB)",
    "klettres": "Learn the alphabet and read syllables in different languages (KDE). (~15MB)",
    "ktuberling": "Potato-themed game for young children (KDE 'Potato Guy'). (~5MB)",
    "kwordquiz": "Flashcard learning program, similar to Anki/Mnemosyne (KDE). (~2MB)",
    "tuxmath": "Tux Math - an arcade game that helps kids practice their math facts. Part of Debian's finest games selection. (~15MB)",
    "tuxtype": "Tux Typing - an educational typing tutor game starring Tux. (~20MB)",

    "### MISCELLANEOUS (Graphical)": "Unique graphical games, or those not fitting other categories.",
    "frozenfriday": "A game about surviving Friday the 13th as a camp counselor. (~1MB)",
    "gnome-nibbles": "A snake game for GNOME, also known as Worms. (~<1MB)",
    "oolite": "A space trading and combat game, inspired by the classic Elite. (~50MB)", # Also Sim/Adventure
    "performous": "Music and rhythm game that supports singing, dancing, and instruments. Part of Debian's finest games selection. (~30MB)",
    "xrick": "A clone of Rick Dangerous, a classic platform-puzzle game. (~1MB)" # Also Action
}

INSTALL_COMMAND_TEMPLATE = "sudo apt-get install -y {packages}"

def log_message(message):
    try:
        # Ensure log directory exists (especially if LOG_FILE is not in /tmp)
        log_dir = os.path.dirname(LOG_FILE)
        if log_dir and not os.path.exists(log_dir):
            os.makedirs(log_dir, exist_ok=True)
        with open(LOG_FILE, "a") as log_file:
            log_file.write(f"{datetime.now()}: {message}\n")
    except Exception as e:
        print(f"Error writing to log file {LOG_FILE}: {e}", file=sys.stderr)

# --- Cache Helper Functions ---
def load_status_cache_from_file(cache_filename):
    if os.path.exists(cache_filename):
        try:
            with open(cache_filename, 'r') as f:
                data = json.load(f)
                log_message(f"Package status cache loaded from {cache_filename}. {len(data)} items.")
                return data
        except json.JSONDecodeError as e:
            log_message(f"Error decoding JSON from cache file {cache_filename}: {e}. Will rebuild.")
            return {}
        except Exception as e:
            log_message(f"Error loading cache file {cache_filename}: {e}. Will rebuild.")
            return {}
    log_message(f"Cache file {cache_filename} not found. Will build anew.")
    return {}

def save_status_cache_to_file(cache_filename, status_cache_data):
    try:
        if not os.path.exists(CACHE_DIR):
            os.makedirs(CACHE_DIR, exist_ok=True)
            log_message(f"Created cache directory: {CACHE_DIR}")
        with open(cache_filename, 'w') as f:
            json.dump(status_cache_data, f, indent=4)
        log_message(f"Package status cache ({len(status_cache_data)} items) saved to {cache_filename}.")
    except Exception as e:
        log_message(f"Error saving cache file {cache_filename}: {e}")
        print(f"Warning: Could not save package status cache to {cache_filename}: {e}", file=sys.stderr)

def get_package_status(package_name, suppress_logging=False):
    env = os.environ.copy()
    env['LC_ALL'] = 'C' # For consistent output from apt/dpkg
    try:
        # Check if installed first
        dpkg_result = subprocess.run(['dpkg', '-l', package_name],
                                     capture_output=True, text=True, check=False, env=env)
        if dpkg_result.returncode == 0:
            for line in dpkg_result.stdout.splitlines():
                parts = line.split()
                # Ensure robust parsing for 'ii' status
                if len(parts) >= 2 and parts[0] == 'ii' and parts[1] == package_name:
                    return PACKAGE_STATUS_INSTALLED
    except FileNotFoundError: # dpkg not found
        if not suppress_logging: log_message(f"dpkg command not found during check for {package_name}.")
        # Fall through to apt-cache check if dpkg fails, or return error if critical
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during dpkg -l check for {package_name}: {e}")

    # If not installed or dpkg check failed, check if available via apt-cache
    try:
        apt_show_result = subprocess.run(['apt-cache', 'show', package_name],
                                         capture_output=True, text=True, check=False, env=env)
        if apt_show_result.returncode == 0 and apt_show_result.stdout.strip(): # Ensure there's output
            return PACKAGE_STATUS_AVAILABLE
        else:
            # Log only if it's an unexpected error, not just "package not found"
            if not suppress_logging and apt_show_result.returncode != 0 and "No GPG key" not in apt_show_result.stderr: # Common warning, not an error for availability
                 # Only log if stderr seems to indicate a problem beyond not finding the package
                if "E: No packages found" not in apt_show_result.stderr and "Unable to locate package" not in apt_show_result.stderr:
                    log_message(f"apt-cache show for '{package_name}' error. RC: {apt_show_result.returncode}. Stderr: {apt_show_result.stderr.strip()}")
            return PACKAGE_STATUS_NOT_AVAILABLE
    except FileNotFoundError: # apt-cache not found
        if not suppress_logging: log_message(f"apt-cache command not found during check for {package_name}.")
        return PACKAGE_STATUS_CHECK_ERROR # Critical if apt-cache is missing
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during apt-cache show for {package_name}: {e}")
        return PACKAGE_STATUS_CHECK_ERROR
    
    # If dpkg check ran but didn't find it as 'ii', and apt-cache didn't find it as available, it's NOT_AVAILABLE
    return PACKAGE_STATUS_NOT_AVAILABLE


def get_formatted_header_text(item_name_key):
    header_content = item_name_key[len(HEADER_PREFIX):].strip().upper()
    return f"--- {header_content} ---" # Added extra dashes for visibility

def manage_cache_and_display_menu(stdscr, item_definitions, status_cache_dict, force_full_rebuild_all):
    # status_cache_dict is the main cache dictionary, pre-populated if loaded from file.
    # force_full_rebuild_all means ignore existing data and check ALL items.

    if not curses.has_colors():
        # This check might be better in main before curses.wrapper
        raise RuntimeError("Terminal does not support colors.")
    try:
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
        curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal / Available / Header
        curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # Error text
        curses.init_pair(4, curses.COLOR_GREEN, curses.COLOR_BLACK)  # Installed Item Name / Legend
        curses.init_pair(5, curses.COLOR_YELLOW, curses.COLOR_BLACK) # Yellow Key Hint
    except curses.error as e:
        # This error usually means initscr() hasn't been called by wrapper yet,
        # or too many colors. Should be rare if wrapper handles initscr.
        raise RuntimeError(f"Error initializing colors: {e}. This may be a curses setup issue.")


    items_that_need_checking_now = []
    if force_full_rebuild_all:
        log_message("User opted for full cache rebuild. Clearing existing loaded statuses for re-check.")
        status_cache_dict.clear() # Clear all old statuses
        for item_name_key in item_definitions.keys():
            if not item_name_key.startswith(HEADER_PREFIX):
                items_that_need_checking_now.append(item_name_key)
    else: # Not a full rebuild, just check missing items
        for item_name_key in item_definitions.keys():
            if not item_name_key.startswith(HEADER_PREFIX):
                if item_name_key not in status_cache_dict: # Check if name not in cache
                    items_that_need_checking_now.append(item_name_key)
        if items_that_need_checking_now:
             log_message(f"Checking status for {len(items_that_need_checking_now)} new/uncached items.")
        else:
             log_message("No new/uncached items to check. Using existing cache for all known items.")

    if items_that_need_checking_now:
        stdscr.clear()
        h_loader, w_loader = stdscr.getmaxyx()
        loading_line_y = h_loader // 2
        title_verb = "Building" if force_full_rebuild_all else "Updating"
        title_message = f"{title_verb} package status cache. This may take a moment..."
        
        def safe_addstr_loader(y, x, text, attr=0): # Local helper for loader
            if 0 <= y < h_loader and 0 <= x < w_loader and x + len(text) <= w_loader:
                stdscr.addstr(y, x, text, attr)
            elif 0 <= y < h_loader and 0 <= x < w_loader : # Truncate if too long
                stdscr.addstr(y, x, text[:w_loader-x-1], attr)
        
        title_x = max(0, (w_loader - len(title_message)) // 2)
        if loading_line_y > 0 : safe_addstr_loader(loading_line_y -1 , title_x, title_message)
        elif loading_line_y >=0 : safe_addstr_loader(loading_line_y , title_x, title_message)

        checked_count = 0
        cache_update_start_time = time.time()
        total_items_to_check_now = len(items_that_need_checking_now)

        for item_name_key in items_that_need_checking_now:
            checked_count += 1
            progress_percent = (checked_count * 100) // total_items_to_check_now if total_items_to_check_now > 0 else 100
            bar_width = 20; filled_len = int(bar_width * progress_percent // 100)
            bar = '#' * filled_len + '-' * (bar_width - filled_len)
            progress_prefix = f"[{bar}] {progress_percent}% "
            checking_text = "Checking: "
            
            available_for_name = w_loader - len(progress_prefix) - len(checking_text) - 4 # Account for margins/spacing
            display_item_name_progress = item_name_key
            if len(item_name_key) > available_for_name and available_for_name > 3: # Ensure space for ellipsis
                display_item_name_progress = item_name_key[:available_for_name-3] + "..."
            elif available_for_name <=3 : display_item_name_progress = ""; checking_text = ""


            if loading_line_y < h_loader :
                stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
                full_progress_message = f"{progress_prefix}{checking_text}{display_item_name_progress}"
                safe_addstr_loader(loading_line_y, 0, full_progress_message)
            stdscr.refresh()
            status_cache_dict[item_name_key] = get_package_status(item_name_key, suppress_logging=True)

        cache_update_duration = time.time() - cache_update_start_time
        log_message(f"Item status cache {title_verb.lower()} in {cache_update_duration:.2f}s for {checked_count} items.")
        
        if loading_line_y < h_loader: # Final message for cache update
            stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
            final_cache_message = f"Cache {title_verb.lower()}: {checked_count} items in {cache_update_duration:.2f}s."
            msg_x_final = max(0, (w_loader - len(final_cache_message)) // 2)
            safe_addstr_loader(loading_line_y, msg_x_final, final_cache_message)
            stdscr.refresh()
            time.sleep(1.0 if checked_count > 0 else 0.3) # Shorter sleep if nothing was actually checked.
    else:
        log_message("No items required status checking; using existing/loaded cache as is.")
        # Optionally, show a very brief "Using cached statuses..." message if desired.
        # For now, no visual feedback if nothing was checked to speed up launch.

    return display_menu(stdscr, item_definitions, status_cache_dict)


def display_menu(stdscr, item_definitions, status_cache):
    # ... (display_menu function remains largely the same as your provided one) ...
    # It will use the status_cache dict passed to it.
    # Ensure curses.curs_set(0) is called, usually done by wrapper or at start of this func.
    curses.curs_set(0)

    item_names = list(item_definitions.keys()) 
    if not item_names:
        # Simplified error display if no items
        stdscr.addstr(0,0, "No items loaded to display in menu.", curses.color_pair(3))
        stdscr.refresh()
        time.sleep(2) # Give time to read
        return None # Indicate quit or error

    checked_items = {name: False for name in item_names if not name.startswith(HEADER_PREFIX)}
    select_all_items = False
    highlighted_linear_idx = 0
    display_column_offset = 0

    # Ensure first non-header item is highlighted if list starts with headers
    first_selectable_idx = 0
    for idx, name in enumerate(item_names):
        if not name.startswith(HEADER_PREFIX):
            first_selectable_idx = idx
            break
    highlighted_linear_idx = first_selectable_idx


    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            footer_content_height = 8 
            footer_height_needed = footer_content_height + 1 

            if height < footer_height_needed + 1 or width < 50: # Min terminal size
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(0, 0, "Terminal too small.")
                stdscr.addstr(1,0, f"Need {footer_height_needed+1}H x 50W. Press Q or resize.")
                stdscr.attroff(curses.color_pair(3))
                stdscr.refresh()
                key = stdscr.getch()
                if key == ord('q') or key == ord('Q'): return None
                continue
            
            max_len_game_name_only = 0
            game_item_names = [n for n in item_names if not n.startswith(HEADER_PREFIX)]
            if game_item_names:
                max_len_game_name_only = max(len(name) for name in game_item_names) if game_item_names else 20
            else: # Handle case with no game items (only headers)
                max_len_game_name_only = 20 # Default if no games

            max_game_line_len = 4 + max_len_game_name_only + 2 # "[X] " + name + " ✓"

            max_len_formatted_header = 0
            header_item_names = [n for n in item_names if n.startswith(HEADER_PREFIX)]
            if header_item_names:
                max_len_formatted_header = max(len(get_formatted_header_text(h_name)) for h_name in header_item_names)
            
            max_text_len_for_item = max(max_game_line_len, max_len_formatted_header, 10) 

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
                current_attributes = curses.color_pair(2) 

                if is_header:
                    display_string = get_formatted_header_text(item_name)
                    current_attributes |= curses.A_BOLD 
                else: 
                    checkbox = "[X]" if checked_items.get(item_name, False) else "[ ]"
                    status = status_cache.get(item_name, PACKAGE_STATUS_CHECK_ERROR)
                    item_marker = ""
                    if status == PACKAGE_STATUS_INSTALLED:
                        current_attributes = curses.color_pair(4) 
                        item_marker = " ✓"
                    elif status == PACKAGE_STATUS_AVAILABLE:
                        current_attributes = curses.color_pair(2) 
                    elif status == PACKAGE_STATUS_NOT_AVAILABLE or status == PACKAGE_STATUS_CHECK_ERROR:
                        current_attributes = curses.color_pair(2) | curses.A_DIM 
                    display_string = f"{checkbox} {item_name}{item_marker}"
                
                display_string_padded = display_string.ljust(max_text_len_for_item)

                final_attributes_to_apply = current_attributes
                if idx == highlighted_linear_idx:
                    final_attributes_to_apply = curses.color_pair(1) 
                    if is_header: 
                        final_attributes_to_apply |= curses.A_BOLD
                
                if 0 <= screen_y < height and 0 <= screen_x < width:
                        stdscr.addstr(screen_y, screen_x, display_string_padded[:width-screen_x], final_attributes_to_apply)
            
            # --- Footer Drawing ---
            air_gap_line = num_display_rows 
            instruction_y_base = air_gap_line + 1
            instr_line_y = instruction_y_base

            def draw_line_safely(y, content_parts): 
                if y < height:
                    stdscr.move(y, 0)
                    current_x_footer = 0
                    for part_text, part_attr in content_parts:
                        if current_x_footer < width -1:
                            drawable_len = min(len(part_text), width - 1 - current_x_footer)
                            stdscr.addstr(part_text[:drawable_len], part_attr)
                            current_x_footer += drawable_len
                        else: break
                    stdscr.clrtoeol()
            
            draw_line_safely(instr_line_y, [("Arrows/PgUp/PgDn/Home/End. Space=toggle. Ctrl+A=all.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("'", curses.A_BOLD), ("I", curses.color_pair(5) | curses.A_BOLD),("' to install ", curses.A_BOLD), ("selected", curses.color_pair(2) | curses.A_BOLD),(". '", curses.A_BOLD), ("Q", curses.color_pair(5) | curses.A_BOLD),("' to quit.", curses.A_BOLD)])
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
                if description_area_y_start < height: 
                    stdscr.move(description_area_y_start, 0); stdscr.clrtoeol()
                    stdscr.addstr(description_area_y_start, 0, desc_header[:width-1])

                actual_desc_text = item_definitions.get(current_item_name, "No description available.")
                if description_area_y_start + 1 < height: 
                    stdscr.move(description_area_y_start + 1, 0); stdscr.clrtoeol()
                    stdscr.addstr(description_area_y_start + 1, 0, actual_desc_text[:width-1])
            stdscr.refresh()

            key = stdscr.getch()
            num_items = len(item_names)
            if not num_items: continue

            # --- Key handling ---
            if key == curses.KEY_UP:
                if current_highlighted_row_in_col > 0: highlighted_linear_idx -= 1
                elif current_highlighted_logical_col > 0: 
                    target_col_last_item_idx = (current_highlighted_logical_col * num_display_rows) -1
                    highlighted_linear_idx = min(target_col_last_item_idx, num_items -1)
                else: # At top of first column, wrap to bottom of last column
                    highlighted_linear_idx = num_items -1

            elif key == curses.KEY_DOWN:
                if current_highlighted_row_in_col < num_display_rows - 1 and highlighted_linear_idx + 1 < num_items: 
                    highlighted_linear_idx += 1
                elif current_highlighted_logical_col + 1 < total_logical_columns and \
                    (current_highlighted_logical_col + 1) * num_display_rows < num_items : 
                    highlighted_linear_idx = (current_highlighted_logical_col + 1) * num_display_rows
                elif highlighted_linear_idx +1 >= num_items : # At bottom of last col, wrap to top of first
                    highlighted_linear_idx = 0


            elif key == curses.KEY_LEFT:
                if current_highlighted_logical_col > 0:
                    new_idx_target = (current_highlighted_logical_col - 1) * num_display_rows + current_highlighted_row_in_col
                    max_idx_in_prev_col = min( (current_highlighted_logical_col * num_display_rows) -1 , num_items -1)
                    highlighted_linear_idx = min(new_idx_target, max_idx_in_prev_col)
                else: # At first column, wrap to last column if multiple logical columns exist
                    if total_logical_columns > 1:
                        target_col = total_logical_columns -1
                        new_idx_target = target_col * num_display_rows + current_highlighted_row_in_col
                        highlighted_linear_idx = min(new_idx_target, num_items-1)


            elif key == curses.KEY_RIGHT:
                if current_highlighted_logical_col < total_logical_columns - 1:
                    new_idx_target = (current_highlighted_logical_col + 1) * num_display_rows + current_highlighted_row_in_col
                    highlighted_linear_idx = min(new_idx_target, num_items - 1)
                elif total_logical_columns > 1 : # At last column, wrap to first column
                    target_col = 0
                    new_idx_target = target_col * num_display_rows + current_highlighted_row_in_col
                    highlighted_linear_idx = min(new_idx_target, num_items-1)


            elif key == curses.KEY_PPAGE: 
                highlighted_linear_idx = max(0, highlighted_linear_idx - num_display_rows)
            elif key == curses.KEY_NPAGE: 
                highlighted_linear_idx = min(num_items - 1, highlighted_linear_idx + num_display_rows)
            elif key == curses.KEY_HOME: 
                highlighted_linear_idx = 0 # Go to very first item overall
            elif key == curses.KEY_END: 
                highlighted_linear_idx = num_items - 1 # Go to very last item overall
            elif key == ord(" "):
                if 0 <= highlighted_linear_idx < num_items:
                    item_to_toggle = item_names[highlighted_linear_idx]
                    if not item_to_toggle.startswith(HEADER_PREFIX): 
                        status_toggle = status_cache.get(item_to_toggle, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle == PACKAGE_STATUS_INSTALLED or status_toggle == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_to_toggle] = not checked_items[item_to_toggle]
                        else: curses.flash() 
                    else: curses.flash() 
            elif key == 1:  # Ctrl+A
                select_all_items = not select_all_items
                for item_name_iter in item_names:
                    if not item_name_iter.startswith(HEADER_PREFIX): 
                        status_toggle_all = status_cache.get(item_name_iter, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle_all == PACKAGE_STATUS_INSTALLED or status_toggle_all == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_name_iter] = select_all_items
                        elif not select_all_items: 
                            checked_items[item_name_iter] = False
            elif key == ord("i") or key == ord("I") :
                selected_to_install = [item for item, is_checked in checked_items.items() if is_checked and not item.startswith(HEADER_PREFIX)]
                return selected_to_install
            elif key == ord("q") or key == ord("Q"):
                return None
            elif key == curses.KEY_RESIZE: pass # Handled by loop re-calculating dimensions

            # Auto-paging logic to ensure highlighted item is visible
            if num_items > 0 and num_display_rows > 0:
                highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_items - 1)) # Clamp index
                
                # Ensure first selectable item is highlighted if current is header
                while item_names[highlighted_linear_idx].startswith(HEADER_PREFIX) and highlighted_linear_idx +1 < num_items :
                    highlighted_linear_idx +=1 # Move down to next
                    if key == curses.KEY_UP : # if moving up into header, try to go past it upwards
                        highlighted_linear_idx -=2 # one for current, one more
                        highlighted_linear_idx = max(0, highlighted_linear_idx)
                        if item_names[highlighted_linear_idx].startswith(HEADER_PREFIX): # if still header, go to first selectable
                             highlighted_linear_idx = first_selectable_idx
                        break # break inner loop after adjustment

                new_curr_hl_logical_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0

                if new_curr_hl_logical_col >= display_column_offset + num_display_columns_on_screen:
                    display_column_offset = min(max_possible_offset, new_curr_hl_logical_col - num_display_columns_on_screen + 1)
                elif new_curr_hl_logical_col < display_column_offset:
                    display_column_offset = max(0, new_curr_hl_logical_col)
                
                # After HOME or END key, adjust view
                if key == curses.KEY_HOME: display_column_offset = 0
                elif key == curses.KEY_END:
                    if num_display_rows > 0:
                        last_item_logical_col = (num_items - 1) // num_display_rows
                        display_column_offset = max(0, last_item_logical_col - num_display_columns_on_screen + 1)
                        display_column_offset = min(display_column_offset, max_possible_offset)

        except curses.error as e: # Catch curses-specific errors for resilience
            log_message(f"Curses error in display_menu: {e}")
            # Typical errors are often related to trying to write outside screen bounds during resize
            if "ERR" in str(e) or "addwstr" in str(e) or "addstr" in str(e) or "waddwstr" in str(e):
                time.sleep(0.05) # Small delay and retry, window might be resizing
                continue # Retry the loop
            else: # For other curses errors, re-raise
                raise 
        except Exception as e:
            log_message(f"Unexpected error in display_menu: {e}, {type(e)}")
            # Clean up curses before raising, if possible
            if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
                try: curses.nocbreak(); curses.echo(); curses.endwin()
                except: pass
            raise


def install_selected_items(selected_items_list, item_definitions_dict, status_cache_to_update):
    # ... (install_selected_items function remains the same) ...
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
        if item_name.startswith(HEADER_PREFIX): continue 

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
    if not_available_skipped: print(f"Skipping (not in repos / error): {', '.join(not_available_skipped + error_checking_skipped)}")
    # if error_checking_skipped: print(f"Skipping (error/unknown status): {', '.join(error_checking_skipped)}") # Merged above

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
                new_status = get_package_status(item_name_verify) # Re-check status after install
                status_cache_to_update[item_name_verify] = new_status # Update the main cache
                if new_status == PACKAGE_STATUS_INSTALLED:
                    print(f"  ✓ {item_name_verify} is now INSTALLED.")
                    successfully_installed_in_batch.append(item_name_verify)
                else:
                    print(f"  ✗ {item_name_verify} still not INSTALLED (status: {new_status}). Apt reported success but verification failed.")
        else:
            print(f"\n✗ Installation command failed (RC:{process.returncode}) for: {', '.join(items_to_actually_install)}")
            log_message(f"Command failed (code {process.returncode}): {install_command}")
            print("Re-checking status of items for which apt reported errors...")
            for item_name_failed in items_to_actually_install: 
                status_cache_to_update[item_name_failed] = get_package_status(item_name_failed, suppress_logging=True)
    except Exception as e:
        print(f"An unexpected error occurred during installation: {e}")
        log_message(f"Exception during installation command '{install_command}': {e}")

    total_runtime = time.time() - overall_start_time
    print(f"\nInstallation attempt finished for batch. Runtime: {total_runtime:.2f} seconds.")


def ask_to_continue(prompt_message):
    # ... (ask_to_continue function remains the same) ...
    while True:
        try:
            response = input(f"{prompt_message} (y/N): ").strip().lower()
            if response in ['y', 'yes']: return True
            elif response in ['', 'n', 'no']: return False
            else: print("Invalid input. Please enter 'y' or 'n'.")
        except EOFError: print("\nNo input received, assuming No."); return False
        except KeyboardInterrupt: print("\nSelection cancelled by user."); return False


def main():
    def graceful_signal_handler(sig, frame):
        if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
            try: curses.nocbreak(); curses.echo(); curses.endwin()
            except Exception as e_curses: log_message(f"Error during curses cleanup on SIGINT: {e_curses}")
        print("\nProgram terminated by user (Ctrl+C).")
        log_message("Program terminated by SIGINT.")
        sys.exit(0)

    signal.signal(signal.SIGINT, graceful_signal_handler)

    active_item_collection = AVAILABLE_GAMES
    collection_name_for_messages = "AVAILABLE_GAMES_TEXT" # Assuming this script is for text games

    if not active_item_collection:
        print(f"No items defined in {collection_name_for_messages}. Nothing to do.")
        log_message(f"{collection_name_for_messages} dictionary is empty.")
        return

    # --- Caching Logic at Start ---
    session_item_status_cache = load_status_cache_from_file(CACHE_FILE)
    force_first_full_rebuild = False 

    if session_item_status_cache: # If cache was loaded (even if empty from error)
        print("Existing package status cache found (or cache file exists).")
        if ask_to_continue("Recheck all apps and update full cache? (Potentially slow)"):
            log_message("User opted to rebuild the full package status cache.")
            force_first_full_rebuild = True
        else:
            log_message("User opted to use existing package status cache. Will check for new/unknown items only.")
            force_first_full_rebuild = False
    else: # No cache file found or error loading it meant empty dict returned
        print("No package status cache file found (or it was empty/corrupt). Building a new one.")
        log_message("No valid cache file. Performing initial full cache build.")
        force_first_full_rebuild = True
    
    initial_cache_management_done_this_session = False

    while True:
        selected_items_for_action = None
        try:
            # Determine if this specific run of the menu needs to force a full rebuild.
            # This is true only for the very first time the menu is shown if the user opted for it,
            # or if no cache existed. Subsequent loops (Install More?) use the existing session cache.
            current_run_force_rebuild_flag = False
            if not initial_cache_management_done_this_session:
                current_run_force_rebuild_flag = force_first_full_rebuild
                initial_cache_management_done_this_session = True # Mark that initial decision/build has been processed for this session

            selected_items_for_action = curses.wrapper(
                manage_cache_and_display_menu, # New function name
                active_item_collection,
                session_item_status_cache,     # This is the live cache for the session
                current_run_force_rebuild_flag # Pass the decision for this run
            )
        except RuntimeError as e:
            # Handle no-colors error specifically if not caught earlier
            if "Terminal does not support colors" in str(e) or "Error initializing colors" in str(e) :
                print(f"Error: {e}. This script requires a terminal with color support.", file=sys.stderr)
                log_message(f"Curses color support error: {e}")
            else:
                print(f"A runtime error occurred: {e}")
                log_message(f"RuntimeError from menu session: {e}")
            break # Exit on runtime errors from curses setup
        except Exception as e:
            if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
                try: curses.endwin()
                except: pass # Ignore errors during cleanup
            print(f"An unexpected error occurred running the menu: {e}")
            log_message(f"Unhandled exception in main around curses.wrapper: {e}, {type(e)}")
            import traceback
            log_message(traceback.format_exc())
            break

        if selected_items_for_action is None:
            log_message("User quit the menu or menu failed to initialize.")
            break 
        elif not selected_items_for_action:
            log_message("User proceeded from menu but no items were checked.")
            if not ask_to_continue("No items checked. Return to menu?"):
                break
            else:
                continue 
        else: # Items were selected
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
            # Save cache after installation as statuses might have changed
            save_status_cache_to_file(CACHE_FILE, session_item_status_cache)

        if not ask_to_continue("Would you like to install more items or return to the menu?"):
            break
    
    # Save cache one last time on normal exit, if the initial cache phase was passed.
    if initial_cache_management_done_this_session:
        save_status_cache_to_file(CACHE_FILE, session_item_status_cache)
    
    print("Exiting program.")
    log_message(f"Script {os.path.basename(__file__)} finished.")


if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    try:
        log_dir = os.path.dirname(LOG_FILE)
        if log_dir and not os.path.exists(log_dir): # Check if log_dir is not empty string
            os.makedirs(log_dir, exist_ok=True)
        with open(LOG_FILE, "a") as f: # Open in append mode
            f.write(f"\n{datetime.now()}: === {script_name} session started ===\n")
    except Exception as e:
        print(f"Warning: Could not initialize logging for {LOG_FILE}: {e}", file=sys.stderr)

    if not sys.stdout.isatty():
        print("Error: This script uses curses and must be run in a terminal.", file=sys.stderr)
        log_message("Script aborted: Not running in a TTY.")
        sys.exit(1)

    log_message(f"Starting {script_name} script.")
    main()
