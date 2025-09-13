#!/bin/bash
# Author: Roy Wiseman 2025-05

# Comprehensive Terminal Toys Demo Script
# Installs and demonstrates: fortune, cowsay, figlet, toilet, ponysay, lolcat, aafire, hollywood, bb

# Exit immediately if a command exits with a non-zero status.
# Modified to allow specific command failures within if statements (e.g., using set +e / set -e blocks).
set -e

# --- Configuration ---
TOOLS=(
    "fortune" "cowsay" "figlet" "toilet" "ponysay"
    "lolcat" "aafire" "hollywood" "bb"
)
TOOL_DESCRIPTIONS=(
    "fortune: Displays a random adage or message."
    "cowsay: A configurable talking cow (or other animal) that says your message."
    "figlet: Creates large character banners out of ordinary text."
    "toilet: Similar to figlet, but with more options for colors and effects."
    "ponysay: A fork of cowsay that uses ponies to say your messages."
    "lolcat: Concatenates like cat but displays output in a rainbow of colors."
    "aafire: A fireplace simulator that runs in the terminal using ASCII art."
    "hollywood: Fills your console with Hollywood melodrama."
    "bb: An ASCII art animation demo (often part of bsdgames or aalib)."
)

# URLs for tools not easily available via apt or requiring specific versions
# You might need to visit https://vcheng.org/ponysay/ to find the latest version if this URL changes.
PONYSAY_DEB_URL="https://vcheng.org/ponysay/ponysay_3.0.3+20210327-1_all.deb"
PONYSAY_DEB_FILE="ponysay_latest.deb"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

press_any_key() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
    echo ""
}

display_command() {
    echo -e "${GREEN}$ $@${NC}"
}

display_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

display_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# --- Main Script Logic ---

clear -x # Clear the screen but keep the history visible

echo "████████████████████████████████████████████████████████████████████"
echo "██                                                                ██"
echo "██         Welcome to the Ultimate Terminal Toys Demo!            ██"
echo "██                                                                ██"
echo "████████████████████████████████████████████████████████████████████"
echo ""
echo "This script will demonstrate some fun command-line utilities that add graphical flair to your terminal."
echo "It can also attempt to install them if they are missing."
echo ""

# List tools and descriptions
for desc in "${TOOL_DESCRIPTIONS[@]}"; do
    echo "- $desc"
done
echo ""

# --- Installation Phase ---
echo "--- Tool Installation Check ---"
INSTALLED_TOOLS=()
MISSING_TOOLS=()
TOOLS_TO_INSTALL_APT=()
NEEDS_PONYSAY_DEB=false

# Check installed status for all tools
for tool in "${TOOLS[@]}"; do
    if command_exists "$tool"; then
        echo "- $tool: Installed"
        INSTALLED_TOOLS+=("$tool")
    else
        echo "- $tool: Not installed"
        MISSING_TOOLS+=("$tool")
        case "$tool" in
            "fortune") TOOLS_TO_INSTALL_APT+=("fortune-mod") ;;
            "cowsay") TOOLS_TO_INSTALL_APT+=("cowsay") ;;
            "figlet") TOOLS_TO_INSTALL_APT+=("figlet") ;;
            "toilet") TOOLS_TO_INSTALL_APT+=("toilet") ;;
            "lolcat") TOOLS_TO_INSTALL_APT+=("lolcat") ;;
            "aafire") TOOLS_TO_INSTALL_APT+=("libaa-bin") ;; # aafire is in libaa-bin
            "hollywood") TOOLS_TO_INSTALL_APT+=("hollywood") ;;
            "bb") TOOLS_TO_INSTALL_APT+=("bsdgames") ;; # bb is often in bsdgames
            "ponysay") NEEDS_PONYSAY_DEB=true ;;
        esac
    fi
done
# Remove duplicates from TOOLS_TO_INSTALL_APT
# shellcheck disable=SC2207
TOOLS_TO_INSTALL_APT=($(printf "%s\n" "${TOOLS_TO_INSTALL_APT[@]}" | sort -u | tr '\n' ' '))

