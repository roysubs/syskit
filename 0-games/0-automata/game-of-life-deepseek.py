# Author: Roy Wiseman 2025-02
import curses
import time
import sys
import os
from datetime import datetime

# Predefined shapes
SHAPES = {
    '1': 'glider',
    '2': 'blinker',
    '3': 'toad',
    '4': 'beacon',
    '5': 'pulsar'
}

# Define the shapes as lists of (row, col) offsets
SHAPE_DEFINITIONS = {
    'glider': [(0, 1), (1, 2), (2, 0), (2, 1), (2, 2)],
    'blinker': [(0, 0), (0, 1), (0, 2)],
    'toad': [(0, 1), (0, 2), (0, 3), (1, 0), (1, 1), (1, 2)],
    'beacon': [(0, 0), (0, 1), (1, 0), (1, 1), (2, 2), (2, 3), (3, 2), (3, 3)],
    'pulsar': [
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
    ]
}

def create_grid(rows, cols):
    return [[0 for _ in range(cols)] for _ in range(rows)]

def draw_grid(stdscr, grid, cursor_pos, generation, status):
    stdscr.clear()
    rows, cols = len(grid), len(grid[0])
    for row in range(rows):
        for col in range(cols):
            if (row, col) == cursor_pos:
                stdscr.addch(row, col, 'X' if grid[row][col] else ' ')
            else:
                stdscr.addch(row, col, 'o' if grid[row][col] else ' ')
    # Display user info at the bottom
    stdscr.addstr(rows + 1, 0, "Space: Place cell | s: Start | q: Quit | +: Speed up | -: Slow down")
    stdscr.addstr(rows + 2, 0, "1: Glider | 2: Blinker | 3: Toad | 4: Beacon | 5: Pulsar")
    stdscr.addstr(rows + 3, 0, f"Generation: {generation} | Status: {status}")
    stdscr.refresh()

def get_neighbors(grid, row, col):
    rows, cols = len(grid), len(grid[0])
    neighbors = []
    for i in range(-1, 2):
        for j in range(-1, 2):
            if i == 0 and j == 0:
                continue
            r, c = row + i, col + j
            if 0 <= r < rows and 0 <= c < cols:
                neighbors.append(grid[r][c])
    return sum(neighbors)

def update_grid(grid):
    new_grid = create_grid(len(grid), len(grid[0]))
    for row in range(len(grid)):
        for col in range(len(grid[0])):
            neighbors = get_neighbors(grid, row, col)
            if grid[row][col]:
                new_grid[row][col] = 1 if neighbors in [2, 3] else 0
            else:
                new_grid[row][col] = 1 if neighbors == 3 else 0
    return new_grid

def save_grid(grid, filename):
    with open(filename, 'w') as f:
        for row in grid:
            f.write(''.join(map(str, row)) + '\n')

def load_grid(filename):
    with open(filename, 'r') as f:
        grid = [list(map(int, line.strip())) for line in f]
    return grid

def main(stdscr):
    curses.curs_set(1)  # Show cursor
    stdscr.nodelay(0)   # Blocking input
    stdscr.timeout(100) # Refresh rate

    # Get terminal size
    rows, cols = curses.LINES - 4, curses.COLS
    grid = create_grid(rows, cols)
    cursor_pos = [rows // 2, cols // 2]
    generation = 0
    status = "Editing"
    speed = 100  # Refresh rate in ms

    # Load a saved file if provided
    if len(sys.argv) > 1:
        grid = load_grid(sys.argv[1])
        status = "Running"
        generation = 0

    while True:
        draw_grid(stdscr, grid, tuple(cursor_pos), generation, status)
        key = stdscr.getch()

        if status == "Editing":
            if key == curses.KEY_UP and cursor_pos[0] > 0:
                cursor_pos[0] -= 1
            elif key == curses.KEY_DOWN and cursor_pos[0] < rows - 1:
                cursor_pos[0] += 1
            elif key == curses.KEY_LEFT and cursor_pos[1] > 0:
                cursor_pos[1] -= 1
            elif key == curses.KEY_RIGHT and cursor_pos[1] < cols - 1:
                cursor_pos[1] += 1
            elif key == ord(' '):
                grid[cursor_pos[0]][cursor_pos[1]] ^= 1  # Toggle cell
            elif key == ord('s'):
                # Save initial state and start simulation
                filename = f"life-{datetime.now().strftime('%Y%m%d-%H%M%S')}.sav"
                save_grid(grid, filename)
                status = "Running"
            elif key in [ord('1'), ord('2'), ord('3'), ord('4'), ord('5')]:
                # Place predefined shape
                shape = SHAPE_DEFINITIONS[SHAPES[chr(key)]]
                for dr, dc in shape:
                    r, c = cursor_pos[0] + dr, cursor_pos[1] + dc
                    if 0 <= r < rows and 0 <= c < cols:
                        grid[r][c] = 1
            elif key == ord('q'):
                break

        elif status == "Running":
            if key == ord('+'):
                speed = max(10, speed - 10)
                stdscr.timeout(speed)
            elif key == ord('-'):
                speed += 10
                stdscr.timeout(speed)
            elif key == ord('q'):
                break

            new_grid = update_grid(grid)
            if new_grid == grid:
                status = f"Static at generation {generation}"
            else:
                grid = new_grid
                generation += 1

if __name__ == "__main__":
    curses.wrapper(main)
