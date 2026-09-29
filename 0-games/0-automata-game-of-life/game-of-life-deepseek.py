#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
"""Conway's Game of Life (Terminal / Curses).

John Conway's 1970 zero-player cellular automaton.
A dense 2D grid engine featuring toroidal wrapping, rich color modes,
non-blocking input, preset stamping, period detection, and state persistence
in ~/.automata-game-of-life/.

Rules:
  - Any live cell with fewer than 2 live neighbors dies (underpopulation).
  - Any live cell with 2 or 3 live neighbors lives on to the next generation.
  - Any live cell with more than 3 live neighbors dies (overpopulation).
  - Any dead cell with exactly 3 live neighbors becomes a live cell (reproduction).
"""

import argparse
from collections import deque
import curses
from datetime import datetime
import json
import os
import sys

SAVE_DIR = os.path.expanduser("~/.automata-game-of-life")

# Predefined shapes (name, list of (dr, dc) offsets)
PATTERNS = {
    1: ("Glider", [(0, 1), (1, 2), (2, 0), (2, 1), (2, 2)]),
    2: ("Blinker", [(0, 0), (0, 1), (0, 2)]),
    3: ("Toad", [(0, 1), (0, 2), (0, 3), (1, 0), (1, 1), (1, 2)]),
    4: ("Beacon", [(0, 0), (0, 1), (1, 0), (1, 1), (2, 2), (2, 3), (3, 2), (3, 3)]),
    5: ("Pulsar (P=3)", [
        (0, 2), (0, 3), (0, 4), (0, 8), (0, 9), (0, 10),
        (2, 0), (2, 5), (2, 7), (2, 12),
        (3, 0), (3, 5), (3, 7), (3, 12),
        (4, 0), (4, 5), (4, 7), (4, 12),
        (5, 2), (5, 3), (5, 4), (5, 8), (5, 9), (5, 10),
        (7, 2), (7, 3), (7, 4), (7, 8), (7, 9), (7, 10),
        (8, 0), (8, 5), (8, 7), (8, 12),
        (9, 0), (9, 5), (9, 7), (9, 12),
        (10, 0), (10, 5), (10, 7), (10, 12),
        (12, 2), (12, 3), (12, 4), (12, 8), (12, 9), (12, 10)
    ]),
    6: ("LWSS (Spaceship)", [
        (0, 1), (0, 4), (1, 0), (2, 0), (2, 4), (3, 0), (3, 1), (3, 2), (3, 3)
    ]),
    7: ("Pentadecathlon (P=15)", [
        (0, 1), (0, 2), (1, 0), (1, 3), (2, 1), (2, 2),
        (3, 1), (3, 2), (4, 1), (4, 2), (5, 1), (5, 2),
        (6, 0), (6, 3), (7, 1), (7, 2)
    ]),
    8: ("Gosper Glider Gun", [
        (4, 0), (4, 1), (5, 0), (5, 1),
        (2, 12), (2, 13), (3, 11), (3, 15), (4, 10), (4, 16),
        (5, 10), (5, 14), (5, 16), (5, 17), (6, 10), (6, 16),
        (7, 11), (7, 15), (8, 12), (8, 13),
        (0, 24), (1, 22), (1, 24), (2, 20), (2, 21), (3, 20),
        (3, 21), (4, 20), (4, 21), (5, 22), (5, 24), (6, 24),
        (2, 34), (2, 35), (3, 34), (3, 35)
    ])
}

COLOR_MODES = ["matrix", "cyberpunk", "classic", "mono"]


def create_grid(rows, cols):
    """Creates a blank 2D grid."""
    return [[0 for _ in range(cols)] for _ in range(rows)]


def get_neighbors(grid, row, col, rows, cols):
    """Counts live neighbors with toroidal boundary wrapping."""
    total = 0
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr == 0 and dc == 0:
                continue
            nr = (row + dr) % rows
            nc = (col + dc) % cols
            total += grid[nr][nc]
    return total


