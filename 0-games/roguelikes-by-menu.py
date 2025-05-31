#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime

LOG_FILE = "/tmp/roguelike_get_menus.log"

# --- Roguelike Definitions ---
ROGUELIKES = {
    "angband": {
        "display_name": "Angband", "year_created": 1990, "package_name": "angband", "executable": "angband",
        "description": "Single-player, text-based, dungeon simulation game. One of the 'greats'.",
        "install_type": "apt", "source_url": "https://rephial.org/", "notes": "Many variants exist."
    },
    "rogue-bsd": {
        "display_name": "Rogue (BSD)", "year_created": 1980, "package_name": "bsdgames-nonfree", "executable": "rogue",
        "description": "The original classic dungeon exploration game that started the genre.",
        "install_type": "apt", "source_url": "N/A (part of bsdgames)", "notes": "Requires bsdgames-nonfree package."
    },
    "crawl": {
        "display_name": "Dungeon Crawl Stone Soup (Console)", "year_created": 1997, "package_name": "crawl", "executable": "crawl",
        "description": "A popular and widely acclaimed roguelike with diverse species and gods.",
        "install_type": "apt", "source_url": "https://crawl.develz.org/", "notes": "Tiles version: crawl-tiles"
    },
    "crawl-tiles": {
        "display_name": "Dungeon Crawl Stone Soup (Tiles)", "year_created": 1997, "package_name": "crawl-tiles", "executable": "crawl-xtile",
        "description": "Graphical tiles version of Dungeon Crawl Stone Soup.",
        "install_type": "apt", "source_url": "https://crawl.develz.org/", "notes": ""
    },
    "lambdahack": {
        "display_name": "LambdaHack", "year_created": 2011, "package_name": "lambdahack", "executable": "LambdaHack",
        "description": "Tactical squad ASCII roguelike dungeon crawler game engine and game.",
        "install_type": "apt", "source_url": "https://lambdahack.github.io/", "notes": ""
    },
    "moria": {
        "display_name": "Moria (Umoria)", "year_created": 1983, "package_name": "moria", "executable": "moria",
        "description": "Rogue-like game with an infinite dungeon, based on Tolkien's Moria.",
        "install_type": "apt", "source_url": "http://umoria.org/", "notes": "Also known as Umoria."
    },
    "nethack-console": {
        "display_name": "NetHack (Console)", "year_created": 1987, "package_name": "nethack-console", "executable": "nethack",
        "description": "A deeply complex and iconic roguelike. 'The DevTeam thinks of everything.'",
        "install_type": "apt", "source_url": "https://www.nethack.org/", "notes": "Graphical versions also available."
    },
    "nethack-qt": {
        "display_name": "NetHack (Qt)", "year_created": 1987, "package_name": "nethack-qt", "executable": "NetHackQt",
        "description": "NetHack with a Qt graphical interface.",
        "install_type": "apt", "source_url": "https://www.nethack.org/", "notes": ""
    },
    "nethack-x11": {
        "display_name": "NetHack (X11)", "year_created": 1987, "package_name": "nethack-x11", "executable": "nethack",
        "description": "NetHack with an X11 graphical interface.",
        "install_type": "apt", "source_url": "https://www.nethack.org/", "notes": ""
    },
    "omega-rpg": {
        "display_name": "Omega", "year_created": 1988, "package_name": "omega-rpg", "executable": "omega",
        "description": "A complex text-based roguelike with a large overworld and many features.",
        "install_type": "apt", "source_url": "N/A (archived)", "notes": "Can be challenging to get into."
    },
    "powder": {
        "display_name": "POWDER", "year_created": 2003, "package_name": "powder", "executable": "powder",
        "description": "Graphical dungeon crawling game originally for GBA, ported to PC.",
        "install_type": "apt", "source_url": "http://www.zincland.com/powder/", "notes": ""
    },
    "slashem": {
        "display_name": "Slash'EM", "year_created": 1996, "package_name": "slashem", "executable": "slashem",
        "description": "A popular and extensive variant of NetHack.",
        "install_type": "apt", "source_url": "http://www.slashem.org/", "notes": ""
    },
    "tome2": {
        "display_name": "Tales of Middle Earth (ToME 2.x)", "year_created": 1998, "package_name": "tome", "executable": "tome",
        "description": "The precursor to modern Tales of Maj'Eyal, based on Angband.",
        "install_type": "apt", "source_url": "http://www.t-o-m-e.net/legacy.php", "notes": "This is the classic version, not T-Engine 4."
    },
    "allure": {
        "display_name": "Allure of the Stars", "year_created": 2012, "package_name": "allure", "executable": "allure",
        "description": "A science-fiction roguelike about exploring star systems and planets.",
        "install_type": "apt", "source_url": "http://allure.sourceforge.net/", "notes": ""
    },
    "boohu": {
        "display_name": "Boohu", "year_created": 2016, "package_name": "boohu", "executable": "boohu",
        "description": "A coffee-break roguelike focusing on tactical decisions and minimalist design.",
        "install_type": "apt", "source_url": "https://github.com/KuidKoder/boohu", "notes": ""
    },
    "cataclysm-dda-sdl": {
        "display_name": "Cataclysm: Dark Days Ahead (SDL/Tiles)", "year_created": 2013, "package_name": "cataclysm-dda-sdl", "executable": "cataclysm-tiles",
        "description": "In-depth post-apocalyptic survival roguelike with crafting, building, and mutations.",
        "install_type": "apt", "source_url": "https://cataclysmdda.org/", "notes": "Console version often 'cataclysm-dda'."
    },
    "gearhead": {
        "display_name": "GearHead 1", "year_created": 2002, "package_name": "gearhead", "executable": "gearhead",
        "description": "A mecha roguelike with a complex storyline, procedural generation, and tactical combat.",
        "install_type": "apt", "source_url": "http://gearhead.sourceforge.net/", "notes": ""
    },
    "gearhead2": {
        "display_name": "GearHead 2", "year_created": 2007, "package_name": "gearhead2", "executable": "gearhead2",
        "description": "Successor to GearHead, continuing the mecha roguelike themes with enhancements.",
        "install_type": "apt", "source_url": "https://github.com/jwvhewitt/gearhead2", "notes": ""
    },
    "hearse": {
        "display_name": "Hearse", "year_created": 2001, "package_name": "hearse", "executable": "hearse",
        "description": "A variant of NetHack focusing on graveyards, the undead, and darker themes.",
        "install_type": "apt", "source_url": "http://hearse.sourceforge.net/", "notes": ""
    },
    "hyperrogue": {
        "display_name": "HyperRogue", "year_created": 2011, "package_name": "hyperrogue", "executable": "hyperrogue",
        "description": "A unique roguelike set on a hyperbolic plane, leading to mind-bending tactical gameplay.",
        "install_type": "apt", "source_url": "http://www.roguetemple.com/z/hyper/", "notes": ""
    },
    # --- Custom Install Examples ---
    "fangband": {
        "display_name": "FAngband", "year_created": 1998, "package_name": None, "executable": "fangband",
        "description": "A variant of Angband known for its difficulty, unique monsters, and extensive features.",
        "install_type": "custom", "source_url": "https://github.com/FAangband/FAangband",
        "custom_install_instructions": """1. Ensure you have build tools: sudo apt install build-essential autoconf libncursesw5-dev libx11-dev libxaw7-dev libxext-dev
2. Clone the repository: git clone https://github.com/FAangband/FAangband.git
3. cd FAngband
4. ./autogen.sh
5. ./configure --with-no-x --enable-curses
6. make
7. sudo make install
The executable is typically 'fangband' in the src/ directory or /usr/local/bin/ after install.""",
        "notes": "Compilation required. Instructions are a general guide."
    },
    "sil-q": {
        "display_name": "Sil (Q)", "year_created": 2007, "package_name": None, "executable": "./sil",
        "description": "A roguelike inspired by Tolkien's Silmarillion, focusing on stealth, skill, and atmosphere. Sil(Q) is a maintained fork.",
        "install_type": "custom", "source_url": "https://github.com/sil-q/sil-q",
        "custom_install_instructions": """1. Go to: https://github.com/sil-q/sil-q/releases
2. Download the latest Linux binary (e.g., sil-X.Y.Z-linux.tar.gz).
3. Create a directory (e.g., ~/games/sil-q) and cd into it.
4. Extract: tar -xzvf /path/to/downloaded/sil-X.Y.Z-linux.tar.gz
5. Run from this directory: ./sil""",
        "notes": "Sil(Q) is generally preferred over original Sil for active development."
    },
    "brogue-ce": {
        "display_name": "Brogue (Community Edition)", "year_created": 2009,
        "package_name": None, "executable": "./brogue",
        "description": "A highly-regarded roguelike known for its simple interface, beautiful ASCII graphics, and deep tactical gameplay.",
        "install_type": "custom", "source_url": "https://github.com/tsadok/brogue-ce",
        "custom_install_instructions": """1. Go to https://github.com/tsadok/brogue-ce/releases
2. Download the appropriate precompiled binary for Linux (e.g., brogue-linux-amd64.tbz2).
3. Create a directory (e.g., ~/games/brogue-ce) and cd into it.
4. Extract the archive (e.g., tar -xjvf /path/to/brogue-linux-amd64.tbz2).
5. Run with: ./brogue""",
        "notes": "Community Edition (CE) is actively maintained."
    },
    "adom": {
        "display_name": "ADOM (Ancient Domains Of Mystery)", "year_created": 1994,
        "package_name": None, "executable": "./adom",
        "description": "Classic, deep roguelike with a rich storyline, multiple races/classes, and a large world.",
        "install_type": "custom", "source_url": "https://www.adom.de/home/downloads.html",
        "custom_install_instructions": """1. Go to https://www.adom.de/home/downloads.html
2. Download the Linux version (e.g., ADOM_Linux_amd64_...).
3. Create a directory (e.g., ~/games/adom) and cd into it.
4. Extract: tar -xzvf /path/to/downloaded/adom_linux_amd64_....tar.gz
5. cd adom_VERSION_linux_amd64/
6. Run with: ./adom""",
        "notes": "Free version available. Enhanced version on Steam."
    },
    "te4": {
        "display_name": "Tales of Maj'Eyal (T-Engine 4)", "year_created": 2009,
        "package_name": None, "executable": "./t-engine",
        "description": "A modern, feature-rich roguelike with a graphical interface, unlockable classes, and an extensive world.",
        "install_type": "custom", "source_url": "https://te4.org/download",
        "custom_install_instructions": """1. Go to https://te4.org/download
2. Download the Linux T-Engine4 client (t-engine4-linux64-....zip).
3. Create a directory (e.g., ~/games/tome4) and cd into it.
4. Extract: unzip /path/to/downloaded/t-engine4-linux64-....zip
5. Run with: ./t-engine""",
        "notes": "The engine (t-engine) runs the game module (tome)."
    }
}

