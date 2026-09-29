#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
"""Brian's Brain Cellular Automaton (Terminal / Curses).

Brian Silverman's 1989 cellular automaton simulating neural wave excitation.
Cells cycle through 3 states:
  - READY (OFF): Becomes FIRING if it has exactly 2 FIRING neighbors.
  - FIRING (ON): Automatically transitions to REFRACTORY.
  - REFRACTORY (DYING): Automatically recovers to READY.

Features interactive editing, presets, neural spark injection, visual color modes,
loop/oscillator detection, and persistent state management in ~/.automata-game-of-life/.
"""

import argparse
from collections import deque
import curses
import datetime
import json
import os
import random
import sys

SAVE_DIR = os.path.expanduser("~/.automata-game-of-life")

# Cell States
OFF = 0
FIRING = 1
REFRACTORY = 2

# Presets: list of (dy, dx, state)
PATTERNS = {
    1: ("Glider (Spaceship)", [
        (0, 1, FIRING), (0, 2, FIRING),
        (1, 0, FIRING), (1, 3, REFRACTORY),
        (2, 1, REFRACTORY), (2, 2, REFRACTORY)
    ]),
    2: ("Blinker Oscillator", [
        (0, 1, FIRING), (0, 2, FIRING),
        (1, 0, REFRACTORY), (1, 3, REFRACTORY),
        (2, 1, FIRING), (2, 2, FIRING)
    ]),
    3: ("Star Oscillator", [
        (-1, 0, FIRING), (1, 0, FIRING),
        (0, -1, FIRING), (0, 1, FIRING),
        (-1, -1, REFRACTORY), (1, 1, REFRACTORY),
        (-1, 1, REFRACTORY), (1, -1, REFRACTORY)
    ]),
    4: ("Brain Wave / Spiral", [
        (0, 1, FIRING), (1, 2, FIRING), (2, 0, FIRING), (2, 1, FIRING),
        (0, 2, REFRACTORY), (1, 3, REFRACTORY), (3, 1, REFRACTORY)
    ]),
    5: ("Dual Gliders", [
        (-2, 0, FIRING), (-2, 1, FIRING), (-1, -1, FIRING), (-1, 2, REFRACTORY), (0, 0, REFRACTORY), (0, 1, REFRACTORY),
        (2, 0, FIRING), (2, 1, FIRING), (3, -1, FIRING), (3, 2, REFRACTORY), (4, 0, REFRACTORY), (4, 1, REFRACTORY)
    ]),
}

COLOR_MODES = ["neon", "classic", "amber", "mono"]