echo ""

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "It looks like some tools are missing: ${MISSING_TOOLS[*]}."
    read -r -p "Would you like to attempt to install them now? (yes/no): " install_choice

    if [[ "$install_choice" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        echo ""
        echo "Attempting to install missing tools..."

        if ! command_exists "sudo"; then
            display_error "'sudo' is required for installation but not found. Please install it and try again."
            exit 1
        fi

        display_info "Updating package lists (sudo apt update)..."
        if ! sudo apt update; then
            display_warning "Failed to update package lists. Installation might fail for some tools."
        fi
        echo ""

        # Install tools from apt
        if [ ${#TOOLS_TO_INSTALL_APT[@]} -gt 0 ]; then
            display_info "Installing via apt: ${TOOLS_TO_INSTALL_APT[*]}"
            # shellcheck disable=SC2068
            if sudo apt install -y ${TOOLS_TO_INSTALL_APT[@]}; then
                echo "Selected apt packages installed successfully or were already present."
            else
                display_error "Some apt packages could not be installed. Please check the output above."
                display_info "For 'hollywood' or 'bb', ensure the 'universe' repository is enabled (e.g., sudo add-apt-repository universe) if not found."
            fi
            echo ""
        fi

        # Special handling for ponysay using the .deb file
        if $NEEDS_PONYSAY_DEB && ! command_exists "ponysay"; then
            display_info "Attempting to install ponysay..."
            if ! command_exists "wget"; then
                display_warning "'wget' is required to download ponysay but not found. Trying to install wget..."
                if sudo apt install -y wget; then
                     display_info "wget installed successfully."
                else
                    display_error "Failed to install wget. Cannot download ponysay. Please install wget manually and retry."
                fi
            fi

            if command_exists "wget"; then
                echo "Downloading ponysay from $PONYSAY_DEB_URL"
                if wget -O "$PONYSAY_DEB_FILE" "$PONYSAY_DEB_URL"; then
                    echo "Download complete. Installing $PONYSAY_DEB_FILE..."
                    set +e # Allow dpkg to fail without exiting script
                    sudo dpkg -i "$PONYSAY_DEB_FILE"
                    DPKG_EXIT_CODE=$?
                    set -e

                    if [ $DPKG_EXIT_CODE -eq 0 ]; then
                        echo "ponysay installed successfully (via .deb)."
                        rm "$PONYSAY_DEB_FILE"
                    else
                        display_error "Failed to install ponysay using dpkg (exit code $DPKG_EXIT_CODE)."
                        display_info "Attempting to fix broken dependencies with 'sudo apt --fix-broken install -y'..."
                        set +e
                        if sudo apt --fix-broken install -y; then
                            echo "Dependencies fixed. Trying ponysay installation again..."
                            if sudo dpkg -i "$PONYSAY_DEB_FILE"; then
                                echo "ponysay installed successfully (via .deb) after fixing dependencies."
                                rm "$PONYSAY_DEB_FILE"
                            else
                                display_error "Failed to install ponysay even after fixing dependencies. Please try installing it manually."
                                display_info "The downloaded file is $PONYSAY_DEB_FILE in the current directory."
                            fi
                        else
                            display_error "Failed to fix broken dependencies. Please try installing ponysay manually."
                            display_info "The downloaded file is $PONYSAY_DEB_FILE in the current directory."
                        fi
                        set -e
                    fi
                else
                    display_error "Failed to download ponysay from $PONYSAY_DEB_URL. Please check the URL or your network connection."
                fi
            fi
            echo ""
        fi

        echo "Installation attempts finished."
        echo "Re-checking tool status:"
        # Update installed status
        INSTALLED_TOOLS=()
        for tool in "${TOOLS[@]}"; do
            if command_exists "$tool"; then
                echo "- $tool: Installed"
                INSTALLED_TOOLS+=("$tool")
            else
                echo "- $tool: ${RED}Not installed${NC}"
            fi
        done
        press_any_key
    else
        echo ""
        echo "Skipping installation."
        echo ""
    fi
else
    echo "All primary tools appear to be installed. Great!"
    press_any_key
fi


# --- Demonstrations ---

echo "Now let's see some examples of these tools in action!"
echo "Note: Some commands might require specific fonts or configurations."
echo "If a command doesn't look right, its dependencies might be missing or it might not be fully compatible with your terminal."
echo ""
press_any_key

# Fortune Demo
if command_exists "fortune"; then
    clear -x
    echo "--- fortune Examples ---"
    echo ""
    display_command fortune
    fortune
    press_any_key

    display_command fortune -s  # Short fortune
    fortune -s
    press_any_key

    display_command fortune -l  # Long fortune
    fortune -l
    press_any_key

    # Some systems have themed fortunes
    if [ -e /usr/share/games/fortunes/literature ]; then
        display_command fortune literature
        fortune literature
        press_any_key
    fi
fi

# Cowsay Examples
if command_exists "cowsay"; then
    clear -x
    echo "--- cowsay Examples ---"
    echo ""
    display_command cowsay "Hello from cowsay!"
    cowsay "Hello from cowsay!"
    press_any_key

    echo "Cowsay modes:"
    display_command cowsay -b "Borg mode"
    cowsay -b "Borg mode"
    press_any_key
    display_command cowsay -d "Dead mode"
    cowsay -d "Dead mode"
    press_any_key
    display_command cowsay -g "Greedy mode"
    cowsay -g "Greedy mode"
    press_any_key
    display_command cowsay -p "Paranoid mode"
    cowsay -p "Paranoid mode"
    press_any_key
    display_command cowsay -s "Stoned mode"
    cowsay -s "Stoned mode"
    press_any_key
    display_command cowsay -t "Tired mode"
    cowsay -t "Tired mode"
    press_any_key
    display_command cowsay -w "Wired mode"
    cowsay -w "Wired mode"
    press_any_key
    display_command cowsay -y "Youthful mode"
    cowsay -y "Youthful mode"
    press_any_key

    display_command cowsay -l  # List available cowfiles
    cowsay -l
    press_any_key

    COWFILE="elephant"
    display_command cowsay -f $COWFILE "I'm an $COWFILE!"
    set +e # Allow cowsay to fail if cowfile doesn't exist
    cowsay -f $COWFILE "I'm an $COWFILE!"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Cowfile '$COWFILE' not found, using default cow.${NC}"
        cowsay "I'm an $COWFILE! (Fallback)"
    fi
    set -e
    press_any_key

    echo "Piping text into cowsay:"
    display_command echo "This text is piped!" \| cowsay
    echo "This text is piped!" | cowsay
    press_any_key
fi

# Figlet Examples
if command_exists "figlet"; then
    clear -x
    echo "--- figlet Examples ---"
    echo ""
    display_command figlet "FIGLET"
    figlet "FIGLET"
    press_any_key

    echo "Figlet has many fonts. You can usually find them in /usr/share/figlet/ or use 'showfigfonts'."
    display_command showfigfonts '(if installed, lists available figlet fonts)'
    if command_exists "showfigfonts"; then
        showfigfonts | head -n 15 # Show a few
        echo "..."
    else
        echo "showfigfonts command not found. It's part of figlet's examples or a separate package."
    fi
    press_any_key

    FIG_FONT="slant"
    display_command figlet -f $FIG_FONT "Slanted Text"
    set +e
    figlet -f $FIG_FONT "Slanted Text"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Figlet font '$FIG_FONT' not found, using default font.${NC}"
        figlet "Slanted Text (Fallback)"
    fi
    set -e
    press_any_key

    FIG_FONT="banner"
    display_command figlet -f $FIG_FONT -w 160 "Banner Font" # -w for width
    set +e
    figlet -f $FIG_FONT -w 160 "Banner Font"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Figlet font '$FIG_FONT' not found, using default font.${NC}"
        figlet -w 160 "Banner Font (Fallback)"
    fi
    set -e
    press_any_key
fi

# Toilet Examples
if command_exists "toilet"; then
    clear -x
    echo "--- toilet Examples ---"
    echo ""
    display_command toilet "TOILET"
    toilet "TOILET"
    press_any_key

    display_command toilet --gay "Rainbow Text"
    # Some terminals might not support all toilet features, redirect stderr
    set +e
    toilet --gay "Rainbow Text" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}toilet --gay failed or not supported. Using default.${NC}"
        toilet "Rainbow Text (Fallback)"
    fi
    set -e
    press_any_key

    TOILET_FONT="mono12"
    TOILET_FILTER="metal"
    display_command toilet -f $TOILET_FONT -F $TOILET_FILTER "Shiny Metal"
    set +e
    toilet -f $TOILET_FONT -F $TOILET_FILTER "Shiny Metal" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}toilet -f $TOILET_FONT -F $TOILET_FILTER failed. Font or filter might be missing/unsupported. Using default.${NC}"
        toilet "Shiny Metal (Fallback)"
    fi
    set -e
    press_any_key
    
    display_command toilet -f term -F border --html "HTML Border"
    set +e
    toilet -f term -F border --html "HTML Border" 2>/dev/null # --html outputs HTML, may look weird in terminal
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}toilet -f term -F border --html failed. Using default.${NC}"
        toilet "HTML Border (Fallback)"
    else
        echo "(Above output is HTML code)"
    fi
    set -e
    press_any_key
fi

# Ponysay Examples
if command_exists "ponysay"; then
    clear -x
    echo "--- ponysay Examples ---"
    echo ""
    display_command PYTHONWARNINGS=ignore ponysay "Greetings from a pony!"
    PYTHONWARNINGS=ignore ponysay "Greetings from a pony!" # PYTHONWARNINGS=ignore to suppress SyntaxWarning from older python scripts
    press_any_key

    display_command PYTHONWARNINGS=ignore ponysay -l # List ponies
    PYTHONWARNINGS=ignore ponysay -l | head -n 20 # Show first few
    echo "..."
    press_any_key

    PONY_NAME="fluttershy" # Example, pick one from `ponysay -l`
    display_command PYTHONWARNINGS=ignore ponysay -f "$PONY_NAME" "Hi from $PONY_NAME!"
    set +e
    PYTHONWARNINGS=ignore ponysay -f "$PONY_NAME" "Hi from $PONY_NAME!" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Pony '$PONY_NAME' not found, using a random pony instead.${NC}"
        PYTHONWARNINGS=ignore ponysay "Hi from a random pony! ($PONY_NAME not found)"
    fi
    set -e
    press_any_key

    display_command PYTHONWARNINGS=ignore ponysay -q # Random quote
    PYTHONWARNINGS=ignore ponysay -q
    press_any_key
fi

# lolcat Examples
if command_exists "lolcat"; then
    clear -x
    echo "--- lolcat Examples ---"
    echo ""
    display_command echo "Hello Rainbow World!" \| lolcat
    echo "Hello Rainbow World!" | lolcat
    press_any_key

    display_command date \| lolcat
    date | lolcat
    press_any_key
    
    LOREM="Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
    display_command echo \"\$LOREM\" \| lolcat -a -d 5 -s 50 -p 1
    echo "$LOREM" | lolcat -a -d 2 -s 50 -p 0.5 # Animate, duration 2, speed 50, spread 0.5
    press_any_key
fi

# aafire Example
if command_exists "aafire"; then
    clear -x
    echo "--- aafire Example ---"
    echo ""
    display_command aafire
    echo "Starting aafire... Press Ctrl+C to stop."
    press_any_key
    # Trap Ctrl+C to avoid script exit during aafire
    (trap培训 "echo '\nReturning to menu...' && sleep 1" SIGINT; aafire -driver curses) || echo "aafire finished or was interrupted."
    # The `-driver curses` often works better in modern terminals than the default.
    # If aafire takes over the screen, might need a `reset` or `clear -x` after.
    clear -x
    echo "aafire demo finished."
    press_any_key
fi

# hollywood Example
if command_exists "hollywood"; then
    clear -x
    echo "--- hollywood Example ---"
    echo ""
    display_command hollywood
    echo "Starting hollywood... It will run for a short period or press Ctrl+C multiple times to stop."
    display_info "You might need to increase the number of splits in your terminal multiplexer (like tmux) for full effect."
    press_any_key
    set +e # hollywood might exit with non-zero if stopped early
    hollywood
    set -e
    clear -x
    echo "hollywood demo finished."
    press_any_key
fi

# bb Example
if command_exists "bb"; then
    clear -x
    echo "--- bb Example ---"
    echo ""
    display_command bb
    echo "Starting bb (ASCII art demo)... Press Ctrl+C to stop."
    press_any_key
    (trap "echo '\nReturning to menu...' && sleep 1" SIGINT; bb) || echo "bb finished or was interrupted."
    clear -x
    echo "bb demo finished."
    press_any_key
fi

# --- Combined Demonstrations ---
clear -x
echo "--- Combined Tool Demonstrations ---"
echo "Let's see how these tools can be combined using pipes!"
echo ""
press_any_key

if command_exists "fortune" && command_exists "cowsay" && command_exists "lolcat"; then
    echo "Example 1: fortune | cowsay | lolcat"
    display_command fortune \| cowsay \| lolcat
    fortune | cowsay | lolcat
    press_any_key
else
    display_info "Skipping 'fortune | cowsay | lolcat' (one or more tools missing)."
fi

if command_exists "fortune" && command_exists "ponysay" && command_exists "lolcat"; then
    echo "Example 2: fortune | ponysay | lolcat"
    display_command fortune \| PYTHONWARNINGS=ignore ponysay \| lolcat
    fortune | PYTHONWARNINGS=ignore ponysay | lolcat
    press_any_key
else
    display_info "Skipping 'fortune | ponysay | lolcat' (one or more tools missing)."
fi

if command_exists "toilet" && command_exists "lolcat"; then
    echo "Example 3: echo \"1234567890\" | toilet -f bigmono9 -F metal | lolcat -S 1 -F 0.2"
    display_command echo \"1234567890\" \| toilet -f bigmono9 -F metal \| lolcat -S 1 -F 0.2
    set +e # toilet might fail with specific fonts/filters
    echo "1234567890" | toilet -f bigmono9 -F metal 2>/dev/null | lolcat -S 1 -F 0.2
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Combination with toilet failed (font/filter issue?). Trying simpler toilet.${NC}"
        echo "1234567890" | toilet | lolcat
    fi
    set -e
    press_any_key
else
    display_info "Skipping 'echo | toilet | lolcat' (one or more tools missing)."
fi

if command_exists "figlet" && command_exists "lolcat"; then
    echo "Example 4: figlet -f script \"Awesome Text\" | lolcat -a -d 3"
    display_command figlet -f script \"Awesome Text\" \| lolcat -a -d 3
    set +e
    figlet -f script "Awesome Text" 2>/dev/null | lolcat -a -d 3
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Combination with figlet failed (font issue?). Trying simpler figlet.${NC}"
        figlet "Awesome Text" | lolcat -a -d 3
    fi
    set -e
    press_any_key
else
    display_info "Skipping 'figlet | lolcat' (one or more tools missing)."
fi

if command_exists "ls" && command_exists "figlet" && command_exists "lolcat"; then
    echo "Example 5: Show current directory listing with Figlet (small font) and lolcat"
    display_command ls -1 \| figlet -f term -w \$\(tput cols\) \| lolcat -p 0.8
    # This example might be too much for one screen without scrolling
    ls -1 | head -n 5 | figlet -f term -w $(tput cols) | lolcat -p 0.8
    echo "(Showing first 5 items only for brevity)"
    press_any_key
else
    display_info "Skipping 'ls | figlet | lolcat' (one or more tools missing)."
fi


echo "█████████████████████████████████████████████████████████████"
echo "██                                                         ██"
echo "██         End of the Ultimate Terminal Toys Demo!         ██"
echo "██   Explore these tools further with their --help flags!  ██"
echo "██                                                         ██"
echo "█████████████████████████████████████████████████████████████"
echo ""

exit 0