def log_message(message):
    """Log messages to the log file with timestamp."""
    try:
        with open(LOG_FILE, "a") as log_file:
            log_file.write(f"{datetime.now()}: {message}\n")
    except Exception as e:
        print(f"Error writing to log file {LOG_FILE}: {e}", file=sys.stderr)

def check_package_installed(package_name, suppress_logging=False):
    """Check if a package is already installed."""
    try:
        result = subprocess.run(['dpkg', '-l', package_name],
                                capture_output=True, text=True, check=False)
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) > 1 and parts[0] == 'ii' and parts[1] == package_name:
                    return True
        return False
    except FileNotFoundError:
        if not suppress_logging:
            log_message("dpkg command not found. Cannot check package status.")
        return False
    except Exception as e:
        if not suppress_logging:
            log_message(f"Error checking package {package_name}: {e}")
        return False

def display_menu(stdscr, game_definitions):
    """Display the interactive menu for game selection."""
    curses.curs_set(0)
    curses.start_color()
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal
    curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # Error
    curses.init_pair(4, curses.COLOR_YELLOW, curses.COLOR_BLACK) # Custom install type
    curses.init_pair(5, curses.COLOR_CYAN, curses.COLOR_BLACK)   # Apt install type
    curses.init_pair(6, curses.COLOR_GREEN, curses.COLOR_BLACK)  # Installed

    game_keys = sorted(list(game_definitions.keys()))
    if not game_keys:
        stdscr.addstr(0, 0, "No games loaded. Check ROGUELIKES dictionary.")
        stdscr.refresh()
        time.sleep(2)
        return None, None

    # --- Caching APT package statuses ---
    apt_package_status_cache = {}
    log_message("Building APT package status cache...")
    initial_cache_build_start_time = time.time()
    for key_cache, data_cache in game_definitions.items():
        pkg_name_cache = data_cache.get('package_name')
        if data_cache.get('install_type') == 'apt' and pkg_name_cache:
            if pkg_name_cache not in apt_package_status_cache: # Avoid re-checking if multiple entries used same pkg_name
                apt_package_status_cache[pkg_name_cache] = check_package_installed(pkg_name_cache, suppress_logging=True)
    cache_build_duration = time.time() - initial_cache_build_start_time
    log_message(f"APT package status cache built in {cache_build_duration:.2f}s. Statuses: {apt_package_status_cache}")
    # --- End Caching ---

    checked_games = {key: False for key in game_keys}
    select_all_games = False
    highlighted_linear_idx = 0

    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            footer_height_needed = 10 
            if height < footer_height_needed + 3 or width < 50: 
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(0, 0, "Terminal too small. Please resize.")
                stdscr.addstr(1, 0, "Press Q to quit or resize window.")
                stdscr.attroff(curses.color_pair(3))
                stdscr.refresh()
                key = stdscr.getch()
                if key == ord('q') or key == ord('Q'):
                    return None, None
                elif key == curses.KEY_RESIZE:
                    continue 
                continue

            max_display_name_len = max(len(f"{game_definitions[key].get('display_name', key)} ({game_definitions[key].get('year_created', 'N/A')})") for key in game_keys) if game_keys else 0
            option_width_on_screen = max_display_name_len + 8  
            num_display_columns = max(1, width // option_width_on_screen)
            num_display_rows = height - footer_height_needed

            if num_display_rows < 1: 
                num_display_rows = 1

            highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(game_keys) - 1))

            current_grid_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0
            current_grid_row = highlighted_linear_idx % num_display_rows if num_display_rows > 0 else 0

            for idx, game_key in enumerate(game_keys):
                display_col_for_item = idx // num_display_rows
                display_row_for_item = idx % num_display_rows

                if display_row_for_item >= num_display_rows:
                    continue

                screen_x = display_col_for_item * option_width_on_screen
                screen_y = display_row_for_item

                if screen_x + option_width_on_screen > width:
                    continue

                game_data = game_definitions[game_key]
                checkbox = "[X]" if checked_games[game_key] else "[ ]"

                is_installed = False
                pkg_name_list = game_data.get('package_name')
                if game_data.get('install_type') == 'apt' and pkg_name_list:
                    is_installed = apt_package_status_cache.get(pkg_name_list, False) # Use cache

                installed_marker = " ✓" if is_installed else ""
                list_entry_text = f"{checkbox} {game_data.get('display_name', game_key)} ({game_data.get('year_created', 'N/A')}){installed_marker}"

                max_len_in_col = option_width_on_screen - 2 
                list_entry_text = list_entry_text[:max_len_in_col]

                if is_installed:
                    color_pair_idx = 6
                elif game_data.get('install_type', 'unknown') == 'custom':
                    color_pair_idx = 4
                elif game_data.get('install_type', 'unknown') == 'apt':
                    color_pair_idx = 5
                else:
                    color_pair_idx = 2

                if idx == highlighted_linear_idx:
                    stdscr.attron(curses.color_pair(1))
                    stdscr.addstr(screen_y, screen_x, list_entry_text.ljust(max_len_in_col))
                    stdscr.attroff(curses.color_pair(1))
                else:
                    stdscr.attron(curses.color_pair(color_pair_idx))
                    stdscr.addstr(screen_y, screen_x, list_entry_text.ljust(max_len_in_col))
                    stdscr.attroff(curses.color_pair(color_pair_idx))

            footer_y_start = num_display_rows
            instructions = [
                "Nav: Arrows, PgUp/PgDn, Home/End",
                "Act: Space=toggle, Ctrl+A=all/none, P=process, Q=quit",
                "Color: Cyan=apt, Yellow=custom, Green=installed"
            ]

            for i, instruction in enumerate(instructions):
                if footer_y_start + i < height:
                    stdscr.addstr(footer_y_start + i, 0, instruction[:width-1], curses.A_BOLD)

            description_area_y_start = footer_y_start + len(instructions) + 1
            if game_keys and 0 <= highlighted_linear_idx < len(game_keys):
                current_game_key = game_keys[highlighted_linear_idx]
                current_game_data = game_definitions[current_game_key]

                display_name = current_game_data.get('display_name', current_game_key)
                year = current_game_data.get('year_created', 'N/A')
                pkg = current_game_data.get('package_name', 'N/A (Custom)')
                exe = current_game_data.get('executable', 'N/A')
                desc_text = current_game_data.get('description', "No description.")
                src_url = current_game_data.get('source_url', 'N/A')
                notes_text = current_game_data.get('notes', '')
                install_type = current_game_data.get('install_type', 'N/A').upper()
                
                is_pkg_installed_detail = False
                pkg_name_detail = current_game_data.get('package_name')
                if current_game_data.get('install_type') == 'apt' and pkg_name_detail:
                    is_pkg_installed_detail = apt_package_status_cache.get(pkg_name_detail, False) # Use cache
                installed_status_detail = " (INSTALLED)" if is_pkg_installed_detail else ""


                details_header = f"Details: {display_name} ({year}) - Type: {install_type}{installed_status_detail}"
                details = [
                    details_header,
                ]
                if current_game_data.get('install_type') == 'apt':
                    details.append(f"Package: {pkg}")
                else: # For custom, show source URL more prominently
                    details.append(f"Source: {src_url}")
                
                details.extend([
                    f"Execute: {exe}",
                    f"Description: {desc_text}"
                ])


                if notes_text:
                    details.append(f"Notes: {notes_text}")

                current_y_detail = description_area_y_start
                for detail_line in details:
                    max_detail_width = width -1
                    start = 0
                    while start < len(detail_line):
                        if current_y_detail < height -1: 
                            line_part = detail_line[start : start + max_detail_width]
                            stdscr.addstr(current_y_detail, 0, line_part)
                            current_y_detail += 1
                            start += max_detail_width
                        else:
                            break
                    if current_y_detail >= height -1 and start < len(detail_line):
                        if current_y_detail -1 >= description_area_y_start : 
                             stdscr.addstr(current_y_detail -1, max_detail_width - 3, "...")
                        break
            stdscr.refresh()

            key = stdscr.getch()
            num_games = len(game_keys)
            if not num_games: continue

            if key == curses.KEY_UP:
                new_row_in_col = current_grid_row - 1
                if new_row_in_col >= 0:
                    highlighted_linear_idx = current_grid_col * num_display_rows + new_row_in_col
                elif current_grid_col > 0: 
                    highlighted_linear_idx = (current_grid_col - 1) * num_display_rows + (num_display_rows - 1)
                    highlighted_linear_idx = min(highlighted_linear_idx, num_games - 1) 
            elif key == curses.KEY_DOWN:
                new_row_in_col = current_grid_row + 1
                potential_new_idx = current_grid_col * num_display_rows + new_row_in_col
                if new_row_in_col < num_display_rows and potential_new_idx < num_games:
                    highlighted_linear_idx = potential_new_idx
                elif (current_grid_col + 1) * num_display_rows < num_games: 
                     highlighted_linear_idx = (current_grid_col + 1) * num_display_rows
            elif key == curses.KEY_LEFT:
                if current_grid_col > 0:
                    new_col = current_grid_col - 1
                    highlighted_linear_idx = new_col * num_display_rows + current_grid_row
                    max_idx_in_new_col = min((new_col + 1) * num_display_rows -1, num_games -1)
                    highlighted_linear_idx = min(highlighted_linear_idx, max_idx_in_new_col)
            elif key == curses.KEY_RIGHT:
                if (current_grid_col + 1) * num_display_rows < num_games:
                    new_col = current_grid_col + 1
                    highlighted_linear_idx = new_col * num_display_rows + current_grid_row
                    highlighted_linear_idx = min(highlighted_linear_idx, num_games - 1)
            elif key == curses.KEY_PPAGE:
                highlighted_linear_idx = max(0, highlighted_linear_idx - num_display_rows)
            elif key == curses.KEY_NPAGE:
                highlighted_linear_idx = min(num_games - 1, highlighted_linear_idx + num_display_rows)
            elif key == curses.KEY_HOME:
                highlighted_linear_idx = 0
            elif key == curses.KEY_END:
                highlighted_linear_idx = num_games - 1
            elif key == ord(" "):
                if num_games > 0 and 0 <= highlighted_linear_idx < num_games:
                    game_to_toggle = game_keys[highlighted_linear_idx]
                    checked_games[game_to_toggle] = not checked_games[game_to_toggle]
            elif key == 1:  # Ctrl+A
                select_all_games = not select_all_games
                for gk_iter in game_keys:
                    checked_games[gk_iter] = select_all_games
            elif key == ord("p") or key == ord("P"):
                selected_apt_games = [gk_sel for gk_sel, is_checked in checked_games.items()
                                      if is_checked and game_definitions[gk_sel].get("install_type") == "apt"]
                selected_custom_games = [gk_sel for gk_sel, is_checked in checked_games.items()
                                         if is_checked and game_definitions[gk_sel].get("install_type") == "custom"]
                return selected_apt_games, selected_custom_games
            elif key == ord("q") or key == ord("Q"):
                return None, None
            elif key == curses.KEY_RESIZE:
                highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(game_keys) - 1 if game_keys else 0))

            if num_games > 0: 
                 highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_games - 1))

        except curses.error as e:
            log_message(f"Curses error in display_menu: {e}")
            time.sleep(0.05) # Shorter pause for minor errors
            pass
        except Exception as e:
            log_message(f"Unexpected error in display_menu: {e}")
            curses.endwin()
            print(f"An unexpected error occurred in display_menu: {e}. Check log at {LOG_FILE}")
            sys.exit(1)


