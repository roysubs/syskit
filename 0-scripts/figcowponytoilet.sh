#!/bin/bash
# Author: Roy Wiseman 2025-03

# Exit immediately if a command exits with a non-zero status.
# Modified to allow specific command failures within if statements.
set -e

# --- Configuration ---
TOOLS=("cowsay" "figlet" "toilet" "ponysay")
TOOL_DESCRIPTIONS=(
    "cowsay: A configurable talking cow (or other animal) that says your message."
    "figlet: Creates large character banners out of ordinary text."
    "toilet: Similar to figlet, but with more options for colors and effects."
    "ponysay: A fork of cowsay that uses ponies to say your messages."
)
# Specific URL for ponysay .deb on Debian/Ubuntu (check if this is still current)
# You might need to visit https://vcheng.org/ponysay/ to find the latest version if this URL changes.
PONYSAY_DEB_URL="https://vcheng.org/ponysay/ponysay_3.0.3+20210327-1_all.deb"
PONYSAY_DEB_FILE="ponysay_latest.deb"

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to pause execution and wait for a key press
press_any_key() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
    echo ""
}

# Function to display a command in green
display_command() {
    echo -e "${GREEN}$ $@${NC}"
}

# --- Main Script Logic ---

clear -x # Clear the screen but keep the history visible

echo "███████████████████████████████████████████████████████████████████████████████"
echo "██                                                                           ██"
echo "██              Welcome to the Graphical Terminal Tools Demo!                ██"
echo "██                                                                           ██"
echo "███████████████████████████████████████████████████████████████████████████████"
echo ""
echo "This script will demonstrate some fun command-line utilities that add graphical flair to your terminal:"
echo ""

# List tools and descriptions
for desc in "${TOOL_DESCRIPTIONS[@]}"; do
    echo "- $desc"
done
echo ""

# Check installed status
echo "Checking installed tools:"
INSTALLED_TOOLS=()
MISSING_TOOLS=()

for tool in "${TOOLS[@]}"; do
    if command_exists "$tool"; then
        echo "- $tool: Installed"
        INSTALLED_TOOLS+=("$tool")
    else
        echo "- $tool: Not installed"
        MISSING_TOOLS+=("$tool")
    fi
done
echo ""

