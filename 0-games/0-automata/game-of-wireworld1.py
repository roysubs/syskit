#!/usr/bin/env python3
# Author: Roy Wiseman 2025-05

# Wireworld Cellular Automaton

# Wireworld (Rule Set)
# Philosophy: A cellular automaton designed to model electronic circuits. It's a more practical ruleset compared to the abstract nature of others like Life.
# Rules:
# Cells can be in four states: Empty, Wire, Electron Head, and Electron Tail.
# - Electron Head (H) becomes Electron Tail (T).
# - Electron Tail (T) becomes Empty ( ).
# - Wire (W) becomes Electron Head (H) if it has 1 or 2 neighbors that are Electron Heads (H). Otherwise, it remains Wire (W).
# - Empty ( ) remains Empty ( ).
# Behavior: Wireworld can simulate logic gates, including AND, OR, and NOT gates, and can even perform basic computations.
# Philosophy Behind the Rules: Wireworld's goal is to model real-world processes like circuits and logic operations, showing that logical computation can emerge from simple, local interactions within a grid.

import curses
import time
import datetime
import json
import sys

# Cell States
EMPTY = ' '
WIRE = 'W'
HEAD = 'H'
TAIL = 'T'

# Preset Wireworld Patterns (relative coordinates and state)
# For simplicity, patterns initially place only wires. User can add heads.
PATTERNS = {
    1: ("Straight Wire", [(0, 0), (0, 1), (0, 2), (0, 3)]),
    2: ("Corner", [(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)]),
    3: ("T-Junction", [(0, 1), (1, 0), (1, 1), (1, 2), (2, 1)]),
    4: ("Diode (Wires only)", [(0,0),(0,1),(0,2),(1,1),(2,1),(2,0),(2,2)]), # Basic wire structure for a diode
}

