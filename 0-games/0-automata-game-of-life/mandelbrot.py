#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
import curses
import time

# ASCII characters to represent different levels of iteration depth
ASCII_CHARS = [' ', '.', ':', '-', '=', '+', '*', '#', '%', '@']

def mandelbrot(c, max_iter):
    z = complex(0, 0)
    for n in range(max_iter):
        z = z*z + c
        if abs(z) > 2:
            return n
    return max_iter

def draw_fractal(stdscr, width, height, zoom, x_offset, y_offset, max_iter=100):
    # Map screen coordinates to the complex plane
    min_x, max_x = -2.0 / zoom + x_offset, 1.0 / zoom + x_offset
    min_y, max_y = -1.5 / zoom + y_offset, 1.5 / zoom + y_offset

    for y in range(height):
        for x in range(width):
            # Map pixel position to a point in the complex plane
            real = min_x + (max_x - min_x) * x / width
            imag = min_y + (max_y - min_y) * y / height
            c = complex(real, imag)

            # Calculate the number of iterations for this point
            m = mandelbrot(c, max_iter)

            # Use the iteration count to select an ASCII character
            char = ASCII_CHARS[int(m / max_iter * (len(ASCII_CHARS) - 1))]

            # Set color based on iteration depth
            color = int(m / max_iter * 7)  # 8 color levels

            # Display the character at the corresponding position
            stdscr.addstr(y, x, char, curses.color_pair(color))

def main(stdscr):
    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(0)

    # Initialize color pairs
    for i in range(8):
        curses.init_pair(i + 1, i, curses.COLOR_BLACK)

    height, width = stdscr.getmaxyx()
    max_iter = 100  # Max iterations for Mandelbrot calculation
    zoom = 1.0  # Initial zoom level
    x_offset, y_offset = -0.5, 0.0  # Center of the fractal

    while True:
        stdscr.clear()

        # Draw the fractal on the screen
        draw_fractal(stdscr, width, height - 4, zoom, x_offset, y_offset, max_iter)

        # Display instructions
        stdscr.addstr(height - 4, 0, "Zoom with + and - | Arrow keys to move | q to quit")
        stdscr.addstr(height - 3, 0, f"Zoom: {zoom:.2f} | Offset: ({x_offset:.2f}, {y_offset:.2f})")
        stdscr.refresh()

        key = stdscr.getch()

        if key == ord('q'):
            break
        elif key == ord('+'):
            zoom *= 4  # Zoom in by a factor of 4
        elif key == ord('-'):
            zoom /= 4  # Zoom out by a factor of 4
        elif key == curses.KEY_UP:
            y_offset += 0.1 / zoom  # Move up
        elif key == curses.KEY_DOWN:
            y_offset -= 0.1 / zoom  # Move down
        elif key == curses.KEY_LEFT:
            x_offset += 0.1 / zoom  # Move left
        elif key == curses.KEY_RIGHT:
            x_offset -= 0.1 / zoom  # Move right

        time.sleep(0.1)  # Pause to prevent excessive CPU usage

if __name__ == "__main__":
    curses.wrapper(main)