def save_state(grid, prefix="brain"):
    """Saves the current active cells to a timestamped JSON file in ~/.automata-game-of-life/."""
    os.makedirs(SAVE_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = os.path.join(SAVE_DIR, f"{prefix}-{timestamp}.sav")
    # Save only non-OFF cells as "y,x": state
    payload = {f"{k[0]},{k[1]}": v for k, v in grid.items() if v in (FIRING, REFRACTORY)}
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    return filename


def load_state(filename):
    """Loads brain state from a JSON file (searches current dir and ~/.automata-game-of-life/)."""
    target = filename
    if not os.path.exists(target):
        candidate = os.path.join(SAVE_DIR, os.path.basename(filename))
        if os.path.exists(candidate):
            target = candidate
    with open(target, "r", encoding="utf-8") as f:
        data = json.load(f)
    result = {}
    for k, v in data.items():
        coords = tuple(map(int, k.split(',')))
        if v in (FIRING, "ON", 1):
            result[coords] = FIRING
        elif v in (REFRACTORY, "RECRUITING", 2):
            result[coords] = REFRACTORY
    return result


def get_neighbors(y, x, height, width):
    """Returns 8-connected toroidal neighbor coordinates."""
    return [
        ((y + dy) % height, (x + dx) % width)
        for dy in (-1, 0, 1)
        for dx in (-1, 0, 1)
        if (dy, dx) != (0, 0)
    ]


def step(grid, height, width):
    """Computes next generation of Brian's Brain with sparse dict pruning."""
    new_grid = {}
    neighbor_counts = {}

    # State transitions for currently active cells
    for (y, x), state in grid.items():
        if state == FIRING:
            new_grid[(y, x)] = REFRACTORY
            for ny, nx in get_neighbors(y, x, height, width):
                neighbor_counts[(ny, nx)] = neighbor_counts.get((ny, nx), 0) + 1
        elif state == REFRACTORY:
            # Recovers to READY (OFF, omit from new_grid to keep dict sparse)
            pass

    # Any READY cell with exactly 2 FIRING neighbors becomes FIRING
    for (y, x), count in neighbor_counts.items():
        if count == 2 and grid.get((y, x), OFF) == OFF:
            new_grid[(y, x)] = FIRING

    return new_grid


def init_colors(enabled=True):
    """Initializes curses color pairs."""
    if not enabled or not curses.has_colors():
        return False
    try:
        curses.start_color()
        curses.use_default_colors()
        # Pair 1: Cyan (Firing in neon mode)
        curses.init_pair(1, curses.COLOR_CYAN, -1)
        # Pair 2: Magenta / Red (Refractory in neon mode)
        curses.init_pair(2, curses.COLOR_MAGENTA, -1)
        # Pair 3: Green (Classic firing)
        curses.init_pair(3, curses.COLOR_GREEN, -1)
        # Pair 4: Yellow (Classic refractory)
        curses.init_pair(4, curses.COLOR_YELLOW, -1)
        # Pair 5: White / Amber
        curses.init_pair(5, curses.COLOR_YELLOW, -1)
        curses.init_pair(6, curses.COLOR_RED, -1)
        # Pair 7: Cursor standout
        curses.init_pair(7, curses.COLOR_BLACK, curses.COLOR_WHITE)
        return True
    except curses.error:
        return False


def get_cell_style(state, mode, has_color):
    """Returns the visual character and color attribute for a cell state."""
    if not has_color or mode == "mono":
        if state == FIRING:
            return 'O', curses.A_BOLD
        elif state == REFRACTORY:
            return '.', curses.A_DIM
        return ' ', curses.A_NORMAL

    if mode == "neon":
        if state == FIRING:
            return 'O', curses.color_pair(1) | curses.A_BOLD
        elif state == REFRACTORY:
            return 'x', curses.color_pair(2) | curses.A_BOLD
    elif mode == "classic":
        if state == FIRING:
            return 'O', curses.color_pair(3) | curses.A_BOLD
        elif state == REFRACTORY:
            return '.', curses.color_pair(4)
    elif mode == "amber":
        if state == FIRING:
            return 'O', curses.color_pair(5) | curses.A_BOLD
        elif state == REFRACTORY:
            return '.', curses.color_pair(6)

    return 'O', curses.A_BOLD


def safe_addstr(stdscr, y, x, text, attr=0):
    try:
        max_y, max_x = stdscr.getmaxyx()
        if 0 <= y < max_y and 0 <= x < max_x:
            avail = max_x - x - 1
            if avail > 0:
                stdscr.addstr(y, x, text[:avail], attr)
    except curses.error:
        pass


def safe_addch(stdscr, y, x, ch, attr=0):
    try:
        max_y, max_x = stdscr.getmaxyx()
        if 0 <= y < max_y and 0 <= x < max_x - 1:
            stdscr.addch(y, x, ch, attr)
    except curses.error:
        pass


def run_brain(stdscr, args):
    curses.curs_set(0)
    has_color = init_colors(not args.no_color)

    color_mode = args.color if has_color else "mono"
    speed = max(0.01, float(args.speed))

    height, width = stdscr.getmaxyx()
    height = max(5, height - 4)

    cursor_y, cursor_x = height // 2, width // 2
    grid = {}
    running = False
    generation = 0
    status_msg = "Editing (Paused)"
    notification = ""
    history = deque(maxlen=64)

    if args.file:
        try:
            grid = load_state(args.file)
            status_msg = f"Loaded {os.path.basename(args.file)}"
        except Exception as e:
            status_msg = f"Failed to load file: {e}"

    while True:
        max_y, max_x = stdscr.getmaxyx()
        height = max(5, max_y - 4)
        width = max_x

        cursor_y %= height
        cursor_x %= width

        stdscr.erase()

        # Render active cells
        firing_count = 0
        refractory_count = 0
        for (y, x), state in grid.items():
            if y < height and x < width:
                if state == FIRING:
                    firing_count += 1
                elif state == REFRACTORY:
                    refractory_count += 1
                ch, attr = get_cell_style(state, color_mode, has_color)
                safe_addch(stdscr, y, x, ch, attr)

        # Highlight cursor when paused or editing
        if not running:
            cursor_attr = (curses.color_pair(7) | curses.A_BOLD) if has_color else curses.A_STANDOUT
            curr_state = grid.get((cursor_y, cursor_x), OFF)
            cursor_char = 'X' if curr_state == OFF else ('O' if curr_state == FIRING else '.')
            safe_addch(stdscr, cursor_y, cursor_x, cursor_char, cursor_attr)

        col_name = color_mode.upper() if has_color else "OFF"
        run_label = "RUNNING" if running else "PAUSED"

        safe_addstr(
            stdscr, height, 0,
            "SPACE: Cycle State/Pause | s: Start(Auto-save) | p: Pause | u: Neural Spark | c: Color | q: Quit",
            curses.A_DIM
        )
        safe_addstr(
            stdscr, height + 1, 0,
            "1: Glider 2: Blinker 3: Star 4: Wave/Spiral 5: Dual Gliders | r: Clear | +/-: Speed",
            curses.A_DIM
        )
        info_line = (
            f"[{run_label}] Gen: {generation} | Firing: {firing_count} | Dying: {refractory_count} | "
            f"Speed: {speed:.2f}s | Color: {col_name} | {status_msg}"
        )
        safe_addstr(stdscr, height + 2, 0, info_line, curses.A_BOLD)

        if notification:
            safe_addstr(stdscr, height + 3, 0, f">> {notification}", curses.color_pair(4 if has_color else 0))
        else:
            state_desc = "OFF" if grid.get((cursor_y, cursor_x), OFF) == OFF else ("FIRING" if grid[(cursor_y, cursor_x)] == FIRING else "REFRACTORY")
            safe_addstr(stdscr, height + 3, 0, f"Cursor: ({cursor_y}, {cursor_x}) [{state_desc}]")

        stdscr.refresh()

        timeout_ms = max(10, int(speed * 1000)) if running else 100
        stdscr.timeout(timeout_ms)

        try:
            key = stdscr.getch()
        except curses.error:
            key = -1

        if key == curses.KEY_UP:
            cursor_y = (cursor_y - 1) % height
        elif key == curses.KEY_DOWN:
            cursor_y = (cursor_y + 1) % height
        elif key == curses.KEY_LEFT:
            cursor_x = (cursor_x - 1) % width
        elif key == curses.KEY_RIGHT:
            cursor_x = (cursor_x + 1) % width
        elif key == ord(' '):
            if running:
                running = False
                status_msg = "Paused"
                notification = ""
            else:
                pos = (cursor_y, cursor_x)
                curr = grid.get(pos, OFF)
                # Cycle: OFF -> FIRING -> REFRACTORY -> OFF
                if curr == OFF:
                    grid[pos] = FIRING
                elif curr == FIRING:
                    grid[pos] = REFRACTORY
                else:
                    grid.pop(pos, None)
                notification = ""
        elif key in map(ord, "12345"):
            pattern_name, pattern_cells = PATTERNS[int(chr(key))]
            for dy, dx, state in pattern_cells:
                ny = (cursor_y + dy) % height
                nx = (cursor_x + dx) % width
                grid[(ny, nx)] = state
            notification = f"Stamped {pattern_name} at ({cursor_y}, {cursor_x})"
        elif key == ord('u'):  # Inject random neural spark cluster
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    if random.random() < 0.25:
                        ny = (cursor_y + dy) % height
                        nx = (cursor_x + dx) % width
                        grid[(ny, nx)] = FIRING if random.random() < 0.7 else REFRACTORY
            notification = f"Injected random neural spark cluster around ({cursor_y}, {cursor_x})"
        elif key == ord('s'):
            if not running:
                saved_file = save_state(grid)
                notification = f"Saved initial state to {saved_file}"
                running = True
                status_msg = "Running"
        elif key == ord('p'):
            running = not running
            status_msg = "Running" if running else "Paused"
            if not running:
                notification = ""
        elif key == ord('c') and has_color:
            cur_idx = COLOR_MODES.index(color_mode)
            color_mode = COLOR_MODES[(cur_idx + 1) % len(COLOR_MODES)]
            notification = f"Color mode switched to: {color_mode.upper()}"
        elif key == ord('+') or key == ord('='):
            speed = max(0.01, speed - 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key == ord('-') or key == ord('_'):
            speed = min(1.0, speed + 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key == ord('w'):
            saved_file = save_state(grid, prefix="manual-brain")
            notification = f"Manual save written to {saved_file}"
        elif key == ord('r'):
            grid.clear()
            history.clear()
            generation = 0
            running = False
            status_msg = "Grid cleared"
            notification = ""
        elif key in (ord('q'), 27):
            break

        if running:
            # Snapshot for loop detection: frozenset of ((y,x), state)
            state_frozen = frozenset(grid.items())
            history.append(state_frozen)

            new_grid = step(grid, height, width)
            generation += 1

            if not new_grid:
                status_msg = f"Neural activity ceased at Gen {generation}"
                running = False
            else:
                next_frozen = frozenset(new_grid.items())
                found_period = None
                for idx, prev_frozen in enumerate(reversed(history)):
                    if next_frozen == prev_frozen:
                        found_period = idx + 1
                        break

                if found_period == 1:
                    status_msg = f"Static pattern at Gen {generation}"
                elif found_period is not None:
                    status_msg = f"Oscillator (period {found_period}) at Gen {generation}"
                else:
                    status_msg = "Active neural waves"

            grid = new_grid


def parse_args():
    parser = argparse.ArgumentParser(
        description="Brian's Brain Cellular Automaton in terminal curses.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Rules:
  Cells have 3 states: READY (OFF), FIRING (ON), and REFRACTORY (DYING).
  - READY cell becomes FIRING if it has exactly 2 FIRING neighbors.
  - FIRING cell always becomes REFRACTORY in the next generation.
  - REFRACTORY cell always recovers to READY in the next generation.

Controls:
  Arrow Keys      Move cursor
  SPACE           Cycle cell state (OFF -> FIRING -> REFRACTORY) or pause simulation
  s               Start simulation (automatically saves initial state to brain-*.sav)
  p               Toggle Pause / Resume
  u               Inject random neural spark cluster around cursor
  c               Cycle color modes: NEON -> CLASSIC -> AMBER -> MONO
  + / -           Speed up / slow down simulation
  1-5             Stamp preset pattern at cursor:
                    1: Glider (Spaceship)   2: Blinker Oscillator
                    3: Star Oscillator      4: Brain Wave / Spiral
                    5: Dual Gliders
  w               Manually save current state to ~/.automata-game-of-life/
  r               Clear board / reset
  q / ESC         Quit

State Files:
  - Initial states are saved automatically to ~/.automata-game-of-life/brain-YYYYMMDD-HHMMSS.sav
  - Resume any saved state:
      python game-of-brians-brain.py brain-20260919-120000.sav
"""
    )
    parser.add_argument("file", nargs="?", help="Optional path to a saved state JSON (.sav) to load")
    parser.add_argument(
        "-c", "--color",
        choices=COLOR_MODES,
        default="neon",
        help="Initial color mode (default: neon). Choices: neon, classic, amber, mono."
    )
    parser.add_argument(
        "-s", "--speed",
        type=float,
        default=0.08,
        help="Initial step delay in seconds per generation (default: 0.08)"
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI colors and run in standard monochrome"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    curses.wrapper(lambda stdscr: run_brain(stdscr, args))


if __name__ == "__main__":
    main()