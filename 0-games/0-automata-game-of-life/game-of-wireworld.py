#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05
"""Wireworld Cellular Automaton (Terminal / Curses).

Wireworld is a cellular automaton developed by Brian Silverman in 1987 to model
electronic circuits and digital logic operations through local cell interactions.

Rules:
  Cells exist in four states:
    0: Empty (quiescent space)
    1: Wire / Conductor (copper track)
    2: Electron Head (active high signal)
    3: Electron Tail (repolarizing state)

  State Transitions:
    - Empty -> Empty
    - Electron Head -> Electron Tail
    - Electron Tail -> Wire
    - Wire -> Electron Head IF exactly 1 or 2 neighbor cells are Electron Heads;
              otherwise remains Wire.

Features:
  - Interactive terminal UI with cursor navigation and cell placement
  - Direct state keys (w: Wire, h: Head, t: Tail, x: Erase) and SPACE cycling
  - Circuit presets (Clock Loop, Diode, Splitter, Integrated Circuit, Dual Clocks, etc.)
  - Color palettes (electric, copper, matrix, mono)
  - Period and oscillator detection with bounded history window
  - Automatic & manual state persistence in ~/.automata-game-of-life/
  - Toroidal screen wrapping for boundless circuit design
"""

import argparse
from collections import deque
import curses
import datetime
import json
import os
import sys

SAVE_DIR = os.path.expanduser("~/.automata-game-of-life")

# Cell States
EMPTY = 0
WIRE = 1
HEAD = 2
TAIL = 3

STATE_NAMES = {
    EMPTY: "Empty",
    WIRE: "Wire",
    HEAD: "Head",
    TAIL: "Tail"
}

COLOR_MODES = ["electric", "copper", "matrix", "mono"]

