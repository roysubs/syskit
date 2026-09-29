#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
"""Conway's Game of Life in Python Curses.

Supports interactive editing, preset patterns, multiple visual color modes,
automatic saving of initial states, loop/oscillator detection, and speed control.
"""

import argparse
from collections import deque
import curses
import datetime
import json
import os
import sys

# Define common Game of Life patterns
# Offsets are relative (dy, dx) from cursor position
PULSAR_OFFSETS = [
    (0, 2), (0, 3), (0, 4), (0, 8), (0, 9), (0, 10),
    (2, 0), (2, 5), (2, 7), (2, 12),
    (3, 0), (3, 5), (3, 7), (3, 12),
    (4, 0), (4, 5), (4, 7), (4, 12),
    (5, 2), (5, 3), (5, 4), (5, 8), (5, 9), (5, 10),
    (7, 2), (7, 3), (7, 4), (7, 8), (7, 9), (7, 10),
    (8, 0), (8, 5), (8, 7), (8, 12),
    (9, 0), (9, 5), (9, 7), (9, 12),
    (10, 0), (10, 5), (10, 7), (10, 12),
    (12, 2), (12, 3), (12, 4), (12, 8), (12, 9), (12, 10),
]

PATTERNS = {
    1: ("Block", [(0, 0), (0, 1), (1, 0), (1, 1)]),
    2: ("Blinker", [(0, -1), (0, 0), (0, 1)]),
    3: ("Toad", [(0, 0), (0, 1), (0, 2), (1, -1), (1, 0), (1, 1)]),
    4: ("Glider", [(0, 1), (1, 2), (2, 0), (2, 1), (2, 2)]),
    5: ("LWSS", [(0, 1), (0, 4), (1, 0), (2, 0), (2, 4), (3, 0), (3, 1), (3, 2), (3, 3)]),
    6: ("MWSS", [(0, 1), (0, 5), (1, 0), (2, 0), (2, 5), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4)]),
    7: ("HWSS", [(0, 1), (0, 6), (1, 0), (2, 0), (2, 6), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (3, 5)]),
    8: ("Pulsar", PULSAR_OFFSETS),
    9: ("Pentadecathlon", [(0, 1), (1, 0), (1, 2), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 0), (8, 2), (9, 1)]),
    0: ("Gosper Glider Gun", [
        (0, 24), (1, 22), (1, 24), (2, 12), (2, 13), (2, 20), (2, 21), (2, 34), (2, 35),
        (3, 11), (3, 15), (3, 20), (3, 21), (3, 34), (3, 35), (4, 0), (4, 1), (4, 10),
        (4, 16), (4, 20), (4, 21), (5, 0), (5, 1), (5, 10), (5, 14), (5, 16), (5, 17),
        (5, 22), (5, 24), (6, 10), (6, 16), (6, 24), (7, 11), (7, 15), (8, 12), (8, 13)
    ]),
}

COLOR_MODES = ["age", "neighbors", "rainbow", "mono"]


SAVE_DIR = os.path.expanduser("~/.automata-game-of-life")


def save_state(grid, prefix="life"):
    """Saves the current live cell coordinates to a timestamped JSON file in ~/.automata-game-of-life/."""
    os.makedirs(SAVE_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = os.path.join(SAVE_DIR, f"{prefix}-{timestamp}.sav")
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(list(grid), f)
    return filename


def load_state(filename):
    """Loads live cell coordinates from a JSON file (searches current directory and ~/.automata-game-of-life/)."""
    target = filename
    if not os.path.exists(target):
        candidate = os.path.join(SAVE_DIR, os.path.basename(filename))
        if os.path.exists(candidate):
            target = candidate
    with open(target, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {tuple(coord) for coord in data}


def get_neighbors(y, x, height, width):
    """Returns 8-connected toroidal neighbor coordinates."""
    return [
        ((y + dy) % height, (x + dx) % width)
        for dy in (-1, 0, 1)
        for dx in (-1, 0, 1)
        if (dy, dx) != (0, 0)
    ]


def step(grid, cell_ages, height, width):
    """Computes the next generation using Conway's B3/S23 rules on a torus."""
    new_grid = set()
    new_ages = {}
    neighbor_counts = {}

    for y, x in grid:
        for ny, nx in get_neighbors(y, x, height, width):
            neighbor_counts[(ny, nx)] = neighbor_counts.get((ny, nx), 0) + 1

    for (y, x), count in neighbor_counts.items():
        if count == 3 or (count == 2 and (y, x) in grid):
            new_grid.add((y, x))
            new_ages[(y, x)] = cell_ages.get((y, x), 0) + 1

    return new_grid, new_ages, neighbor_counts


def init_colors(enabled=True):
    """Initializes terminal colors and color pairs."""
    if not enabled or not curses.has_colors():
        return False
    try:
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_GREEN, -1)
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_RED, -1)
        curses.init_pair(5, curses.COLOR_BLUE, -1)
        curses.init_pair(6, curses.COLOR_MAGENTA, -1)
        curses.init_pair(7, curses.COLOR_BLACK, curses.COLOR_WHITE)
        return True
    except curses.error:
        return False