def update_grid(grid, rows, cols):
    """Computes next generation grid and neighbor density map."""
    new_grid = create_grid(rows, cols)
    neighbor_counts = {}
    for r in range(rows):
        for c in range(cols):
            nc = get_neighbors(grid, r, c, rows, cols)
            if grid[r][c]:
                new_grid[r][c] = 1 if nc in (2, 3) else 0
                neighbor_counts[(r, c)] = nc
            else:
                new_grid[r][c] = 1 if nc == 3 else 0
                if new_grid[r][c]:
                    neighbor_counts[(r, c)] = nc
    return new_grid, neighbor_counts


def save_grid(grid, prefix="life-deepseek"):
    """Saves non-empty cells to ~/.automata-game-of-life/."""
    os.makedirs(SAVE_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filepath = os.path.join(SAVE_DIR, f"{prefix}-{timestamp}.sav")

    rows = len(grid)
    cols = len(grid[0]) if rows > 0 else 0
    live_cells = []
    for r in range(rows):
        for c in range(cols):
            if grid[r][c]:
                live_cells.append([r, c])

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(live_cells, f, indent=2)
    return filepath


def load_grid(filename, target_rows, target_cols):
    """Loads a grid from either JSON coordinate list or legacy binary text rows."""
    target = filename
    if not os.path.exists(target):
        candidate = os.path.join(SAVE_DIR, os.path.basename(filename))
        if os.path.exists(candidate):
            target = candidate

    grid = create_grid(target_rows, target_cols)
    with open(target, "r", encoding="utf-8") as f:
        content = f.read().strip()

    if not content:
        return grid

    # Try JSON format
    try:
        data = json.loads(content)
        if isinstance(data, list):
            for item in data:
                if isinstance(item, (list, tuple)) and len(item) >= 2:
                    r, c = item[0] % target_rows, item[1] % target_cols
                    grid[r][c] = 1
            return grid
        elif isinstance(data, dict):
            for k, v in data.items():
                if v:
                    coords = list(map(int, k.split(",")))
                    r, c = coords[0] % target_rows, coords[1] % target_cols
                    grid[r][c] = 1
            return grid
    except json.JSONDecodeError:
        pass

    # Legacy line-by-line binary text
    lines = content.splitlines()
    for r, line in enumerate(lines):
        if r >= target_rows:
            break
        for c, ch in enumerate(line):
            if c >= target_cols:
                break
            if ch in ('1', 'o', 'O', '#', 'X'):
                grid[r][c] = 1

    return grid


def init_colors():
    """Initializes terminal color palette."""
    curses.start_color()
    try:
        curses.use_default_colors()
    except curses.error:
        pass

    # 1: Green (Matrix live cell)
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)
    # 2: Cyan (Cyberpunk / young)
    curses.init_pair(2, curses.COLOR_CYAN, curses.COLOR_BLACK)
    # 3: Yellow (Accent / warning)
    curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    # 4: Magenta (Cyberpunk live)
    curses.init_pair(4, curses.COLOR_MAGENTA, curses.COLOR_BLACK)
    # 5: White (Bright highlight)
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLACK)
    # 6: Blue (Classic deep)
    curses.init_pair(6, curses.COLOR_BLUE, curses.COLOR_BLACK)
    # 7: Red (Overcrowded / Cursor)
    curses.init_pair(7, curses.COLOR_RED, curses.COLOR_BLACK)


def get_cell_style(r, c, nc, color_mode, has_color):
    """Returns (character, curses_attribute) for Conway cell."""
    if not has_color or color_mode == "mono":
        return 'o', curses.A_BOLD

    if color_mode == "matrix":
        if nc == 3:
            return 'o', curses.color_pair(1) | curses.A_BOLD
        return 'o', curses.color_pair(1)
    elif color_mode == "cyberpunk":
        if nc == 3:
            return 'o', curses.color_pair(4) | curses.A_BOLD
        elif nc == 2:
            return 'o', curses.color_pair(2) | curses.A_BOLD
        return 'o', curses.color_pair(3)
    elif color_mode == "classic":
        if nc == 3:
            return 'o', curses.color_pair(5) | curses.A_BOLD
        return 'o', curses.color_pair(2)

    return 'o', curses.color_pair(1)


def safe_addch(stdscr, y, x, ch, attr=curses.A_NORMAL):
    try:
        stdscr.addch(y, x, ch, attr)
    except curses.error:
        pass


def safe_addstr(stdscr, y, x, text, attr=curses.A_NORMAL):
    try:
        stdscr.addstr(y, x, text, attr)
    except curses.error:
        pass


