#!/bin/bash
# Author: Roy Wiseman 2025-03

### Notes to integrate at some point ###
# Need to talk about ALT+Mouse drag and other things like that - it selects a box etc
# By default, in terminal:
# Ctrl+Shift+c to copy selected text into clipboard
# Ctrl+Shift+v to paste from clipboard into a terminal
# If not, Terminal preferences are usually in right-click inside the terminal, then Preferences or Settings, or in the menu bar Edit > Preferences.
# Look for the Shortcuts section and ensure "Paste" is mapped to Ctrl+Shift+V.


# This will mimic Ctrl+L to quick-clear the screen *without* removing history
# This may not work in GNOME terminal
softclear() { printf '\033[H\033[2J'; }
# However, it is better to just use this:   clear -x

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
echo
softclear

# Function to wait for user input
press_any_key() {
    echo -e "${YELLOW}\nPress any key to continue...${NC}"
    # Use read -n 1 -s -r without the explicit prompt in the read command
    read -n 1 -s -r
    echo "" # Add a newline after the key press
}

# Function to display a section
display_section() {
    local title="$1"
    local content="$2" # This variable now holds the entire multi-line content

    # clear # Clear the screen for each section (optional, uncomment if desired)
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${CYAN}${title}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    # Use echo -e to interpret the newlines and colors in the content variable
    echo -e "${content}"
    press_any_key
    softclear
}

# --- Section 1: Basics and Windows Terminal Tabs and Splits ---

intro_content="A quick refresher on useful features of Windows Terminal when connecting
via SSH to Linux systems, with buffers/pasting (and tools like xclip),
tiling (and pros and cons Windows Terminal tiles vs tmux).

Windows Terminal allows you to manage multiple connections or shells
in one window.
1.  ${GREEN}Basics:${NC}
    - ${YELLOW}Ctrl-+${NC} Zoom Increase / ${YELLOW}Ctrl--${NC} Zoom Decrease
    - ${YELLOW}Ctrl-,${NC} / ${YELLOW}Ctrl+Tab${NC} Open Windows Terminal Settings
    - ${YELLOW}Ctrl-Tab${NC} or ${YELLOW}Ctrl-Page Up/Down${NC} Navigate between tabs
    - ${YELLOW}Ctrl-Alt-[number]${NC} Jump to a specific tab (1-9)
2.  ${GREEN}Tabs:${NC}
    - ${YELLOW}Ctrl-Shift-T${NC} Open a new tab (will be PowerShell unless
      defaults have changed)
    - ${YELLOW}Ctrl-Shift-W${NC} Close the current tab
    - ${YELLOW}Ctrl-Tab${NC} or ${YELLOW}Ctrl-Page Up/Down${NC} Navigate between tabs
    - ${YELLOW}Ctrl-Alt-[number]${NC} Jump to a specific tab (1-9)

3.  ${GREEN}Splits (Panes):${NC}
    - ${YELLOW}Alt-Shift-+${NC} or ${YELLOW}Alt-Shift-D${NC} Split the current pane
      horizontally
    - ${YELLOW}Alt-Shift--${NC} Split the current pane vertically
    - ${YELLOW}Alt-Arrow Keys${NC} Navigate between panes (Up, Down, Left,
      Right) (or just mouse click on the pane to focus)
    - ${YELLOW}Ctrl-Shift-W${NC} Close the current pane
    - ${YELLOW}Alt-Shift-Arrow Keys${NC} Resize panes
    - ${YELLOW}Alt-Shift-L${NC} Switch to layout mode (for more complex pane
      management) (Then use Arrow Keys and Enter)

Note: An advantage of Windows Terminal splits over tmux is that it is fully mouse aware
at all times (not just when in mouse mode like tmux); just move the over a pan and key-
presses will go to that pane (and no mouse-click is required to change pane as in tmux).
This is very useful for diff compares etc.

Using splits is great for:
-   Running a command in one pane while editing a file in another.
-   Monitoring logs in one pane while working elsewhere.
-   Having multiple SSH sessions open side-by-side."

display_section \
"Windows Terminal Basics, and Tabs/Splits" \
"$intro_content"

# --- Section 2: Copy and Paste ---

section2_content="\
Copying and pasting text is straightforward.

1.  ${GREEN}Mouse Selection:${NC}
    -   ${YELLOW}Left mouse button click and drag${NC} to select text.
    -   Selected text is ${YELLOW}automatically copied to the Windows clipboard
      by default${NC} in Windows Terminal.