def get_cell_style(y, x, age, neighbors, mode, gen, has_color):
    """Returns the visual attribute/color for a live cell."""
    if not has_color or mode == "mono":
        return curses.color_pair(1) | curses.A_BOLD if has_color else curses.A_NORMAL

    if mode == "age":
        if age <= 1:
            return curses.color_pair(2) | curses.A_BOLD
        elif age <= 4:
            return curses.color_pair(1)
        elif age <= 12:
            return curses.color_pair(3) | curses.A_BOLD
        elif age <= 25:
            return curses.color_pair(6) | curses.A_BOLD
        else:
            return curses.color_pair(4) | curses.A_BOLD

    elif mode == "neighbors":
        if neighbors == 2:
            return curses.color_pair(2) | curses.A_BOLD
        elif neighbors == 3:
            return curses.color_pair(3) | curses.A_BOLD
        else:
            return curses.color_pair(1)

    elif mode == "rainbow":
        palette = [
            curses.color_pair(4) | curses.A_BOLD,
            curses.color_pair(3) | curses.A_BOLD,
            curses.color_pair(1) | curses.A_BOLD,
            curses.color_pair(2) | curses.A_BOLD,
            curses.color_pair(5) | curses.A_BOLD,
            curses.color_pair(6) | curses.A_BOLD,
        ]
        return palette[(y + x + gen) % len(palette)]

    return curses.color_pair(1)


def safe_addstr(stdscr, y, x, text, attr=0):
    """Safely renders a string without exceeding terminal boundaries."""
    try:
        max_y, max_x = stdscr.getmaxyx()
        if 0 <= y < max_y and 0 <= x < max_x:
            avail = max_x - x - 1
            if avail > 0:
                stdscr.addstr(y, x, text[:avail], attr)
    except curses.error:
        pass


def safe_addch(stdscr, y, x, ch, attr=0):
    """Safely renders a single character without throwing curses errors."""
    try:
        max_y, max_x = stdscr.getmaxyx()
        if 0 <= y < max_y and 0 <= x < max_x - 1:
            stdscr.addch(y, x, ch, attr)
    except curses.error:
        pass


