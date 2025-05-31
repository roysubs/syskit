#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05

# Wireworld Cellular Automaton

# Wireworld (Rule Set)
# Philosophy: A cellular automaton designed to model electronic circuits.
# Rules:
# - Empty (0), Wire (1), Electron Head (2), Electron Tail (3)
# - Electron Head becomes Electron Tail in the next generation.
# - Electron Tail becomes Empty.
# - An Electron Head is created if a neighboring Wire has exactly one or two Electron Tails.
# - Wire cells are just connectors.
# Behavior: Wireworld can simulate logic gates (AND, OR, NOT) and perform basic computations, showing how simple local interactions can generate complex behaviors.

import curses
import time
import datetime
import json
import sys

PATTERNS = {
    1: ("Wire Loop", [[0, 0], [0, 1], [1, 1], [1, 0]]),
    2: ("Glider", [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]]),
}

def save_state(grid):
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"wireworld-{timestamp}.sav"
    with open(filename, "w") as f:
        json.dump({f"{k[0]},{k[1]}": v for k, v in grid.items()}, f)
    return filename

def load_state(filename):
    with open(filename, "r") as f:
        return {tuple(map(int, k.split(','))): v for k, v in json.load(f).items()}

def get_neighbors(y, x, height, width):
    return [((y + dy) % height, (x + dx) % width)
            for dy in [-1, 0, 1] for dx in [-1, 0, 1] if (dy, dx) != (0, 0)]

def step(grid, height, width):
    new_grid = {}
    
    for (y, x), state in grid.items():
        if state == 2:  # Electron Head
            new_grid[(y, x)] = 3  # Become Electron Tail
        elif state == 3:  # Electron Tail
            new_grid[(y, x)] = 0  # Become Empty

    for (y, x), state in grid.items():
        if state == 1:  # Wire
            head_count = 0
            for ny, nx in get_neighbors(y, x, height, width):
                if grid.get((ny, nx)) == 3:  # Electron Tail
                    head_count += 1
            if head_count == 1 or head_count == 2:
                new_grid[(y, x)] = 2  # Become Electron Head

    return new_grid

def main(stdscr):
    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(100)

    # Initialize color pairs
    curses.start_color()
    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Wire (White)
    curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK)  # Electron Head (Red)
    curses.init_pair(3, curses.COLOR_BLUE, curses.COLOR_BLACK)  # Electron Tail (Blue)
    curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_BLACK)  # Empty (Black)

    height, width = stdscr.getmaxyx()
    height -= 4  # Leave space for UI

    cursor_y, cursor_x = height // 2, width // 2
    grid = {}
    speed = 0.1
    running = False
    history = []

    if len(sys.argv) > 1:
        grid = load_state(sys.argv[1])
        running = True

    while True:
        stdscr.clear()
        for (y, x), state in grid.items():
            if state == 1:
                stdscr.addch(y, x, '#', curses.color_pair(1))  # Wire
            elif state == 2:
                stdscr.addch(y, x, 'O', curses.color_pair(2))  # Electron Head
            elif state == 3:
                stdscr.addch(y, x, 'o', curses.color_pair(3))  # Electron Tail

        if not running:
            stdscr.addch(cursor_y, cursor_x, 'X', curses.color_pair(4))  # Empty for cursor position

        stdscr.addstr(height, 0, "Press SPACE to toggle cells, S to start, +/- to adjust speed")
        stdscr.addstr(height + 1, 0, "1: Wire Loop  2: Glider")
        stdscr.addstr(height + 3, 0, f"Generation: {len(history)} Speed: {speed:.2f}s")
        stdscr.refresh()
        key = stdscr.getch()

        if key == curses.KEY_UP and cursor_y > 0:
            cursor_y -= 1
        elif key == curses.KEY_DOWN and cursor_y < height - 1:
            cursor_y += 1
        elif key == curses.KEY_LEFT and cursor_x > 0:
            cursor_x -= 1
        elif key == curses.KEY_RIGHT and cursor_x < width - 1:
            cursor_x += 1
        elif key == ord(' '):
            current_state = grid.get((cursor_y, cursor_x), 0)
            grid[(cursor_y, cursor_x)] = (current_state + 1) % 4  # Toggle through Empty, Wire, Electron Head, Electron Tail
        elif key in map(ord, "12"):
            pattern_name, pattern_cells = PATTERNS[int(chr(key))]
            for dy, dx in pattern_cells:
                grid[(cursor_y + dy, cursor_x + dx)] = 1  # Place Wire
        elif key == ord('s'):
            save_state({k: v for k, v in grid.items() if v != 0})
            running = True
        elif key == ord('+'):
            speed = max(0.01, speed - 0.02)
        elif key == ord('-'):
            speed += 0.02
        elif key == ord('q'):
            break

        if running:
            history.append(grid.copy())
            new_grid = step(grid, height, width)
            if not new_grid:
                stdscr.addstr(height + 3, 0, "Circuit has stopped.")
                stdscr.refresh()
                time.sleep(2)
                break
            elif new_grid in history:
                stdscr.addstr(height + 3, 0, f"Reached repeating shape at generation {len(history)}")
                stdscr.refresh()
                time.sleep(2)
                break
            grid = new_grid
            time.sleep(speed)

if __name__ == "__main__":
    curses.wrapper(main)