def run_game(stdscr, args):
    curses.curs_set(0)
    has_color = curses.has_colors() and not args.no_color
    if has_color:
        init_colors()

    max_y, max_x = stdscr.getmaxyx()
    rows = max(5, max_y - 4)
    cols = max_x

    grid = create_grid(rows, cols)
    cursor_pos = [rows // 2, cols // 2]
    generation = 0
    status_msg = "Editing (Paused)"
    notification = ""
    speed = max(0.01, min(1.0, args.speed))
    color_mode = args.color
    running = False
    history = deque(maxlen=64)
    neighbor_counts = {}

    if args.file:
        try:
            grid = load_grid(args.file, rows, cols)
            status_msg = f"Loaded {os.path.basename(args.file)}"
        except Exception as e:
            status_msg = f"Failed to load: {e}"

    while True:
        max_y, max_x = stdscr.getmaxyx()
        current_rows = max(5, max_y - 4)
        current_cols = max_x

        # Adapt grid if window resized
        if current_rows != rows or current_cols != cols:
            new_g = create_grid(current_rows, current_cols)
            for r in range(min(rows, current_rows)):
                for c in range(min(cols, current_cols)):
                    new_g[r][c] = grid[r][c]
            grid = new_g
            rows, cols = current_rows, current_cols

        cursor_pos[0] %= rows
        cursor_pos[1] %= cols

        stdscr.erase()

        # Render living cells
        live_count = 0
        for r in range(rows):
            for c in range(cols):
                if grid[r][c]:
                    live_count += 1
                    nc = neighbor_counts.get((r, c), 2)
                    ch, attr = get_cell_style(r, c, nc, color_mode, has_color)
                    safe_addch(stdscr, r, c, ch, attr)

        # Render cursor in edit mode
        if not running:
            cursor_attr = (curses.color_pair(3) | curses.A_BOLD) if has_color else curses.A_STANDOUT
            cursor_ch = 'X' if grid[cursor_pos[0]][cursor_pos[1]] == 0 else '*'
            safe_addch(stdscr, cursor_pos[0], cursor_pos[1], cursor_ch, cursor_attr)

        # Bottom UI
        run_label = "RUNNING" if running else "PAUSED"
        safe_addstr(
            stdscr, rows, 0,
            "SPACE: Toggle/Pause | s: Start(Auto-save) | p: Pause | c: Color | r: Clear | +/-: Speed | q: Quit",
            curses.A_DIM
        )
        safe_addstr(
            stdscr, rows + 1, 0,
            "Presets: 1: Glider 2: Blinker 3: Toad 4: Beacon 5: Pulsar 6: LWSS 7: Pentadec 8: Gun",
            curses.A_DIM
        )
        info_line = (
            f"[{run_label}] Gen: {generation} | Population: {live_count} | Speed: {speed:.2f}s | "
            f"Palette: {color_mode.upper()} | {status_msg}"
        )
        safe_addstr(stdscr, rows + 2, 0, info_line, curses.A_BOLD)

        if notification:
            safe_addstr(stdscr, rows + 3, 0, f">> {notification}", curses.color_pair(3) if has_color else curses.A_NORMAL)
        else:
            safe_addstr(stdscr, rows + 3, 0, f"Cursor: ({cursor_pos[0]}, {cursor_pos[1]})")

        stdscr.refresh()

        timeout_ms = max(10, int(speed * 1000)) if running else 100
        stdscr.timeout(timeout_ms)

        try:
            key = stdscr.getch()
        except curses.error:
            key = -1

        if key == curses.KEY_UP:
            cursor_pos[0] = (cursor_pos[0] - 1) % rows
        elif key == curses.KEY_DOWN:
            cursor_pos[0] = (cursor_pos[0] + 1) % rows
        elif key == curses.KEY_LEFT:
            cursor_pos[1] = (cursor_pos[1] - 1) % cols
        elif key == curses.KEY_RIGHT:
            cursor_pos[1] = (cursor_pos[1] + 1) % cols
        elif key == ord(' '):
            if running:
                running = False
                status_msg = "Paused"
                notification = ""
            else:
                grid[cursor_pos[0]][cursor_pos[1]] ^= 1
                notification = ""
        elif key in map(ord, "12345678"):
            p_idx = int(chr(key))
            p_name, p_cells = PATTERNS[p_idx]
            for dr, dc in p_cells:
                nr = (cursor_pos[0] + dr) % rows
                nc = (cursor_pos[1] + dc) % cols
                grid[nr][nc] = 1
            notification = f"Stamped {p_name} at ({cursor_pos[0]}, {cursor_pos[1]})"
        elif key == ord('s'):
            if not running:
                saved_path = save_grid(grid)
                notification = f"Saved initial state to {saved_path}"
                running = True
                status_msg = "Running"
        elif key == ord('p'):
            running = not running
            status_msg = "Running" if running else "Paused"
            if not running:
                notification = ""
        elif key in (ord('w'), ord('W')):
            saved_path = save_grid(grid, prefix="manual-life-deepseek")
            notification = f"Manual save written to {saved_path}"
        elif key == ord('c') and has_color:
            c_idx = COLOR_MODES.index(color_mode)
            color_mode = COLOR_MODES[(c_idx + 1) % len(COLOR_MODES)]
            notification = f"Color mode switched to: {color_mode.upper()}"
        elif key in (ord('+'), ord('=')):
            speed = max(0.01, speed - 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key in (ord('-'), ord('_')):
            speed = min(1.0, speed + 0.02)
            notification = f"Speed: {speed:.2f}s per gen"
        elif key == ord('r'):
            grid = create_grid(rows, cols)
            neighbor_counts.clear()
            history.clear()
            generation = 0
            running = False
            status_msg = "Grid cleared"
            notification = ""
        elif key in (ord('q'), 27):
            break

        if running:
            # Capture live cell coordinates for period detection
            current_live = frozenset(
                (r, c) for r in range(rows) for c in range(cols) if grid[r][c]
            )
            history.append(current_live)

            new_grid, neighbor_counts = update_grid(grid, rows, cols)
            generation += 1

            new_live = frozenset(
                (r, c) for r in range(rows) for c in range(cols) if new_grid[r][c]
            )

            if not new_live:
                status_msg = f"Extinct at generation {generation}"
                running = False
            else:
                found_period = None
                for idx, prev_state in enumerate(reversed(history)):
                    if new_live == prev_state:
                        found_period = idx + 1
                        break

                if found_period == 1:
                    status_msg = f"Static configuration at Gen {generation}"
                elif found_period is not None:
                    status_msg = f"Oscillator (period {found_period}) at Gen {generation}"
                else:
                    status_msg = "Running"

            grid = new_grid


def parse_args():
    parser = argparse.ArgumentParser(
        description="Conway's Game of Life (Terminal / Curses Matrix Engine).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Controls:
  Arrow Keys      Move cursor
  SPACE           Toggle cell at cursor (in edit mode) or pause simulation (when running)
  s               Start simulation (automatically saves initial state to ~/.automata-game-of-life/)
  p               Toggle Pause / Resume
  c               Cycle color modes: MATRIX -> CYBERPUNK -> CLASSIC -> MONO
  + / -           Speed up / slow down simulation
  1-8             Stamp preset pattern at cursor:
                    1: Glider     2: Blinker  3: Toad     4: Beacon
                    5: Pulsar     6: LWSS     7: Pentadec 8: Glider Gun
  w               Manually save current state to ~/.automata-game-of-life/manual-*.sav
  r               Clear board / reset
  q / ESC         Quit

State Files:
  - Initial states are saved to ~/.automata-game-of-life/life-deepseek-YYYYMMDD-HHMMSS.sav.
  - Load saved state with:
      python game-of-life-deepseek.py life-deepseek-20260920-120000.sav
"""
    )
    parser.add_argument("file", nargs="?", help="Optional path to saved state JSON or text file to load")
    parser.add_argument(
        "-c", "--color",
        choices=COLOR_MODES,
        default="matrix",
        help="Initial color mode (default: matrix)."
    )
    parser.add_argument(
        "-s", "--speed",
        type=float,
        default=0.1,
        help="Initial delay in seconds per generation (default: 0.1)"
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI colors and run in monochrome"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    curses.wrapper(lambda stdscr: run_game(stdscr, args))


if __name__ == "__main__":
    main()