2.  ${GREEN}Keyboard Shortcuts:${NC}
    -   ${YELLOW}Ctrl-Shift-C${NC} Copy selected text to clipboard
    -   ${YELLOW}Ctrl-Shift-V${NC} Paste from clipboard

Note: This will copy/paste text to/from the Windows clipboard. This
distinction is important when working in tools like vim or nano where they
have their own separate buffers.

Note: ${YELLOW}Ctrl-C${NC} is typically used in the terminal to send an interrupt
signal (like stopping a running command). Avoid using it for copying
unless you specifically configure your terminal.

This method works directly with the Windows clipboard without needing extra
Linux tools for basic text selection."

display_section \
"Copy and Paste in Windows Terminal" \
"$section2_content"

# --- Section 3: tmux: Terminal Multiplexer ---

section3_content="\
${GREEN}tmux${NC} (Terminal Multiplexer) is a powerful tool that runs ${YELLOW}on the remote Linux server${NC}. It allows you to create,
manage, and detach from sessions containing multiple windows and panes, even if your SSH connection is interrupted.

${YELLOW}Key Concept:${NC} tmux sessions persist on the server. You can start a long process, detach from tmux,
close your SSH connection, and reattach later to find your process still running and your layout intact.

1.  ${GREEN}Basic Usage:${NC}
    -   ${YELLOW}tmux${NC} Start a new session
    -   ${YELLOW}tmux new -s mysession${NC} Start a named session
    -   ${YELLOW}tmux ls${NC} List sessions
    -   ${YELLOW}tmux attach${NC} Attach to the last session
    -   ${YELLOW}tmux attach -t mysession${NC} Attach to a named session
    -   ${YELLOW}Prefix Key, then d${NC} Detach from the current session

2.  ${GREEN}tmux Panes (Splits):${NC}
    -   Most tmux commands are invoked by pressing a ${YELLOW}Prefix Key${NC} first, followed by a command key.
    -   The ${MAGENTA}default Prefix Key is Ctrl-B${NC}. Press and release Ctrl-B, then press the command key.
    -   ${YELLOW}Prefix %${NC} Split the current pane ${GREEN}horizontally${NC}.
    -   ${YELLOW}Prefix \"${NC} Split the current pane ${GREEN}vertically${NC}.
    -   ${YELLOW}Prefix Arrow Key${NC} Navigate to the pane in that direction (Up/Down/Left/Right).
    -   ${YELLOW}Prefix z${NC} Zoom pane (toggle maximize/restore).
    -   ${YELLOW}Prefix x${NC} Close the current pane. (Requires confirmation)

3.  ${GREEN}tmux Windows:${NC}
    -   ${YELLOW}Prefix c${NC} Create a new window.
    -   ${YELLOW}Prefix w${NC} List windows (select with arrow keys and Enter).
    -   ${YELLOW}Prefix [number]${NC} Switch to window number [number] (e.g., Prefix 0, Prefix 1).
    -   ${YELLOW}Prefix n${NC} Go to the next window.
    -   ${YELLOW}Prefix p${NC} Go to the previous window.
"
display_section \
"tmux: Terminal Multiplexer" \
"$section3_content"

# --- Section 4: Comparison: tmux vs. Windows Terminal Splits ---

section4_content="\
Both tmux and Windows Terminal (WT) Splits let you have multiple views,
but they operate fundamentally differently:

1.  ${GREEN}Where they Run:${NC}
    -   ${YELLOW}tmux:${NC} Runs entirely on the ${MAGENTA}remote Linux server${NC}. Your
      session lives there.
    -   ${YELLOW}WT Splits:${NC} Managed by the ${MAGENTA}local Windows Terminal
      application${NC}. Each split is typically a separate local process (like
      a separate SSH connection).

2.  ${GREEN}Session Persistence:${NC}
    -   ${GREEN}tmux Advantages:${NC} Sessions ${YELLOW}persist${NC} even if your local
      machine reboots or your SSH connection drops. You can detach and
      reattach later from the same or a different client. Ideal for long-
      running jobs.
    -   ${YELLOW}WT Splits Disadvantages:${NC} If Windows Terminal closes or
      your Windows machine reboots, all your SSH connections in splits are
      ${YELLOW}lost${NC}.