# Offer to install missing tools
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "It looks like some tools are missing: ${MISSING_TOOLS[*]}."
    read -r -p "Would you like to attempt to install them now? (yes/no): " install_choice

    if [[ "$install_choice" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        echo ""
        echo "Attempting to install missing tools..."

        # Check for sudo and wget before attempting installation
        if ! command_exists "sudo"; then
            echo "Error: 'sudo' is required for installation but not found. Please install it and try again."
            exit 1
        fi
        if ! command_exists "wget"; then
            echo "Error: 'wget' is required to download ponysay but not found. Please install it and try again."
            exit 1
        fi

        sudo apt update || echo "Warning: Failed to update package lists. Installation might fail."

        for tool in "${MISSING_TOOLS[@]}"; do
            echo ""
            echo "Installing $tool..."
            case "$tool" in
                "cowsay"|"figlet"|"toilet")
                    if sudo apt install -y "$tool"; then
                        echo "$tool installed successfully."
                        # Add to installed list and remove from missing list if successful
                        INSTALLED_TOOLS+=("$tool")
                        # Remove from missing list using a temporary array or bash 4.4+ array.remove
                        # For broader compatibility, rebuild the missing list
                        temp_missing=()
                        for mtool in "${MISSING_TOOLS[@]}"; do
                            if [ "$mtool" != "$tool" ]; then
                                temp_missing+=("$mtool")
                            fi
                        done
                        MISSING_TOOLS=("${temp_missing[@]}")

                    else
                        echo -e "${RED}Error: Failed to install $tool using apt. Please try installing it manually.${NC}"
                    fi
                    ;;
                "ponysay")
                    # Special handling for ponysay using the .deb file
                    echo "Attempting to download ponysay from $PONYSAY_DEB_URL"
                    if wget -O "$PONYSAY_DEB_FILE" "$PONYSAY_DEB_URL"; then
                        echo "Download complete. Installing $PONYSAY_DEB_FILE..."
                        # Use set +e around dpkg to prevent script exit on dependency errors
                        set +e
                        sudo dpkg -i "$PONYSAY_DEB_FILE"
                        DPKG_EXIT_CODE=$?
                        set -e

                        if [ $DPKG_EXIT_CODE -eq 0 ]; then
                            echo "ponysay installed successfully (via .deb)."
                             INSTALLED_TOOLS+=("$tool")
                             temp_missing=()
                             for mtool in "${MISSING_TOOLS[@]}"; do
                                 if [ "$mtool" != "$tool" ]; then
                                     temp_missing+=("$mtool")
                                 fi
                             done
                             MISSING_TOOLS=("${temp_missing[@]}")
                             rm "$PONYSAY_DEB_FILE"
                        else
                            echo -e "${RED}Error: Failed to install ponysay using dpkg (exit code $DPKG_EXIT_CODE). Attempting to fix broken dependencies...${NC}"
                             set +e
                            if sudo apt --fix-broken install -y; then
                                echo "Dependencies fixed. Trying ponysay installation again..."
                                if sudo dpkg -i "$PONYSAY_DEB_FILE"; then
                                     echo "ponysay installed successfully (via .deb) after fixing dependencies."
                                     INSTALLED_TOOLS+=("$tool")
                                     temp_missing=()
                                     for mtool in "${MISSING_TOOLS[@]}"; do
                                         if [ "$mtool" != "$tool" ]; then
                                             temp_missing+=("$mtool")
                                         fi
                                     done
                                     MISSING_TOOLS=("${temp_missing[@]}")
                                     rm "$PONYSAY_DEB_FILE"
                                else
                                     echo -e "${RED}Error: Failed to install ponysay even after fixing dependencies. Please try installing it manually.${NC}"
                                     # Don't remove the deb file if installation failed again
                                fi
                            else
                                echo -e "${RED}Error: Failed to fix broken dependencies. Please try installing ponysay manually.${NC}"
                                # Don't remove the deb file if installation failed
                            fi
                            set -e
                        fi
                    else
                        echo -e "${RED}Error: Failed to download ponysay from $PONYSAY_DEB_URL. Please check the URL or your network connection.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${RED}Unknown tool $tool. Skipping installation.${NC}"
                    ;;
            esac
        done

        echo ""
        echo "Installation attempts finished."
        echo "Current status:"
         for tool in "${TOOLS[@]}"; do
            if command_exists "$tool"; then
                echo "- $tool: Installed"
            else
                echo "- $tool: Not installed"
            fi
        done
        echo ""
        press_any_key
    else
        echo ""
        echo "Skipping installation."
        echo ""
    fi
else
    echo "All tools are already installed. Great!"
    press_any_key
fi

# --- Demonstrations ---

echo "Now let's see some examples of these tools in action!"
echo ""
press_any_key

