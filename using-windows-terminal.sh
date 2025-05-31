#!/bin/bash
# Author: Roy Wiseman 2025-04
command -v mdcat &>/dev/null || "${0%/*}/mdcat-get.sh"; hash -r
command -v mdcat &>/dev/null || { echo "Error: mdcat required but not available." >&2; exit 1; }
WIDTH=$(if [ $(tput cols) -ge 105 ]; then echo 100; else echo $(( $(tput cols) - 5 )); fi)
mdcat --columns="$WIDTH" <(cat <<'EOF'

# Windows Terminal Shortcuts Cheatsheet

A comprehensive guide to keyboard shortcuts for Windows Terminal.

## General Application & Window Management

* **`Ctrl + ,`**: Open Settings (JSON file)
* **`Ctrl + Shift + P`**: Open the Command Palette (searchable list of all commands)
* **`Alt + F4`**: Close the active window
* **`F11` or `Alt + Enter`**: Toggle full-screen mode
* **`Ctrl + Shift + F`**: Open the search dialog within the terminal
* **`Ctrl + Shift + Space`**: Open the profile dropdown menu
* **`Ctrl + Scroll Wheel (Mouse)`**: Zoom in/out font size
* **`Ctrl + +` (plus key)**: Increase font size
* **`Ctrl + -` (minus key)**: Decrease font size
* **`Ctrl + 0` (zero key)**: Reset font size to default

## Tab Management

* **`Ctrl + Shift + T`**: Open a new tab (default profile)
* **`Ctrl + Shift + W`**: Close the current tab (or pane if active, or window if last tab)
* **`Ctrl + Tab`**: Switch to the next tab
* **`Ctrl + Shift + Tab`**: Switch to the previous tab
* **`Ctrl + Shift + D`**: Duplicate the current tab
* **`Ctrl + Alt + [1-9]`**: Switch to tab number 1-9
* **`Ctrl + Shift + [1-9]`**: Open a new tab with the profile at that index

## Pane Management (Splitting the Terminal Window)

* **`Alt + Shift + -` (minus key)**: Split pane horizontally (default profile)
* **`Alt + Shift + +` (plus key)**: Split pane vertically (default profile)
* **`Alt + Shift + D`**: Split pane using the active profile
* **`Alt + Arrow Keys (Up/Down/Left/Right)`**: Move focus between panes
* **`Alt + Shift + Arrow Keys (Up/Down/Left/Right)`**: Resize the focused pane
* **`Ctrl + Shift + W`**: Close the focused pane (if not the last pane in a tab)

## Copy & Paste

* **`Ctrl + C` or `Ctrl + Insert`**: Copy selected text (sends `Ctrl+C` interrupt if no selection)
* **`Ctrl + V` or `Shift + Insert`**: Paste text
* **`Ctrl + Shift + C`**: Force copy selected text
* **`Ctrl + Shift + V`**: Force paste text

## Scrolling & Navigation within the Terminal Buffer

* **`Ctrl + Shift + Up Arrow`**: Scroll up one line
* **`Ctrl + Shift + Down Arrow`**: Scroll down one line
* **`Ctrl + Shift + Page Up`**: Scroll up one page
* **`Ctrl + Shift + Page Down`**: Scroll down one page
* **`Ctrl + Home`**: Scroll to the top of the buffer
* **`Ctrl + End`**: Scroll to the bottom of the buffer

## Shell-Specific Shortcuts
*(Handled by the shell like PowerShell, CMD, Bash, etc., running inside the terminal)*

* **`Ctrl + L`**: Clear the screen (common in PowerShell, Bash)
* **`Up Arrow / Down Arrow`**: Navigate command history
* **`Tab`**: Autocomplete commands or file/directory names
* **`Ctrl + R`**: Reverse search command history (Bash, PowerShell with PSReadLine)
* **`Ctrl + C`**: Interrupt/cancel the current running command
* **`Ctrl + D`**: Send EOF (End Of File); can close shells or exit programs

## Important Notes

* **Customization:** Most key bindings can be changed in `settings.json` (`Ctrl + ,`).
* **Default Profile:** "New tab" or "split pane" actions often use the default profile.
* **Focus:** Shortcuts apply to the currently focused pane or tab.
* **Shell vs. Terminal:** Distinguish between shortcuts for the Terminal app and those for the shell running inside it.

EOF
) | less -R
