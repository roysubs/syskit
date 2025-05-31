#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02

# Brian's Brain Cellular Automaton

# Brian's Brain (Rule Set)
# Philosophy: Focuses on simplicity and emulating neural activity in a cellular automaton.
# Rules:
# Each cell has three states: ON, OFF, and RECRUITING.
# A cell turns ON if it was OFF and has exactly two ON neighbors.
# A cell turns OFF if it was ON, and its neighbors have less than two or more than three ON neighbors.
# A cell stays OFF if it has one or zero ON neighbors.
# Behavior: Brian's Brain is known for periodic, wave-like patterns, creating random-looking "neural activity." It doesn't have stable patterns like in Conway's Game of Life, but exhibits constant activity and interesting local interactions.
# Philosophy Behind the Rules: Inspired by brain activity and neural networks, where cells (neurons) "fire" and generate activity in neighboring cells, mimicking how neurons interact in the brain.

import curses
import time
import datetime
import json
import sys

PATTERNS = {
    1: ("Blinker", [[0, -1], [0, 0], [0, 1]]),
    2: ("Glider", [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]]),
    3: ("Puffer", [[0, 1], [0, 2], [1, 0], [1, 3], [2, 1], [2, 2], [3, 0], [3, 3]]),
    4: ("Brain Spiral", [[0, 1], [1, 2], [2, 0], [2, 1]]),
}

def save_state(grid):
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"brain-{timestamp}.sav"
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
    neighbor_counts = {}
    
    for (y, x), state in grid.items():
        if state == "ON":
            new_grid[(y, x)] = "RECRUITING"
        elif state == "RECRUITING":
            new_grid[(y, x)] = "OFF"
    
        for ny, nx in get_neighbors(y, x, height, width):
            neighbor_counts[(ny, nx)] = neighbor_counts.get((ny, nx), 0) + (1 if state == "ON" else 0)
    
    for (y, x), count in neighbor_counts.items():
        if count == 2 and grid.get((y, x), "OFF") == "OFF":
            new_grid[(y, x)] = "ON"
    
    return new_grid

def main(stdscr):
    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(100)

    # Initialize color pairs
    curses.start_color()
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)  # ON (Green)
    curses.init_pair(2, curses.COLOR_YELLOW, curses.COLOR_BLACK)  # RECRUITING (Yellow)
    curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_BLACK)  # OFF (Black)
    
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
            if state == "ON":
                stdscr.addch(y, x, 'O', curses.color_pair(1))  # Green for ON
            elif state == "RECRUITING":
                stdscr.addch(y, x, '.', curses.color_pair(2))  # Yellow for RECRUITING
        if not running:
            stdscr.addch(cursor_y, cursor_x, 'X', curses.color_pair(3))  # Black for cursor position

        stdscr.addstr(height, 0, "Press SPACE to toggle cells, S to start, +/- to adjust speed")
        stdscr.addstr(height + 1, 0, "1: Blinker  2: Glider  3: Puffer  4: Brain Spiral")
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
            grid[(cursor_y, cursor_x)] = "ON" if grid.get((cursor_y, cursor_x), "OFF") == "OFF" else "OFF"
        elif key in map(ord, "1234"):
            pattern_name, pattern_cells = PATTERNS[int(chr(key))]
            for dy, dx in pattern_cells:
                grid[(cursor_y + dy, cursor_x + dx)] = "ON"
        elif key == ord('s'):
            save_state({k: v for k, v in grid.items() if v != "OFF"})
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