3.  ${GREEN}Connectivity & Performance:${NC}
    -   ${GREEN}tmux Advantages:${NC} Once attached, navigating panes/windows
      is fast as it's server-side. You only have ${YELLOW}one SSH connection${NC} per
      tmux session.
    -   ${YELLOW}WT Splits Disadvantages:${NC} Each split requires a ${YELLOW}separate
      SSH connection${NC} and process running on your local machine, potentially
      using more local resources and connection overhead if you have many
      splits/tabs.

4.  ${GREEN}Clipboard Integration:${NC}
    -   ${YELLOW}tmux Disadvantages:${NC} Copy/paste within tmux uses tmux's
      internal buffer. Getting text to/from the Windows clipboard often
      requires extra steps (like using mouse selection anyway, or
      configuring tmux's copy-mode to interact with xclip/pbcopy if X11
      forwarding or other mechanisms are set up).
    -   ${GREEN}WT Splits Advantages:${NC} Native ${YELLOW}Ctrl-Shift-C${NC}/${YELLOW}Ctrl-Shift-V${NC}
      and mouse selection work directly with the Windows clipboard across
      all panes/tabs effortlessly.

5.  ${GREEN}Setup & Learning Curve:${NC}
    -   ${YELLOW}tmux Disadvantages:${NC} Requires installation and configuration
      on the ${MAGENTA}remote server${NC}. Has its own set of prefix-key shortcuts
      to learn.
    -   ${GREEN}WT Splits Advantages:${NC} Configuration is done locally in
      Windows Terminal settings. Uses more familiar local shortcut
      patterns.

${CYAN}When to use which?:${NC}

-   Use ${YELLOW}Windows Terminal Splits${NC} for:
    -   Having multiple independent SSH sessions open side-by-side for
      quick access or monitoring.
    -   Working across different servers simultaneously.
    -   When easy, native Windows clipboard copy/paste is a priority.
    -   When you don't need sessions to survive connection drops or local
      reboots.

-   Use ${GREEN}tmux${NC} (inside a single WT tab/pane) for:
    -   Running long-duration tasks on the server that you might want to
      detach from.
    -   Maintaining complex multi-pane layouts for a specific project or
      task on one server, even if you disconnect.
    -   When session persistence across connections/reboots is essential.
    -   If you need to share a terminal session (less common).
"
display_section \
"Comparison: tmux vs. Windows Terminal Splits" \
"$section4_content"


# --- Section 5: Other Useful Windows Terminal Features ---
# Re-numbered this section

section5_content="\
A few more things that can enhance your experience:

1.  ${GREEN}Searching:${NC}
    -   ${YELLOW}Ctrl-Shift-F${NC} Search the terminal buffer for text
    -   Useful for finding previous commands or output.

2.  ${GREEN}Zooming:${NC}
    -   ${YELLOW}Ctrl-Mouse Scroll Wheel${NC} Increase/decrease font size
    -   ${YELLOW}Ctrl-0${NC} Reset zoom

3.  ${GREEN}Settings:${NC}
    -   ${YELLOW}Ctrl-,${NC} Open the Settings UI or JSON file
    -   Here you can customize keybindings, color schemes, profiles
      (including your SSH connection), and more.

4.  ${GREEN}Dragging and Dropping:${NC}
    -   You can often ${YELLOW}drag files from Windows Explorer onto the
      terminal window${NC}.

5.  ${GREEN}Clear terminal (but retain scrollback history):${NC}
    -   ${YELLOW}Ctrl-L${NC} Clear screen
    -   Not a Windows Terminal specifically, applies in most shells (bash
      and PowerShell etc).
    -   It ${YELLOW}does not wipe out history like 'clear', but unclutters
      the terminal window${NC}.
    -   To do this in a script: ${YELLOW}softclear() { printf '\\033[H\\033[2J'; }${NC}
"
display_section \
"Other Useful Windows Terminal Features" \
"$section5_content"

# --- Conclusion ---

conclusion_content="\
You've reviewed features of Windows Terminal, the clipboard integration
with xclip, and a comparison between using tmux server-side
sessions/splits versus Windows Terminal client-side splits.

Remember to explore Windows Terminal settings (${YELLOW}Ctrl-,${NC}) for more
customization options and consider when tmux might be beneficial for
server-side session management."

display_section \
"Refresher Complete!" \
"$conclusion_content"
echo
echo

# --- End of script ---
echo -e "${BLUE}==================================================${NC}"
echo -e "${CYAN}Exiting refresher script.${NC}"
echo -e "${BLUE}==================================================${NC}"
