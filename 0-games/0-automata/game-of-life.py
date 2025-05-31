#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02

# Conway's Game of Life
# This version after various prompts with ChatGPT

# Lexicon of known patterns
# https://playgameoflife.com/lexicon

# Alternative python implemention
# https://www.geeksforgeeks.org/conways-game-life-python-implementation/

import curses
import time
import datetime
import json
import sys

# Define common Game of Life patterns
PATTERNS = {
    1: ("Block", [[0, 0], [0, 1], [1, 0], [1, 1]]),
    2: ("Blinker", [[0, -1], [0, 0], [0, 1]]),
    3: ("Toad", [[0, 0], [0, 1], [0, 2], [1, -1], [1, 0], [1, 1]]),
    4: ("Glider", [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]]),
    5: ("LWSS", [[0, 1], [0, 4], [1, 0], [2, 0], [2, 4], [3, 0], [3, 1], [3, 2], [3, 3]]),
    6: ("MWSS", [[0, 1], [0, 5], [1, 0], [2, 0], [2, 5], [3, 0], [3, 1], [3, 2], [3, 3], [3, 4]]),
    7: ("HWSS", [[0, 1], [0, 6], [1, 0], [2, 0], [2, 6], [3, 0], [3, 1], [3, 2], [3, 3], [3, 4], [3, 5]]),
    8: ("Pulsar", [[0, 2], [0, 3], [0, 4], [0, 8], [0, 9], [0, 10], [2, 0], [2, 5], [2, 7], [2, 12], [3, 0], [3, 5], [3, 7], [3, 12], [4, 0], [4, 5], [4, 7], [4, 12], [5, 2], [5, 3], [5, 4], [5, 8], [5, 9], [5, 10]]),
    9: ("Pentadecathlon", [[0, 1], [1, 0], [1, 2], [2, 1], [3, 1], [4, 1], [5, 1], [6, 1], [7, 1], [8, 0], [8, 2], [9, 1]]),
    0: ("Gosper Glider Gun", [[0, 24], [1, 22], [1, 24], [2, 12], [2, 13], [2, 20], [2, 21], [2, 34], [2, 35], [3, 11], [3, 15], [3, 20], [3, 21], [3, 34], [3, 35], [4, 0], [4, 1], [4, 10], [4, 16], [4, 20], [4, 21], [5, 0], [5, 1], [5, 10], [5, 14], [5, 16], [5, 17], [5, 22], [5, 24], [6, 10], [6, 16], [6, 24], [7, 11], [7, 15], [8, 12], [8, 13]])
}

def save_state(grid):
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"life-{timestamp}.sav"
    with open(filename, "w") as f:
        json.dump(grid, f)
    return filename


def load_state(filename):
    with open(filename, "r") as f:
        return json.load(f)

def get_neighbors(y, x, height, width):
    return [((y + dy) % height, (x + dx) % width)
            for dy in [-1, 0, 1] for dx in [-1, 0, 1] if (dy, dx) != (0, 0)]

def step(grid, height, width):
    new_grid = set()
    neighbor_counts = {}
    for y, x in grid:
        for ny, nx in get_neighbors(y, x, height, width):
            if (ny, nx) in neighbor_counts:
                neighbor_counts[(ny, nx)] += 1
            else:
                neighbor_counts[(ny, nx)] = 1
    for (y, x), count in neighbor_counts.items():
        if count == 3 or (count == 2 and (y, x) in grid):
            new_grid.add((y, x))
    return new_grid

def main(stdscr):
    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(100)
    
    height, width = stdscr.getmaxyx()
    height -= 4  # Leave space for UI
    
    cursor_y, cursor_x = height // 2, width // 2
    grid = set()
    speed = 0.1
    running = False
    history = []

    if len(sys.argv) > 1:
        grid = set(map(tuple, load_state(sys.argv[1])))
        running = True

    while True:
        stdscr.clear()
        for y, x in grid:
            stdscr.addch(y, x, 'o')   # Could use '█') or any other character
        if not running:
            stdscr.addch(cursor_y, cursor_x, 'X')
        
        stdscr.addstr(height, 0, "Press SPACE to toggle cells, S to start, +/- to adjust speed")
        stdscr.addstr(height + 1, 0, "1: Block  2: Blinker  3: Toad  4: Glider  5: LWSS")
        stdscr.addstr(height + 2, 0, "6: MWSS  7: HWSS 8: Pulsar 9: Pentadecathlon  0: Gospar Glider Gun")
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
            grid ^= {(cursor_y, cursor_x)}
        elif key in map(ord, "1234567890"):
            pattern_name, pattern_cells = PATTERNS[int(chr(key))]
            for dy, dx in pattern_cells:
                grid.add((cursor_y + dy, cursor_x + dx))
        elif key == ord('s'):
            save_state(list(grid))
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
                stdscr.addstr(height + 3, 0, "Life has died.")
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