def run_game(stdscr, args):
    curses.curs_set(0)
    has_color = init_colors(not args.no_color)

    color_mode = args.color if has_color else "mono"
    speed = max(0.01, float(args.speed))

    height, width = stdscr.getmaxyx()
    height = max(5, height - 4)

    cursor_y, cursor_x = height // 2, width // 2
    grid = set()
    cell_ages = {}
    neighbor_counts = {}
    running = False
    generation = 0
    status_msg = "Editing (Paused)"
    notification = ""
    history = deque(maxlen=64)

    if args.file:
        try:
            grid = load_state(args.file)
            cell_ages = {cell: 1 for cell in grid}
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
        for y, x in grid:
            if y < height and x < width:
                age = cell_ages.get((y, x), 1)
                nc = neighbor_counts.get((y, x), 0)
                attr = get_cell_style(y, x, age, nc, color_mode, generation, has_color)
                safe_addch(stdscr, y, x, 'o', attr)

        if not running:
            cursor_attr = (curses.color_pair(7) | curses.A_BOLD) if has_color else curses.A_STANDOUT
            safe_addch(stdscr, cursor_y, cursor_x, 'X', cursor_attr)

        col_name = color_mode.upper() if has_color else "OFF"
        run_label = "RUNNING" if running else "PAUSED"

        safe_addstr(
            stdscr, height, 0,
            "SPACE: Toggle/Pause | s: Start(Auto-save) | p: Pause | c: Color | r: Clear | +/-: Speed | q: Quit",
            curses.A_DIM
        )
        safe_addstr(
            stdscr, height + 1, 0,
            "1: Block 2: Blinker 3: Toad 4: Glider 5: LWSS 6: MWSS 7: HWSS 8: Pulsar 9: Pentadec 0: GliderGun",
            curses.A_DIM
        )
        info_line = (
            f"[{run_label}] Gen: {generation} | Live: {len(grid)} | Speed: {speed:.2f}s | "
            f"Color: {col_name} | {status_msg}"
        )
        safe_addstr(stdscr, height + 2, 0, info_line, curses.A_BOLD)

        if notification:
            safe_addstr(stdscr, height + 3, 0, f">> {notification}", curses.color_pair(3) if has_color else curses.A_NORMAL)
        else:
            safe_addstr(stdscr, height + 3, 0, f"Cursor: ({cursor_y}, {cursor_x})")

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
                if pos in grid:
                    grid.remove(pos)
                    cell_ages.pop(pos, None)
                else:
                    grid.add(pos)
                    cell_ages[pos] = 1
                notification = ""
        elif key in map(ord, "1234567890"):
            pattern_name, pattern_cells = PATTERNS[int(chr(key))]
            for dy, dx in pattern_cells:
                ny = (cursor_y + dy) % height
                nx = (cursor_x + dx) % width
                grid.add((ny, nx))
                cell_ages[(ny, nx)] = 1
            notification = f"Stamped {pattern_name} at ({cursor_y}, {cursor_x})"
        elif key == ord('s'):
            if not running:
                saved_file = save_state(list(grid))
                notification = f"Saved initial state to {saved_file}"
                running = True
                status_msg = "Running"
        elif key == ord('p'):
            running = not running
            status_msg = "Running" if running else "Paused"
            if not running:
                notification = ""
        elif key == ord('c') and has_color:
            current_idx = COLOR_MODES.index(color_mode)
            color_mode = COLOR_MODES[(current_idx + 1) % len(COLOR_MODES)]
            notification = f"Color mode switched to: {color_mode.upper()}"
        elif key == ord('+') or key == ord('='):
            speed = max(0.01, speed - 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key == ord('-') or key == ord('_'):
            speed = min(1.0, speed + 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key == ord('w'):
            saved_file = save_state(list(grid), prefix="manual")
            notification = f"Manual save written to {saved_file}"
        elif key == ord('r'):
            grid.clear()
            cell_ages.clear()
            neighbor_counts.clear()
            history.clear()
            generation = 0
            running = False
            status_msg = "Grid cleared"
            notification = ""
        elif key in (ord('q'), 27):
            break

        if running:
            history.append(frozenset(grid))
            new_grid, new_ages, neighbor_counts = step(grid, cell_ages, height, width)
            generation += 1

            if not new_grid:
                status_msg = f"Life died out at Gen {generation}"
                running = False
            else:
                current_frozen = frozenset(new_grid)
                found_period = None
                for idx, prev_frozen in enumerate(reversed(history)):
                    if current_frozen == prev_frozen:
                        found_period = idx + 1
                        break

                if found_period == 1:
                    status_msg = f"Static pattern reached at Gen {generation}"
                elif found_period is not None:
                    status_msg = f"Oscillator (period {found_period}) at Gen {generation}"
                else:
                    status_msg = "Running"

            grid = new_grid
            cell_ages = new_ages


def parse_args():
    parser = argparse.ArgumentParser(
        description="Conway's Game of Life in terminal curses.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Controls:
  Arrow Keys      Move editing cursor
  SPACE           Toggle cell at cursor (in edit mode) or pause simulation (when running)
  s               Start simulation (automatically saves initial state to ~/.automata-game-of-life/life-*.sav)
  p               Toggle Pause / Resume
  c               Cycle color modes: AGE -> NEIGHBORS -> RAINBOW -> MONO
  + / -           Speed up / slow down simulation
  1-9, 0          Stamp preset pattern at cursor:
                    1: Block      2: Blinker    3: Toad       4: Glider   5: LWSS
                    6: MWSS       7: HWSS       8: Pulsar     9: Pentadecathlon
                    0: Gosper Glider Gun
  w               Manually save current state to ~/.automata-game-of-life/manual-*.sav
  r               Clear board / reset
  q / ESC         Quit

State Files:
  - An initial state is automatically saved to a JSON file (~/.automata-game-of-life/life-YYYYMMDD-HHMMSS.sav)
    every time you start simulation from edit mode.
  - To resume or view a saved state, pass the file path:
      python game-of-life.py life-20260919-120000.sav
"""
    )
    parser.add_argument("file", nargs="?", help="Optional path to a saved state JSON (.sav) to load")
    parser.add_argument(
        "-c", "--color",
        choices=COLOR_MODES,
        default="age",
        help="Initial color mode (default: age). Modes: age (cells age-tinted), "
             "neighbors (density-colored), rainbow (wave pattern), mono (monochrome green)."
    )
    parser.add_argument(
        "-s", "--speed",
        type=float,
        default=0.1,
        help="Initial simulation delay in seconds per generation (default: 0.1)"
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI colors and run in standard monochrome"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    curses.wrapper(lambda stdscr: run_game(stdscr, args))


if __name__ == "__main__":
    main()