# ... (rest of the script: process_selected_games, signal_handler, main, if __name__ == "__main__":)
# The following functions remain unchanged from the previous version I provided.
# Make sure to integrate the above display_menu and check_package_installed 
# into your full script.

def process_selected_games(games_to_install_keys, custom_install_game_keys, game_definitions):
    """Process selected games: install apt packages and show custom instructions."""
    if not games_to_install_keys and not custom_install_game_keys:
        print("No games selected for processing.")
        return

    if games_to_install_keys:
        print("-" * 60)
        print(f"Preparing to install {len(games_to_install_keys)} game(s) via apt...")
        print("-" * 60)

        packages_to_install = []
        already_installed_display = [] # For display purposes
        not_found_for_install = []

        # Re-check status before install, as cache might be stale if script runs for a very long time
        # or if external changes happened. For this UI, cache is likely fine.
        # For robustness, one could optionally re-verify here.
        current_apt_statuses = {}
        log_message("Verifying APT package statuses before installation attempt...")
        for game_key in games_to_install_keys:
            game_data = game_definitions[game_key]
            package_name = game_data.get('package_name')
            if package_name and package_name not in current_apt_statuses:
                 current_apt_statuses[package_name] = check_package_installed(package_name)


        for game_key in games_to_install_keys:
            game_data = game_definitions[game_key]
            package_name = game_data.get('package_name')
            display_name = game_data.get('display_name', game_key)

            if package_name:
                if current_apt_statuses.get(package_name, False): # Use freshly checked status
                    already_installed_display.append(f"{display_name} ({package_name})")
                else:
                    packages_to_install.append(package_name)
                    print(f"  • To install: {display_name} (package: {package_name})")
            else:
                not_found_for_install.append(display_name)


        if already_installed_display: # Changed variable name
            print(f"\nAlready installed: {', '.join(already_installed_display)}")
        if not_found_for_install:
             print(f"\nWarning: No package name defined for APT install: {', '.join(not_found_for_install)}")


        if packages_to_install:
            print(f"\nFound {len(packages_to_install)} apt packages to install.")
            install_command_str = f"sudo apt-get update && sudo apt-get install -y {' '.join(packages_to_install)}"

            print(f"Proposed command: {install_command_str}")
            
            try:
                response = input("Proceed with APT installation? (y/N): ").strip().lower()
            except EOFError: 
                print("\nNo input received for confirmation. Cancelling APT installation.")
                log_message("EOFError at APT confirmation prompt, cancelling.")
                response = 'n'
            except KeyboardInterrupt:
                print("\nAPT Installation interrupted by user at confirmation.")
                log_message("SIGINT at APT confirmation prompt, cancelling.")
                return 


            if response in ['y', 'yes']:
                try:
                    print("\nUpdating package lists (sudo apt-get update)...")
                    update_process = subprocess.run(['sudo', 'apt-get', 'update'], check=True, capture_output=True, text=True)
                    log_message(f"apt-get update stdout:\n{update_process.stdout}")
                    if update_process.stderr: log_message(f"apt-get update stderr:\n{update_process.stderr}")
                    print("Package lists updated.")

                    print(f"Installing packages: {' '.join(packages_to_install)}...")
                    install_process = subprocess.run(['sudo', 'apt-get', 'install', '-y'] + packages_to_install, check=True, capture_output=True, text=True)
                    log_message(f"apt-get install stdout:\n{install_process.stdout}")
                    if install_process.stderr: log_message(f"apt-get install stderr:\n{install_process.stderr}")

                    print("\n✓ APT installation process completed for specified packages.")
                    print("Verifying installations:")
                    for pkg_name_verify in packages_to_install: # Corrected variable name
                        if check_package_installed(pkg_name_verify): # Re-check after install
                            print(f"  ✓ {pkg_name_verify} is now installed.")
                        else:
                            print(f"  ✗ {pkg_name_verify} still not reported as installed. Check logs or run manually.")

                except subprocess.CalledProcessError as e:
                    print(f"\n✗ APT command failed (Code: {e.returncode}).")
                    print(f"  Command: {' '.join(e.cmd)}")
                    if e.stdout: print(f"  Stdout:\n{e.stdout}")
                    if e.stderr: print(f"  Stderr:\n{e.stderr}")
                    print("You may need to check your internet connection, sudo permissions, or package availability.")
                    log_message(f"APT command failed. Cmd: {e.cmd}, Code: {e.returncode}, stdout: {e.stdout}, stderr: {e.stderr}")
                except FileNotFoundError:
                    print("\n✗ Error: 'sudo' or 'apt-get' command not found. Is it in your PATH?")
                    log_message("FileNotFoundError for sudo/apt-get during installation.")
                except KeyboardInterrupt:
                    print("\n\nAPT Installation process interrupted by user.")
                    log_message("APT installation interrupted by SIGINT during command execution.")
                except Exception as e:
                    print(f"\nAn unexpected error occurred during APT installation: {e}")
                    log_message(f"Unexpected error during APT install: {e}")
            else:
                print("APT installation cancelled by user.")
                log_message("APT installation cancelled by user (chose 'N').")
        elif not already_installed_display and not not_found_for_install: 
            print("No new APT packages to install from selection.")


    if custom_install_game_keys:
        print("\n" + "=" * 60)
        print("CUSTOM INSTALLATION INSTRUCTIONS")
        print("=" * 60)

        for game_key in custom_install_game_keys:
            game_data = game_definitions[game_key]
            display_name = game_data.get('display_name', game_key)
            instructions = game_data.get('custom_install_instructions', 'No instructions available.')
            source_url = game_data.get('source_url', 'N/A')

            print(f"\n{'-' * 40}")
            print(f"GAME: {display_name}")
            print(f"SOURCE: {source_url}")
            print(f"{'-' * 40}")
            print("INSTALLATION STEPS:")
            print(instructions)
            executable = game_data.get('executable', 'N/A')
            if executable != 'N/A':
                print(f"Likely executable after install: {executable}")
            print()

    print("\n" + "=" * 60)
    print("Processing complete!")

    if games_to_install_keys: # Only print this if APT games were considered
        processed_apt_executables = False
        for game_key in games_to_install_keys:
             if game_definitions[game_key].get('package_name') and game_definitions[game_key].get('executable') != 'N/A':
                 if not processed_apt_executables:
                    print("\nAPT installed games can typically be launched by typing their executable name.")
                    print("Examples of executables for games processed via APT:")
                    processed_apt_executables = True
                 game_data = game_definitions[game_key]
                 executable = game_data.get('executable')
                 display_name = game_data.get('display_name', game_key)
                 print(f"  • {display_name}: {executable}")