# Preset patterns: list of (dy, dx, state)
PATTERNS = {
    1: ("Clock Loop (P=10)", [
        # Perimeter-10 ring
        (0, 1, WIRE), (0, 2, WIRE), (0, 3, WIRE),
        (1, 0, WIRE), (2, 0, WIRE),
        (3, 1, WIRE), (3, 2, WIRE), (3, 3, WIRE),
        (2, 4, WIRE), (1, 4, WIRE),
        # Output transmission lead
        (1, 5, WIRE), (1, 6, WIRE), (1, 7, WIRE), (1, 8, WIRE),
        (1, 9, WIRE), (1, 10, WIRE), (1, 11, WIRE), (1, 12, WIRE),
        (1, 13, WIRE), (1, 14, WIRE), (1, 15, WIRE),
        # Initial circulating electron
        (0, 1, HEAD), (0, 2, TAIL)
    ]),
    2: ("Diode Gate (One-Way Valve)", [
        # Input lead
        (1, 0, WIRE), (1, 1, WIRE),
        # Asymmetric gate (passes left-to-right, cancels right-to-left)
        (0, 2, WIRE), (0, 3, WIRE), (0, 5, WIRE),
        (1, 2, WIRE), (1, 4, WIRE),
        (2, 2, WIRE), (2, 3, WIRE),
        # Output lead
        (1, 6, WIRE), (1, 7, WIRE), (1, 8, WIRE), (1, 9, WIRE),
        (1, 10, WIRE), (1, 11, WIRE), (1, 12, WIRE),
        # Incoming forward pulse
        (1, 1, HEAD), (1, 0, TAIL)
    ]),
    3: ("Pulse Splitter (1-to-2 Fork)", [
        # Trunk wire
        (2, 0, WIRE), (2, 1, WIRE), (2, 2, WIRE), (2, 3, WIRE),
        # Upper branch
        (1, 4, WIRE), (1, 5, WIRE), (1, 6, WIRE), (1, 7, WIRE),
        (1, 8, WIRE), (1, 9, WIRE), (1, 10, WIRE), (1, 11, WIRE),
        # Lower branch
        (3, 4, WIRE), (3, 5, WIRE), (3, 6, WIRE), (3, 7, WIRE),
        (3, 8, WIRE), (3, 9, WIRE), (3, 10, WIRE), (3, 11, WIRE),
        # Electron heading into fork
        (2, 1, HEAD), (2, 0, TAIL)
    ]),
    4: ("IC: Clock + Diode + Splitter", [
        # Clock loop
        (0, 1, WIRE), (0, 2, WIRE), (0, 3, WIRE),
        (1, 0, WIRE), (2, 0, WIRE),
        (3, 1, WIRE), (3, 2, WIRE), (3, 3, WIRE),
        (2, 4, WIRE), (1, 4, WIRE),
        # Lead to diode buffer
        (1, 5, WIRE), (1, 6, WIRE),
        # Diode
        (0, 7, WIRE), (0, 8, WIRE), (0, 10, WIRE),
        (1, 7, WIRE), (1, 9, WIRE),
        (2, 7, WIRE), (2, 8, WIRE),
        # Splitter junction
        (1, 11, WIRE), (1, 12, WIRE), (1, 13, WIRE),
        # Dual rails
        (0, 14, WIRE), (0, 15, WIRE), (0, 16, WIRE), (0, 17, WIRE), (0, 18, WIRE),
        (0, 19, WIRE), (0, 20, WIRE), (0, 21, WIRE), (0, 22, WIRE), (0, 23, WIRE),
        (2, 14, WIRE), (2, 15, WIRE), (2, 16, WIRE), (2, 17, WIRE), (2, 18, WIRE),
        (2, 19, WIRE), (2, 20, WIRE), (2, 21, WIRE), (2, 22, WIRE), (2, 23, WIRE),
        # Electron in clock
        (0, 1, HEAD), (0, 2, TAIL)
    ]),
    5: ("Dual Clocks (P=8 & P=12)", [
        # Clock 8
        (0, 1, WIRE), (0, 2, WIRE), (1, 3, WIRE), (2, 3, WIRE),
        (3, 2, WIRE), (3, 1, WIRE), (2, 0, WIRE), (1, 0, WIRE),
        (1, 4, WIRE), (1, 5, WIRE), (1, 6, WIRE), (1, 7, WIRE),
        (1, 8, WIRE), (1, 9, WIRE), (1, 10, WIRE),
        (0, 1, HEAD), (0, 2, TAIL),
        # Clock 12
        (5, 1, WIRE), (5, 2, WIRE), (5, 3, WIRE), (5, 4, WIRE),
        (6, 5, WIRE), (7, 5, WIRE),
        (8, 4, WIRE), (8, 3, WIRE), (8, 2, WIRE), (8, 1, WIRE),
        (7, 0, WIRE), (6, 0, WIRE),
        (6, 6, WIRE), (6, 7, WIRE), (6, 8, WIRE), (6, 9, WIRE), (6, 10, WIRE),
        (5, 1, HEAD), (5, 2, TAIL)
    ]),
    6: ("Transmission Line", [
        (0, x, WIRE) for x in range(24)
    ] + [(0, 1, HEAD), (0, 0, TAIL)]),
    7: ("OR Gate Junction", [
        (0, 0, WIRE), (0, 1, WIRE), (0, 2, WIRE), (0, 3, WIRE), (0, 4, WIRE),
        (2, 0, WIRE), (2, 1, WIRE), (2, 2, WIRE), (2, 3, WIRE), (2, 4, WIRE),
        (1, 5, WIRE), (1, 6, WIRE), (1, 7, WIRE), (1, 8, WIRE), (1, 9, WIRE),
        (1, 10, WIRE), (1, 11, WIRE), (1, 12, WIRE),
        (0, 1, HEAD), (0, 0, TAIL),
        (2, 1, HEAD), (2, 0, TAIL)
    ])
}


