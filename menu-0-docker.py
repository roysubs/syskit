#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime

LOG_FILE = "/tmp/python_setup_menus.log"

def log_message(message):
    """Log debug messages to a file."""
    with open(LOG_FILE, "a") as log_file:
        log_file.write(f"{datetime.now()}: {message}\n")

def list_scripts(folder, prefix="docker"):
    """List all scripts in the folder starting with the specified prefix."""
    scripts = [
        f for f in os.listdir(folder)
        if f.startswith(prefix) and f.endswith(".sh") and os.path.isfile(os.path.join(folder, f))
    ]
    log_message(f"Scripts found: {scripts}")
    return sorted(scripts)

def read_first_comment(file_path):
    """Read the first meaningful comment line of a script, excluding the shebang."""
    try:
        with open(file_path, "r") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("#") and not stripped.startswith("#!"):
                    return f"\nDescription of {os.path.basename(file_path)}:\n{stripped[1:].strip()}"
        return f"\nDescription of {os.path.basename(file_path)}:\nNo description available."
    except Exception as e:
        log_message(f"Error reading comment from {file_path}: {e}")
        return f"\nDescription of {os.path.basename(file_path)}:\nError reading description."

def display_menu(stdscr, options, script_dir):
    """Display a list of options with checkboxes and show the first comment of selected script."""
    curses.curs_set(0)
    curses.start_color()
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal

    current_row = 0
    current_column = 0  # Track which column the user is in
    checked = [False] * len(options)
    select_all = False  # Track whether all items are selected or not

    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            # Minimum size check
            if height < 10 or width < 40:
                stdscr.addstr(0, 0, "Terminal size too small. Resize and try again.")
                stdscr.refresh()
                time.sleep(1)
                continue

            # Calculate columns and rows
            max_option_width = max(len(option) for option in options) + 4
            num_columns = max(1, width // max_option_width)
            num_rows = (len(options) + num_columns - 1) // num_columns

            # Display the menu in a grid layout
            for idx, option in enumerate(options):
                row = idx % num_rows
                col = idx // num_rows

                x = col * max_option_width
                y = row

                if y < height - 5:  # Ensure within bounds
                    checkbox = "[X]" if checked[idx] else "[ ]"
                    if col == current_column and row == current_row:
                        # Highlight the selected cell
                        stdscr.attron(curses.color_pair(1))
                        stdscr.addstr(y, x, f"{checkbox} {option[:max_option_width-4]}")
                        stdscr.attroff(curses.color_pair(1))
                    else:
                        # Non-selected cells just show normally without modification
                        stdscr.attron(curses.color_pair(2))
                        stdscr.addstr(y, x, f"{checkbox} {option[:max_option_width-4]}")
                        stdscr.attroff(curses.color_pair(2))

            # Display footer and comments
            footer_row = min(height - 3, num_rows + 1)
            stdscr.addstr(footer_row, 0, "Press 'space' to select an item, Ctrl+a to toggle select all, 'x' to execute selected items, or 'q' to quit.", curses.A_BOLD)

            # Display the first comment of the highlighted script
            comment_row = footer_row + 1
            if 0 <= current_column * num_rows + current_row < len(options):
                script_path = os.path.join(script_dir, options[current_column * num_rows + current_row])
                comment = read_first_comment(script_path)
                stdscr.addstr(comment_row, 0, comment[:width-1])

            stdscr.refresh()

            # Handle user input
            key = stdscr.getch()
            if key == curses.KEY_UP:
                current_idx = current_column * num_rows + current_row
                current_idx = (current_idx - 1) % len(options)
                current_row = current_idx % num_rows
                current_column = current_idx // num_rows
            elif key == curses.KEY_DOWN:
                current_idx = current_column * num_rows + current_row
                current_idx = (current_idx + 1) % len(options)
                current_row = current_idx % num_rows
                current_column = current_idx // num_rows
            elif key == curses.KEY_RIGHT:
                current_idx = current_column * num_rows + current_row
                current_idx = (current_idx + num_rows) % len(options)
                current_row = current_idx % num_rows
                current_column = current_idx // num_rows
            elif key == curses.KEY_LEFT:
                current_idx = current_column * num_rows + current_row
                current_idx = (current_idx - num_rows) % len(options)
                current_row = current_idx % num_rows
                current_column = current_idx // num_rows
            # if key == curses.KEY_UP:
            #     current_row = (current_row - 1) % num_rows
            # elif key == curses.KEY_DOWN:
            #     current_row = (current_row + 1) % num_rows
            # elif key == curses.KEY_RIGHT and current_column < num_columns - 1:
            #     current_column += 1
            #     current_row = min(current_row, (len(options) - 1) % num_rows)
            # elif key == curses.KEY_LEFT and current_column > 0:
            #     current_column -= 1
            #     current_row = min(current_row, (len(options) - 1) % num_rows)
            elif key == ord(" "):  # Toggle checkbox
                idx = current_column * num_rows + current_row
                if 0 <= idx < len(options):
                    checked[idx] = not checked[idx]
            elif key == 1:  # Ctrl+a to toggle select all
                select_all = not select_all
                checked = [select_all] * len(options)
            elif key == ord("x"):  # Execute selected scripts
                return [options[i] for i, is_checked in enumerate(checked) if is_checked]
            elif key == ord("q"):  # Quit without running scripts
                return None

        except curses.error as e:
            log_message(f"Curses error: {e}")
            pass

def run_scripts(script_dir, selected_scripts):
    """Run the selected scripts interactively in order with streaming output and timing."""
    script_start_times = {}
    overall_start_time = time.time()

    for script in selected_scripts:
        script_path = os.path.join(script_dir, script)
        start_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        script_start_times[script] = start_time

        print("-" * 40)
        print(f"Starting: {start_time} - {script}")
        print("-" * 40)

        try:
            # Determine if the script contains "nosudo"
            with open(script_path, "r") as f:
                nosudo = "nosudo" in f.read()

            # Run with or without sudo based on "nosudo"
            if nosudo:
                subprocess.run([script_path], check=True)
            else:
                subprocess.run(["sudo", script_path], check=True)

        except subprocess.CalledProcessError as e:
            print(f"Script {script} failed with error code {e.returncode}")
        except FileNotFoundError:
            print(f"Error: Script not found: {script_path}")
        except PermissionError:
            print(f"Error: Script not executable: {script_path}")
        except OSError as e:
            print(f"OS Error: {e}\nCheck if {script_path} has a valid shebang and is executable.")

    overall_end_time = time.time()

    # Summary and total runtime
    print("-" * 40)
    print("Execution Summary:")
    for script, start_time in script_start_times.items():
        print(f"{start_time} - {script}")
    final_end_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{final_end_time} - Finished running scripts")
    total_runtime = overall_end_time - overall_start_time
    print(f"Total runtime: {total_runtime:.2f} seconds.")

def main():
    def signal_handler(sig, frame):
        print("\nProgram terminated by user.")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    script_dir = os.path.expanduser("~/syskit/0-docker")
    scripts = list_scripts(script_dir)

    if not scripts:
        print("No scripts found in the directory.")
        return

    try:
        selected_scripts = curses.wrapper(lambda stdscr: display_menu(stdscr, scripts, script_dir))
        if selected_scripts is None:
            print("No scripts were selected.")
        else:
            print("The following scripts will be executed in order:")
            for script in selected_scripts:
                print(f"- {script}")
            input("\nPress Enter to start execution...")
            print("\nExecuting selected scripts...\n")
            run_scripts(script_dir, selected_scripts)

    except Exception as e:
        log_message(f"Unhandled exception: {e}")
        print("An error occurred. Check the log file for details.")

if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    log_message(f"Starting {script_name} script.")
    main()
    log_message(f"Script {script_name} finished.")