def save_state(grid):
    """Saves the current non-empty grid state to a JSON file."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"wireworld-{timestamp}.sav"
    # Only save non-empty cells
    state_to_save = {f"{k[0]},{k[1]}": v for k, v in grid.items() if v != EMPTY}
    with open(filename, "w") as f:
        json.dump(state_to_save, f)
    return filename

def load_state(filename):
    """Loads grid state from a JSON file."""
    try:
        with open(filename, "r") as f:
            loaded_data = json.load(f)
            # Convert string keys back to tuple keys
            return {tuple(map(int, k.split(','))): v for k, v in loaded_data.items()}
    except FileNotFoundError:
        return {} # Return empty grid if file not found
    except json.JSONDecodeError:
        return {} # Return empty grid if JSON is invalid

def get_neighbors(y, x, height, width):
    """Returns coordinates of the 8 neighbors, handling wrapping."""
    return [((y + dy) % height, (x + dx) % width)
            for dy in [-1, 0, 1] for dx in [-1, 0, 1] if (dy, dx) != (0, 0)]

def step(grid, height, width):
    """Calculates the next generation of the Wireworld grid."""
    new_grid = {}
    
    # Iterate through all possible cells in the grid bounds
    # This is simpler than tracking only 'active' cells for Wireworld
    for y in range(height):
        for x in range(width):
            pos = (y, x)
            current_state = grid.get(pos, EMPTY) # Default to EMPTY if cell not in grid dict

            if current_state == HEAD:
                new_grid[pos] = TAIL
            elif current_state == TAIL:
                new_grid[pos] = EMPTY
            elif current_state == EMPTY:
                new_grid[pos] = EMPTY # Empty cells always stay empty
            elif current_state == WIRE:
                head_neighbors = 0
                for ny, nx in get_neighbors(y, x, height, width):
                    if grid.get((ny, nx), EMPTY) == HEAD:
                        head_neighbors += 1

                if head_neighbors == 1 or head_neighbors == 2:
                    new_grid[pos] = HEAD
                else:
                    new_grid[pos] = WIRE # Wire stays wire

    # Clean up the new_grid by removing EMPTY entries to keep it sparse
    return {k: v for k, v in new_grid.items() if v != EMPTY}


def get_cell_display(state):
    """Returns the character and color pair ID for a cell state."""
    if state == WIRE:
        return 'W', 1 # White
    elif state == HEAD:
        return 'H', 2 # Yellow
    elif state == TAIL:
        return 'T', 3 # Red
    else: # EMPTY
        return ' ', 4 # Black (background)

def main(stdscr):
    """Main curses application function."""
    curses.curs_set(0) # Hide cursor
    stdscr.nodelay(1)  # Make getch non-blocking
    stdscr.timeout(100) # Wait 100ms for input if no key pressed

    # Initialize color pairs
    curses.start_color()
    # Pair IDs:    Fg Color, Bg Color
    curses.init_pair(1, curses.COLOR_WHITE, curses.COLOR_BLACK)  # WIRE (White)
    curses.init_pair(2, curses.COLOR_YELLOW, curses.COLOR_BLACK) # HEAD (Yellow)
    curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # TAIL (Red)
    curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_BLACK)  # EMPTY (Black)
    curses.init_pair(5, curses.COLOR_CYAN, curses.COLOR_BLACK)   # Cursor/UI (Cyan)


    height, width = stdscr.getmaxyx()
    # Reserve space at the bottom for UI messages
    grid_height = height - 4
    grid_width = width

    cursor_y, cursor_x = grid_height // 2, grid_width // 2
    grid = {}
    speed = 0.1 # Seconds per generation
    running = False
    # history = [] # History can consume a lot of memory for large grids/long runs
    generation = 0

    # State to place when pressing Space/Enter
    current_place_state = WIRE
    place_states_cycle = [WIRE, HEAD, TAIL, EMPTY] # Cycle order

    # Load initial state from command line arg if provided
    if len(sys.argv) > 1:
        loaded_grid = load_state(sys.argv[1])
        if loaded_grid:
            grid = loaded_grid
            # Check if the loaded grid requires adjustment for screen size?
            # For simplicity here, assume it fits or curses will handle clipping.
            # Auto-start if a file was loaded? Brian's Brain did, let's follow.
            running = True
        else:
            # Print error message outside curses if load failed
            print(f"Error loading file: {sys.argv[1]}", file=sys.stderr)
            sys.exit(1)


    while True:
        stdscr.clear()

        # Draw the grid
        for (y, x), state in grid.items():
            # Ensure cell is within visible grid bounds before drawing
            if 0 <= y < grid_height and 0 <= x < grid_width:
                 char, color_pair_id = get_cell_display(state)
                 stdscr.addch(y, x, char, curses.color_pair(color_pair_id))

        # Draw cursor if not running
        if not running:
             # Ensure cursor is within visible grid bounds
            if 0 <= cursor_y < grid_height and 0 <= cursor_x < grid_width:
                stdscr.addch(cursor_y, cursor_x, 'X', curses.color_pair(5)) # Cyan cursor

        # Draw UI
        stdscr.addstr(grid_height, 0, "--- Wireworld Controls ---", curses.color_pair(5))
        stdscr.addstr(grid_height + 1, 0, "Arrows: Move | SPACE: Cycle Place State | ENTER: Place/Erase", curses.color_pair(5))
        stdscr.addstr(grid_height + 2, 0, "r: Run/Pause | s: Save | +/-: Speed | q: Quit", curses.color_pair(5))
        stdscr.addstr(grid_height + 3, 0, f"Placing: {current_place_state} | Gen: {generation} | Speed: {speed:.2f}s", curses.color_pair(5))

        # Draw pattern options
        pattern_line = grid_height + 4
        if pattern_line < height:
             pattern_str = "Patterns: " + " | ".join([f"{num}: {name}" for num, (name, cells) in PATTERNS.items()])
             stdscr.addstr(pattern_line, 0, pattern_str[:grid_width-1], curses.color_pair(5)) # Truncate if too long

        stdscr.refresh()

        # Get user input
        key = stdscr.getch()

        # Handle input when NOT running
        if not running:
            if key == curses.KEY_UP and cursor_y > 0:
                cursor_y -= 1
            elif key == curses.KEY_DOWN and cursor_y < grid_height - 1:
                cursor_y += 1
            elif key == curses.KEY_LEFT and cursor_x > 0:
                cursor_x -= 1
            elif key == curses.KEY_RIGHT and cursor_x < grid_width - 1:
                cursor_x += 1
            elif key == ord(' '): # Cycle place state
                try:
                    current_index = place_states_cycle.index(current_place_state)
                    next_index = (current_index + 1) % len(place_states_cycle)
                    current_place_state = place_states_cycle[next_index]
                except ValueError:
                    # Should not happen if current_place_state is always in the list
                    current_place_state = place_states_cycle[0]
            elif key == curses.KEY_ENTER or key == 10: # Place/Erase
                 if current_place_state == EMPTY:
                     if (cursor_y, cursor_x) in grid:
                         del grid[(cursor_y, cursor_x)]
                 else:
                     grid[(cursor_y, cursor_x)] = current_place_state
            elif key in map(ord, "1234"): # Place patterns
                pattern_num = int(chr(key))
                if pattern_num in PATTERNS:
                    pattern_name, pattern_cells = PATTERNS[pattern_num]
                    for dy, dx in pattern_cells:
                        # Place pattern cells relative to cursor, ensuring they are Wires
                        py, px = cursor_y + dy, cursor_x + dx
                        # Only place if within grid bounds
                        if 0 <= py < grid_height and 0 <= px < grid_width:
                             grid[(py, px)] = WIRE # Patterns place only wires
            elif key == ord('s'): # Save state
                 filename = save_state({k: v for k, v in grid.items() if v != EMPTY})
                 # Display save confirmation message briefly
                 stdscr.addstr(height - 1, 0, f"State saved to {filename}", curses.color_pair(5))
                 stdscr.refresh()
                 time.sleep(1) # Show message for 1 second

        # Handle input regardless of running state
        if key == ord('r'): # Toggle Run/Pause
             running = not running
             if running:
                  # Optionally reset generation count or history when starting
                  # history = []
                  pass
        elif key == ord('+'): # Increase speed (decrease sleep time)
             speed = max(0.01, speed - 0.02)
        elif key == ord('-'): # Decrease speed (increase sleep time)
             speed += 0.02
        elif key == ord('q'): # Quit
             break

        # Simulation Step (only if running)
        if running:
            # history.append(grid.copy()) # Optional: Keep history for repetition check
            generation += 1
            new_grid = step(grid, grid_height, grid_width)

            # Check if simulation has become static (no heads or tails)
            has_electrons = any(state in [HEAD, TAIL] for state in new_grid.values())
            if not has_electrons and grid and new_grid: # Was not empty, now has no electrons
                 stdscr.addstr(height - 1, 0, f"Simulation became static at generation {generation}.", curses.color_pair(5))
                 stdscr.refresh()
                 running = False # Auto-pause when static

            # Optional: Check for repetition (can be slow/memory intensive)
            # if new_grid in history:
            #      stdscr.addstr(height - 1, 0, f"Reached repeating shape at generation {generation}", curses.color_pair(5))
            #      stdscr.refresh()
            #      running = False # Auto-pause on repeat

            grid = new_grid
            time.sleep(speed) # Wait before next step

        # If not running, wait for a short period to avoid busy-waiting on getch()
        if not running:
             time.sleep(0.01)


if __name__ == "__main__":
    # If a filename is provided as a command line argument, try to load it
    if len(sys.argv) > 1:
         # Curses wrapper handles initialization/deinitialization
         curses.wrapper(main)
    else:
        # If no file is provided, start with an empty grid (wrapper handles init)
         curses.wrapper(main)