def save_state(grid, prefix="wireworld"):
    """Saves current non-empty cells to ~/.automata-game-of-life/."""
    os.makedirs(SAVE_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = os.path.join(SAVE_DIR, f"{prefix}-{timestamp}.sav")
    serializable = {f"{y},{x}": int(state) for (y, x), state in grid.items() if state != EMPTY}
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(serializable, f, indent=2)
    return filename


def load_state(filename):
    """Loads grid from JSON file, looking in cwd or ~/.automata-game-of-life/."""
    target = filename
    if not os.path.exists(target):
        candidate = os.path.join(SAVE_DIR, os.path.basename(filename))
        if os.path.exists(candidate):
            target = candidate
    with open(target, "r", encoding="utf-8") as f:
        data = json.load(f)

    grid = {}
    for k, v in data.items():
        coords = tuple(map(int, k.split(",")))
        if isinstance(v, int):
            grid[coords] = v
        elif isinstance(v, str):
            v_upper = v.upper()
            if v_upper in ("W", "1"):
                grid[coords] = WIRE
            elif v_upper in ("H", "2"):
                grid[coords] = HEAD
            elif v_upper in ("T", "3"):
                grid[coords] = TAIL
            elif v.isdigit():
                grid[coords] = int(v)
    return grid


def get_neighbors(y, x, height, width):
    """Returns 8-neighborhood with toroidal wrapping."""
    return [
        ((y + dy) % height, (x + dx) % width)
        for dy in (-1, 0, 1)
        for dx in (-1, 0, 1)
        if not (dy == 0 and dx == 0)
    ]


def step(grid, height, width):
    """Calculates the next generation of Wireworld.

    Rules:
      - HEAD (2) -> TAIL (3)
      - TAIL (3) -> WIRE (1)
      - WIRE (1) -> HEAD (2) if exactly 1 or 2 neighbor HEADs, else WIRE (1)
    """
    new_grid = {}
    for (y, x), state in grid.items():
        if state == HEAD:
            new_grid[(y, x)] = TAIL
        elif state == TAIL:
            new_grid[(y, x)] = WIRE
        elif state == WIRE:
            head_count = 0
            for ny, nx in get_neighbors(y, x, height, width):
                if grid.get((ny, nx)) == HEAD:
                    head_count += 1
            if head_count in (1, 2):
                new_grid[(y, x)] = HEAD
            else:
                new_grid[(y, x)] = WIRE
    return new_grid


def init_colors():
    """Initializes terminal color pairs."""
    curses.start_color()
    try:
        curses.use_default_colors()
    except curses.error:
        pass

    # 1: WIRE (White)
    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLACK)
    # 2: HEAD (Yellow)
    curses.init_pair(2, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    # 3: TAIL (Cyan)
    curses.init_pair(3, curses.COLOR_CYAN, curses.COLOR_BLACK)
    # 4: COPPER/AMBER WIRE (Red)
    curses.init_pair(4, curses.COLOR_RED, curses.COLOR_BLACK)
    # 5: MATRIX (Green)
    curses.init_pair(5, curses.COLOR_GREEN, curses.COLOR_BLACK)
    # 6: ELECTRIC WIRE (Blue)
    curses.init_pair(6, curses.COLOR_BLUE, curses.COLOR_BLACK)
    # 7: ACCENT (Magenta)
    curses.init_pair(7, curses.COLOR_MAGENTA, curses.COLOR_BLACK)


def get_cell_render(state, color_mode, has_color):
    """Returns (character, curses_attribute) for a given state."""
    if not has_color or color_mode == "mono":
        if state == HEAD:
            return 'O', curses.A_STANDOUT | curses.A_BOLD
        elif state == TAIL:
            return 'o', curses.A_UNDERLINE
        elif state == WIRE:
            return '#', curses.A_NORMAL
        return ' ', curses.A_NORMAL

    if color_mode == "electric":
        if state == HEAD:
            return 'O', curses.color_pair(2) | curses.A_BOLD  # Bright Yellow
        elif state == TAIL:
            return 'o', curses.color_pair(3) | curses.A_BOLD  # Cyan
        elif state == WIRE:
            return '#', curses.color_pair(6) | curses.A_BOLD  # Blue wire
    elif color_mode == "copper":
        if state == HEAD:
            return 'O', curses.color_pair(1) | curses.A_BOLD  # Bright White
        elif state == TAIL:
            return 'o', curses.color_pair(2)                  # Yellow
        elif state == WIRE:
            return '#', curses.color_pair(4)                  # Copper/Red
    elif color_mode == "matrix":
        if state == HEAD:
            return 'O', curses.color_pair(1) | curses.A_BOLD  # White
        elif state == TAIL:
            return 'o', curses.color_pair(5) | curses.A_BOLD  # Bright Green
        elif state == WIRE:
            return '#', curses.color_pair(5) | curses.A_DIM   # Dim Green

    return '#', curses.color_pair(1)


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

    grid = {}
    speed = max(0.01, min(1.0, args.speed))
    color_mode = args.color
    running = False
    generation = 0
    status_msg = "Editing (Paused)"
    notification = ""
    history = deque(maxlen=64)

    max_y, max_x = stdscr.getmaxyx()
    height = max(5, max_y - 4)
    width = max_x
    cursor_y, cursor_x = height // 2, width // 2

    if args.file:
        try:
            grid = load_state(args.file)
            status_msg = f"Loaded {os.path.basename(args.file)}"
        except Exception as e:
            status_msg = f"Load failed: {e}"

    while True:
        max_y, max_x = stdscr.getmaxyx()
        height = max(5, max_y - 4)
        width = max_x

        cursor_y %= height
        cursor_x %= width

        stdscr.erase()

        # Render circuit cells
        for (y, x), state in grid.items():
            if 0 <= y < height and 0 <= x < width and state != EMPTY:
                ch, attr = get_cell_render(state, color_mode, has_color)
                safe_addch(stdscr, y, x, ch, attr)

        # Render cursor when paused
        if not running:
            cursor_cell = grid.get((cursor_y, cursor_x), EMPTY)
            cursor_attr = (curses.color_pair(7) | curses.A_BOLD) if has_color else curses.A_STANDOUT
            char = 'X' if cursor_cell == EMPTY else '*'
            safe_addch(stdscr, cursor_y, cursor_x, char, cursor_attr)

        # Status & Controls display
        wire_cnt = sum(1 for s in grid.values() if s == WIRE)
        head_cnt = sum(1 for s in grid.values() if s == HEAD)
        tail_cnt = sum(1 for s in grid.values() if s == TAIL)
        run_label = "RUNNING" if running else "PAUSED"
        cur_cell_state = STATE_NAMES.get(grid.get((cursor_y, cursor_x), EMPTY), "Empty")

        safe_addstr(
            stdscr, height, 0,
            "SPACE: Cycle/Pause | w: Wire | h: Head | t: Tail | x: Erase | s: Start | p: Pause | c: Color | q: Quit",
            curses.A_DIM
        )
        safe_addstr(
            stdscr, height + 1, 0,
            "Presets: 1: Clock(P=10) 2: Diode 3: Splitter 4: IC(Clk+Dio+Split) 5: DualClocks 6: Line 7: OR-Gate",
            curses.A_DIM
        )
        info_line = (
            f"[{run_label}] Gen: {generation} | Wires: {wire_cnt} | Pulses: {head_cnt + tail_cnt} | "
            f"Speed: {speed:.2f}s | Palette: {color_mode.upper()} | {status_msg}"
        )
        safe_addstr(stdscr, height + 2, 0, info_line, curses.A_BOLD)

        if notification:
            safe_addstr(stdscr, height + 3, 0, f">> {notification}", curses.color_pair(2) if has_color else curses.A_NORMAL)
        else:
            safe_addstr(stdscr, height + 3, 0, f"Cursor: ({cursor_y}, {cursor_x}) [{cur_cell_state}]")

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
                cur = grid.get((cursor_y, cursor_x), EMPTY)
                next_state = (cur + 1) % 4
                if next_state == EMPTY:
                    grid.pop((cursor_y, cursor_x), None)
                else:
                    grid[(cursor_y, cursor_x)] = next_state
                notification = ""
        elif key in (ord('w'), ord('W')) and not running:
            grid[(cursor_y, cursor_x)] = WIRE
            notification = "Placed Wire"
        elif key in (ord('h'), ord('H')) and not running:
            grid[(cursor_y, cursor_x)] = HEAD
            notification = "Placed Electron Head"
        elif key in (ord('t'), ord('T')) and not running:
            grid[(cursor_y, cursor_x)] = TAIL
            notification = "Placed Electron Tail"
        elif key in (ord('x'), ord('X'), curses.KEY_DC, 127, 8) and not running:
            grid.pop((cursor_y, cursor_x), None)
            notification = "Erased cell"
        elif key in map(ord, "1234567"):
            p_idx = int(chr(key))
            p_name, p_cells = PATTERNS[p_idx]
            for dy, dx, st in p_cells:
                ny = (cursor_y + dy) % height
                nx = (cursor_x + dx) % width
                if st == EMPTY:
                    grid.pop((ny, nx), None)
                else:
                    grid[(ny, nx)] = st
            notification = f"Stamped {p_name} at ({cursor_y}, {cursor_x})"
        elif key == ord('s'):
            if not running:
                active_cells = {k: v for k, v in grid.items() if v != EMPTY}
                saved_file = save_state(active_cells)
                notification = f"Saved initial circuit to {saved_file}"
                running = True
                status_msg = "Running"
        elif key == ord('p'):
            running = not running
            status_msg = "Running" if running else "Paused"
            if not running:
                notification = ""
        elif key in (ord('m'), ord('S')):
            active_cells = {k: v for k, v in grid.items() if v != EMPTY}
            saved_file = save_state(active_cells, prefix="manual-wireworld")
            notification = f"Manual save written to {saved_file}"
        elif key == ord('c') and has_color:
            c_idx = COLOR_MODES.index(color_mode)
            color_mode = COLOR_MODES[(c_idx + 1) % len(COLOR_MODES)]
            notification = f"Palette switched to: {color_mode.upper()}"
        elif key in (ord('+'), ord('=')):
            speed = max(0.01, speed - 0.02)
            notification = f"Speed: {speed:.2f}s per step"
        elif key in (ord('-'), ord('_')):
            speed = min(1.0, speed + 0.02)
            notification = f"Speed: {speed:.2f}s per step"
        elif key == ord('r'):
            grid.clear()
            history.clear()
            generation = 0
            running = False
            status_msg = "Circuit cleared"
            notification = ""
        elif key in (ord('q'), 27):
            break

        if running:
            frozen_state = tuple(sorted((k, v) for k, v in grid.items() if v != WIRE))
            history.append(frozen_state)

            new_grid = step(grid, height, width)
            generation += 1

            has_electrons = any(s in (HEAD, TAIL) for s in new_grid.values())
            if not has_electrons:
                status_msg = f"Circuit static (quiescent) at Gen {generation}"
            else:
                current_frozen = tuple(sorted((k, v) for k, v in new_grid.items() if v != WIRE))
                found_period = None
                for idx, prev_state in enumerate(reversed(history)):
                    if current_frozen == prev_state:
                        found_period = idx + 1
                        break

                if found_period == 1:
                    status_msg = f"Static pulse state at Gen {generation}"
                elif found_period is not None:
                    status_msg = f"Oscillating circuit (period {found_period}) at Gen {generation}"
                else:
                    status_msg = "Running"

            grid = new_grid


def parse_args():
    parser = argparse.ArgumentParser(
        description="Wireworld Cellular Automaton (Computer Logic & Circuit Simulation).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Controls:
  Arrow Keys      Move cursor
  SPACE           Cycle cell state (Empty -> Wire -> Head -> Tail -> Empty) or Pause
  w               Place Wire (conductor) at cursor
  h               Place Electron Head at cursor
  t               Place Electron Tail at cursor
  x / Backspace   Erase cell at cursor
  s               Start simulation (auto-saves to ~/.automata-game-of-life/wireworld-*.sav)
  p               Toggle Pause / Resume
  m / Shift+S     Manually save circuit state to ~/.automata-game-of-life/manual-wireworld-*.sav
  c               Cycle color palettes: ELECTRIC -> COPPER -> MATRIX -> MONO
  + / -           Speed up / slow down simulation
  1-7             Stamp preset pattern at cursor:
                    1: Clock Loop (P=10)       2: Diode Gate (One-Way)
                    3: Pulse Splitter (1-to-2) 4: IC: Clock + Diode + Splitter
                    5: Dual Clocks (P=8 & 12)  6: Transmission Line
                    7: OR Gate Junction
  r               Clear board / reset
  q / ESC         Quit

State Files:
  - Starting simulation automatically creates a timestamped save file in
    ~/.automata-game-of-life/wireworld-YYYYMMDD-HHMMSS.sav.
  - Load any saved circuit with:
      python game-of-wireworld.py wireworld-20260920-120000.sav
"""
    )
    parser.add_argument("file", nargs="?", help="Optional path to saved JSON state file (.sav) to load")
    parser.add_argument(
        "-c", "--color",
        choices=COLOR_MODES,
        default="electric",
        help="Initial color palette (default: electric)."
    )
    parser.add_argument(
        "-s", "--speed",
        type=float,
        default=0.08,
        help="Initial delay in seconds per generation (default: 0.08)"
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