def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully by cleaning up curses."""
    try:
        if 'curses' in sys.modules and curses.isendwin() is False:
            curses.nocbreak()
            curses.echo()
            curses.endwin()
            log_message("Curses mode ended by signal_handler.")
    except curses.error as e:
        log_message(f"Curses error during signal_handler cleanup: {e}")
    except Exception as e:
        log_message(f"Generic error during signal_handler cleanup: {e}")
    finally:
        print("\nProgram terminated by user (Ctrl+C).")
        log_message("Program terminated by SIGINT (Ctrl+C).")
        sys.exit(0)

def main():
    """Main function to run the roguelike installer menu."""
    script_name = os.path.basename(__file__)
    log_message(f"--- Starting {script_name} script ---")

    signal.signal(signal.SIGINT, signal_handler)

    if not ROGUELIKES:
        print("No roguelike games defined in ROGUELIKES. Exiting.")
        log_message("Error: ROGUELIKES dictionary is empty.")
        return

    selected_apt_games = None
    selected_custom_games = None
    exit_code = 0

    try:
        result = curses.wrapper(display_menu, ROGUELIKES)
        if result:
            selected_apt_games, selected_custom_games = result
    
    except curses.error as e:
        log_message(f"Critical curses error in main or unhandled by wrapper: {e}")
        if 'curses' in sys.modules and not curses.isendwin():
            try: curses.endwin()
            except Exception as e_curses: log_message(f"Failed to manually end curses: {e_curses}")
        print(f"A critical Curses error occurred: {e}. Check log at {LOG_FILE}.")
        exit_code = 1
    except KeyboardInterrupt: 
        log_message("KeyboardInterrupt caught directly in main loop (should be signal_handler).")
        print("\nProgram interrupted in main loop.")
        exit_code = 1 
    except Exception as e:
        log_message(f"An unexpected non-curses error occurred in main: {e}")
        if 'curses' in sys.modules and not curses.isendwin():
             try: curses.endwin()
             except Exception as e_curses: log_message(f"Failed to manually end curses on non-curses error: {e_curses}")
        print(f"An unexpected error occurred: {e}. Check log at {LOG_FILE}.")
        exit_code = 1
    finally:
        if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
             try:
                curses.endwin()
                log_message("Curses explicitly ended in main's finally block.")
             except Exception as e_final_curses:
                log_message(f"Error in final curses.endwin() in main: {e_final_curses}")


    if exit_code == 0:
        if selected_apt_games is None and selected_custom_games is None:
            print("No games selected or menu was quit. Exiting.")
            log_message("User quit the menu or no selections made (result was None, None).")
        elif not selected_apt_games and not selected_custom_games: # Both lists are empty
            print("No games were checked for processing.")
            log_message("User proceeded from menu, but no games were checked.")
        else: # At least one list has items
            log_message(f"Proceeding to process selections. APT games: {selected_apt_games}, Custom games: {selected_custom_games}")
            process_selected_games(selected_apt_games or [], selected_custom_games or [], ROGUELIKES) # Pass empty list if None
    else:
        log_message(f"Skipping processing due to earlier error (exit_code: {exit_code}).")


    log_message(f"--- Script {script_name} finished (Exit Code: {exit_code}) ---")
    if exit_code != 0:
        sys.exit(exit_code)

if __name__ == "__main__":
    if not sys.stdout.isatty():
        print("Error: This script uses curses and must be run in a terminal.", file=sys.stderr)
        log_message("Script aborted: Not running in a TTY.")
        sys.exit(1)

    try:
        with open(LOG_FILE, "a") as f: 
            f.write(f"{datetime.now()}: === {os.path.basename(__file__)} session started ===\n")
    except IOError as e:
        print(f"Warning: Could not write to log file {LOG_FILE}: {e}", file=sys.stderr)

    main()
