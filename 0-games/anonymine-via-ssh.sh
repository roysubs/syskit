#!/bin/bash
# Author: Roy Wiseman 2025-02

# --- Configuration ---
SSH_USER="play"
SSH_HOST="anonymine-demo.oskog97.com"
SSH_PORT="2222"
PASSWORD_HINT="play"

# --- Display Information ---

echo "=================================================="
echo "Welcome to anonymine!"
echo "=================================================="
echo ""
echo "Understanding Game Types (Neighborhoods):"
echo "-----------------------------------------"
echo "In grid-based games like this, 'neighborhoods' define which cells"
echo "are considered 'adjacent' when calculating things like the number of"
echo "mines around a cell."
echo ""
echo " - Neumann: Checks only the four orthogonally adjacent cells (up, down, left, right)."
echo "            Think of it like a plus sign (+) shape."
echo " - Hexagonal: Checks the six adjacent cells in a hexagonal grid layout."
echo " - Moore:   Checks all eight adjacent cells (including diagonals)."
echo "            This is the standard for classic Minesweeper."
echo "            Think of it like a 3x3 square around the cell."
echo ""
echo "You can quit the game inside the SSH session with the interrupt signal (Ctrl + c)."
echo ""
echo "Once connected, you will be prompted with these options:"
echo "Game types:"
echo "  A: Neumann (no diagonals), B: Hexagonal, C: Moore (normal)"
echo "  Defaults to C"
echo "Difficulties:"
echo "  1: Easy, 2: Medium, 3: Default, 4: Hard, 5: Ultra, 6: Custom"
echo "  Defaults to 3"
echo "Polite mode? [No]:"
echo "Show key bindings? [No]:"
echo ""
echo "Key Bindings (Informational - Displayed after connecting if enabled):"
echo "-----------------------------------------------------------------------"
echo "  - Press f (or r, t or g) or tab to place or remove a flag on a cell."
echo "  - Press space or enter to reveal (click on) a cell."
echo "  - Type ? to find difficult to find cells. Press again to deactivate attention mode."
echo "  - Shift-q or Control-c to quit."
echo "  - Pressing an unrecognised key will refresh the screen."
echo ""
echo "  In the traditional and von Neumann modes, you can steer with the arrow"
echo "  keys, wasd, the numpad or hjklyubn."
echo "  You can also (probably) use the mouse, but it's really finicky."
echo "-----------------------------------------------------------------------"
echo ""
echo "Once connected, use password 'play' to start."
echo ""
# --- Wait for user input to connect ---
echo "Press any key to connect to anonymine-demo.oskog97.com..."
read -n 1 -s   # Read one character silently (-n 1 -s)
echo ""

# --- Execute the SSH command ---
echo "Connecting..."
ssh "$SSH_USER"@"$SSH_HOST" -p "$SSH_PORT"

# --- End of script ---
echo ""
echo "Connection closed."
