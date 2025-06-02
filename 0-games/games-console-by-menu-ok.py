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
CACHE_DIR = os.path.expanduser("~/.cache/games_console_by_menu") # User-specific cache directory
CACHE_FILE = os.path.join(CACHE_DIR, "statuses.json")

PACKAGE_STATUS_INSTALLED = "INSTALLED"
PACKAGE_STATUS_AVAILABLE = "AVAILABLE"
PACKAGE_STATUS_NOT_AVAILABLE = "NOT_AVAILABLE"
PACKAGE_STATUS_CHECK_ERROR = "ERROR_CHECKING"

HEADER_PREFIX = "### "

AVAILABLE_GAMES = {
    "### ACTION & ARCADE (Text)": "Fast-paced, reflex-based, and classic arcade-style games for the terminal.",
    "asciijump": "A small and funny ASCII-art ski jumping game. (~<1MB)",
    "bastet": "Ncurses Tetris clone with a nasty block selection algorithm. (~<1MB)",
    "bombardier": "A bomber-style arcade game for the console. (~<1MB)",
    "greed": "A curses-based Tron-like game where you eat numbers. (~<1MB)",
    "moon-buggy": "Drive a car over the moon's surface in this classic text-mode game. (~<1MB)",
    "ninvaders": "A Space Invaders clone for the Ncurses terminal. (~<1MB)",
    "pacman4console": "A PacMan clone for the console. (~<1MB)",
    "robots": "Fight off evil robots in this classic terminal game (often in bsdgames). (~<1MB)",
    "snake4": "A console-based snake game. (~<1MB)",
    "tint": "A Tetris-like ncurses game with color and scoring. (~<1MB)",

    "### STRATEGY & TACTICS (Text)": "Text-based games involving planning, foresight, and resource management.",
    "dopewars": "Text-based drug dealing simulation and strategy game. Part of Debian's games-strategy selection. (~<1MB)",
    "empire": "The classic turn-based strategy wargame for terminals. (~<1MB)",
    "gbatnav": "Ncurses-based Battleship game. Part of Debian's games-strategy selection. (~<1MB)",
    "ogamesim": "Console-based combat simulator for the OGame online strategy game. Part of Debian's games-strategy selection. (~<1MB)",
    "singularity": "Text-based AI / world domination simulation game. Part of Debian's games-strategy selection. (~<1MB)",
    "vms-empire": "VMS-empire, a classic strategy game for text terminals (distinct from GNU Empire). (~<1MB)",
    "zec": "Zillions of Enemy Creatures - a text-based abstract strategy game. Part of Debian's games-strategy selection. (~<1MB)",

    "### PUZZLE & LOGIC (Text)": "Text-based brain teasers, logic challenges, and matching games.",
    "nettoe": "Networked Tic-Tac-Toe game for the console. Part of Debian's finest games selection. (~<1MB)",

    "### BOARD & CARD (Text)": "Digital versions of classic board and card games for the terminal.",
    "gnugo": "The GNU Go program, a text-based Go player and analyzer. (~5MB)",

    "### ROGUELIKES ETC (Text)": "Dungeon crawls, interactive fiction, and terminal adventures.",
    "adom-gb": "Ancient Domains Of Mystery - Classic Edition (check availability). (~10MB)",
    "angband": "A single-player dungeon exploration roguelike game (console). (~5MB)",
    "brogue": "Brogue - a highly acclaimed, visually distinct roguelike (check 'brogue-ce'). (~1MB)",
    "bsdgames": "A collection of classic text-based UNIX games (adventure, rogue, worms, etc.). (~1MB)",
    "cataclysm-dda-curses": "Cataclysm: Dark Days Ahead - post-apocalyptic survival roguelike (ncurses). (~50MB)",
    "crawl": "Dungeon Crawl Stone Soup - a popular and deep roguelike (console). (~15MB)",
    "doomrl": "Doom, the Roguelike - a fast-paced, turn-based roguelike based on Doom. (~5MB)",
    "frotz": "An interpreter for Infocom and other Z-machine interactive fiction games. (~<1MB)",
    "gearhead": "A mecha roguelike with a complex storyline and procedural generation. (~5MB)",
    "gearhead2": "Successor to GearHead, continuing the mecha roguelike themes. (~10MB)",
    "glulxe": "An interpreter for Glulx interactive fiction games. (~<1MB)",
    "larn": "A classic, notoriously difficult roguelike game (try 'xlarn' for X11 version). (~<1MB)",
    "nethack-console": "The classic dungeon exploration roguelike game (console version). (~2MB)",
    "nethereye": "A 'crawler' type game with a curses interface, focusing on exploration. (~<1MB)",
    "omega-rpg": "A complex text-based roguelike with a vast overworld and many features. (~1MB)",
    "slashem": "A variant of NetHack with many more features, monsters, and items. (~5MB)",
    "tomenet": "Tales of Middle Earth (ToME) - a multiplayer roguelike game. (~20MB)",
    "unangband": "A variant of the popular roguelike game Angband. (~5MB)",
    "zangband": "A variant of the roguelike game Angband. (~5MB)",

    "### SIMULATION (Text)": "Text-based games that simulate real-world or fictional systems.",

    "### MISCELLANEOUS (Text)": "Fun terminal utilities, old classics, or unique small text-based games.",
    "sl": "A classic console animation - a steam locomotive runs across your screen. (~<1MB)",
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