# Cowsay Examples
if command_exists "cowsay"; then
    clear -x
    echo "--- cowsay Examples ---"
    echo ""
    display_command cowsay "Hello from cowsay!"
    cowsay "Hello from cowsay!"
    press_any_key

    # Check if elephant is available, default to cow
    display_command cowsay -b   \# Borg mode
    display_command cowsay -d   \# dead mode
    display_command cowsay -g   \# greedy mode
    display_command cowsay -p   \# paranoid mode
    display_command cowsay -s   \# stoned mode
    display_command cowsay -t   \# tired mode
    display_command cowsay -w   \# wired mode
    display_command cowsay -y   \# youthful mode
    echo    
    display_command cowsay -l   \# Display all -f files that can be used
    cowsay -l
    echo
    display_command cowsay -f elephant "I'm an elephant!"
    if cowsay -f elephant "I'm an elephant!"; then
        true # success
    else
        echo -e "${RED}Cowsay cow file 'elephant' not found, using default cow.${NC}"
        cowsay "I'm an elephant! (Fallback)"
    fi
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

    display_command figlet -f standard "Standard Font"
    figlet -f standard "Standard Font"
    press_any_key

    # Try different fonts - font availability varies by system
    display_command figlet -f slant "Slanted Text"
    if figlet -f slant "Slanted Text"; then
        true # success
    else
        echo -e "${RED}Figlet font 'slant' not found, using default font.${NC}"
        figlet "Slanted Text (Fallback)"
    fi
    press_any_key

    display_command figlet -f banner "Banner Font"
    if figlet -f banner "Banner Font"; then
        true # success
    else
        echo -e "${RED}Figlet font 'banner' not found, using default font.${NC}"
        figlet "Banner Font (Fallback)"
    fi
    press_any_key

    display_command figlet -f big "BIG Font"
    if figlet -f big "BIG Font"; then
        true # success
    else
        echo -e "${RED}Figlet font 'big' not found, using default font.${NC}"
        figlet "BIG Font (Fallback)"
    fi
    press_any_key

    display_command figlet -f script "Script Font"
    if figlet -f script "Script Font"; then
        true # success
    else
        echo -e "${RED}Figlet font 'script' not found, using default font.${NC}"
        figlet "Script Font (Fallback)"
    fi
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

    display_command toilet -f mono12 -F metal "Shiny Metal"
    # Wrap in if to handle potential filter issues and redirect stderr
    if toilet -f mono12 -F metal "Shiny Metal" 2>/dev/null; then
        true # success
    else
         echo -e "${RED}Toilet command 'toilet -f mono12 -F metal \"Shiny Metal\"' failed.${NC}"
         echo -e "${RED}Filter '-F metal' or font '-f mono12' might not be supported by your toilet version. Try 'toilet --help'.${NC}"
         echo "Using default toilet output instead:"
         toilet "Shiny Metal (Fallback)"
    fi
    press_any_key

    display_command toilet -f term -F gay "Rainbow Text"
     if toilet -f term -F gay "Rainbow Text" 2>/dev/null; then
        true # success
    else
         echo -e "${RED}Toilet command 'toilet -f term -F gay \"Rainbow Text\"' failed.${NC}"
         echo -e "${RED}Filter '-F gay' or font '-f term' might not be supported by your toilet version. Try 'toilet --help'.${NC}"
         echo "Using default toilet output instead:"
         toilet "Rainbow Text (Fallback)"
    fi
    press_any_key

    # Additional Toilet Examples
    display_command toilet --ice "Icy Cool"
    if toilet --ice "Icy Cool" 2>/dev/null; then
         true # success
    else
         echo -e "${RED}Toilet command 'toilet --ice \"Icy Cool\"' failed.${NC}"
         echo -e "${RED}Option '--ice' might not be supported by your toilet version. Try 'toilet --help'.${NC}"
         echo "Using default toilet output instead:"
         toilet "Icy Cool (Fallback)"
    fi
    press_any_key

    display_command toilet -f future -F border "Future Border"
    if toilet -f future -F border "Future Border" 2>/dev/null; then
         true # success
    else
         echo -e "${RED}Toilet command 'toilet -f future -F border \"Future Border\"' failed.${NC}"
         echo -e "${RED}Filter '-F border' or font '-f future' might not be supported by your toilet version. Try 'toilet --help'.${NC}"
         echo "Using default toilet output instead:"
         toilet "Future Border (Fallback)"
    fi
    press_any_key

    display_command toilet -f term -F matrix "Matrix Effect"
    if toilet -f term -F matrix "Matrix Effect" 2>/dev/null; then
         true # success
    else
         echo -e "${RED}Toilet command 'toilet -f term -F matrix \"Matrix Effect\"' failed.${NC}"
         echo -e "${RED}Filter '-F matrix' or font '-f term' might not be supported by your toilet version. Try 'toilet --help'.${NC}"
         echo "Using default toilet output instead:"
         toilet "Matrix Effect (Fallback)"
    fi
    press_any_key
fi

# Ponysay Examples
if command_exists "ponysay"; then
    clear -x
    echo "--- ponysay Examples ---"
    echo ""
    # Attempt to suppress SyntaxWarning by setting PYTHONWARNINGS
    display_command PYTHONWARNINGS=ignore ponysay "Greetings from a pony!"
    PYTHONWARNINGS=ignore ponysay "Greetings from a pony!"
    press_any_key

    # Try a specific pony - needs to be a valid pony file name
    # You can list available ponies with `ponysay -l`
    PONY="pinkie" # Example pony name
    display_command PYTHONWARNINGS=ignore ponysay -f "$PONY" "Hi from $PONY!"
    # Wrap in if to handle missing pony file gracefully and redirect stderr
    if PYTHONWARNINGS=ignore ponysay -f "$PONY" "Hi from $PONY!" 2>/dev/null; then
        true # success
    else
        echo -e "${RED}Pony '$PONY' not found, using a random pony instead.${NC}"
        PYTHONWARNINGS=ignore ponysay "Hi from a random pony! (Fallback)"
    fi
    press_any_key

    echo "Getting a random pony quote:"
    display_command PYTHONWARNINGS=ignore ponysay -q
    PYTHONWARNINGS=ignore ponysay -q
    press_any_key
fi

echo "█████████████████████████████████████████████████████████████"
echo "██                                                         ██"
echo "██         End of graphical terminal tools demo!           ██"
echo "██                                                         ██"
echo "█████████████████████████████████████████████████████████████"
echo ""

exit 0
