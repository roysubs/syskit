#!/bin/bash
# Author: Roy Wiseman 2025-02

# Purpose of this script:
# Alter the variables for customisation and the display usage information
# Use this to download and enable a github project for use on this system
# Work in progress.

# Variables for customisation
PROJECT_NAME="bash-life"
PROJECT_URL="https://github.com/szantaii/bash-life"
INSTALL_DIR="/opt/$PROJECT_NAME"
SYMLINK_PATH="/usr/local/bin/$PROJECT_NAME"
SYMLINK_TARGET="$INSTALL_DIR/$PROJECT_NAME.sh"

# Step 1: Clone the repository if it doesn’t exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Cloning $PROJECT_NAME repository into $INSTALL_DIR..."
    sudo git clone "$PROJECT_URL" "$INSTALL_DIR"
    sudo chmod +x "$INSTALL_DIR"/*.sh
else
    echo "$PROJECT_NAME is already installed at $INSTALL_DIR. Skipping cloning step."
fi

# Step 2: Create symbolic link
if [ ! -L "$SYMLINK_PATH" ]; then
    echo "Creating symbolic link at $SYMLINK_PATH..."
    sudo ln -s "$SYMLINK_TARGET" "$SYMLINK_PATH"
    sudo chmod +x "$SYMLINK_PATH"
else
    echo "Symbolic link at $SYMLINK_PATH already exists. Skipping this step."
fi

# Step 3: Display usage information
clear
cat << "EOF"
Welcome to Bash Life - Conway's Game of Life
--------------------------------------------
Move around the area with the cursor keys, space to place an 'o' in as many locations as required, then 's' to start, and 'q' to quit.

Famous Objects in Conway's Life:

1. Glider:
A small pattern that travels diagonally across the board.
  o
   o
 ooo

2. Lightweight Spaceship (LWSS):
A larger pattern that travels horizontally or vertically.
 o  o
     o
 o   o
  ooo

3. Blinker:
An oscillator that alternates between two states.
State 1:   ooo
State 2:    o
            o
            o

4. Toad:
Another oscillator that alternates between two states.
State 1:   ooo
           ooo
State 2:    o
           o o
            o

5. Pulsar:
A larger oscillator that alternates between three states.
State 1:
    ooo   ooo

  o    o o    o
  o    o o    o
  o    o o    o

    ooo   ooo


Rules of Conway's Life:
-----------------------
1. Any live cell with fewer than two live neighbors dies (underpopulation).
2. Any live cell with two or three live neighbors lives on to the next generation.
3. Any live cell with more than three live neighbors dies (overpopulation).
4. Any dead cell with exactly three live neighbors becomes a live cell (reproduction).

Press any key to start the Game of Life!
EOF

# Wait for user input
read -n 1 -s

# Change to the repository directory and start the game
cd "$INSTALL_DIR" || exit
./$PROJECT_NAME.sh

