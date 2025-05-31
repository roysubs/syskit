#!/bin/bash
# Author: Roy Wiseman 2025-05

# Exit immediately if a command exits with a non-zero status.
# Modified to allow specific command failures within if statements.
set -e

# --- Configuration ---
APT_TOOLS=("cowsay" "figlet" "toilet" "fortune" "lolcat" "libaa-bin")
GITHUB_TOOLS=("hollywood" "bb")
ALL_TOOLS=("cowsay" "figlet" "toilet" "ponysay" "fortune" "lolcat" "aafire" "hollywood" "bb")

TOOL_DESCRIPTIONS=(
    "cowsay: A configurable talking cow (or other animal) that says your message."
    "figlet: Creates large character banners out of ordinary text."
    "toilet: Similar to figlet, but with more options for colors and effects."
    "ponysay: A fork of cowsay that uses ponies to say your messages."
    "fortune: Displays random quotes, jokes, and sayings."
    "lolcat: Adds rainbow coloring to text output."
    "aafire: ASCII art fireplace animation (part of libaa-bin)."
    "hollywood: Creates a Hollywood-style hacker terminal simulation."
    "bb: ASCII art demo with various animations and effects."
)

# URLs for tools not in standard repos
PONYSAY_DEB_URL="https://vcheng.org/ponysay/ponysay_3.0.3+20210327-1_all.deb"
PONYSAY_DEB_FILE="ponysay_latest.deb"
HOLLYWOOD_REPO="https://github.com/dustinkirkland/hollywood.git"
BB_REPO="https://github.com/pipeseroni/pipes.sh.git"  # Alternative since bb might not be easily available

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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

# Function to display section headers
section_header() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}██  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Function to install tools from GitHub
install_from_github() {
    local tool_name=$1
    local repo_url=$2
    
    echo "Installing $tool_name from GitHub..."
    
    # Check if git is available
    if ! command_exists "git"; then
        echo -e "${RED}Error: 'git' is required to install $tool_name but not found.${NC}"
        echo "Please install git first: sudo apt install git"
        return 1
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    case "$tool_name" in
        "hollywood")
            if git clone "$repo_url"; then
                cd hollywood
                if sudo make install; then
                    echo -e "${GREEN}$tool_name installed successfully.${NC}"
                    cd - > /dev/null
                    rm -rf "$temp_dir"
                    return 0
                else
                    echo -e "${RED}Failed to install $tool_name.${NC}"
                fi
            else
                echo -e "${RED}Failed to clone $tool_name repository.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Unknown GitHub tool: $tool_name${NC}"
            ;;
    esac
    
    cd - > /dev/null
    rm -rf "$temp_dir"
    return 1
}

# --- Main Script Logic ---

clear -x # Clear the screen but keep the history visible

echo -e "${PURPLE}███████████████████████████████████████████████████████████████████████████████${NC}"
echo -e "${PURPLE}██                                                                           ██${NC}"
echo -e "${PURPLE}██              Welcome to the Ultimate Terminal Toys Demo!                  ██${NC}"
echo -e "${PURPLE}██                                                                           ██${NC}"
echo -e "${PURPLE}███████████████████████████████████████████████████████████████████████████████${NC}"
echo ""
echo "This script will demonstrate fun command-line utilities that add graphical flair to your terminal:"
echo ""

# List tools and descriptions
for desc in "${TOOL_DESCRIPTIONS[@]}"; do
    echo -e "${CYAN}-${NC} $desc"
done
echo ""

# Check installed status
echo -e "${YELLOW}Checking installed tools:${NC}"
INSTALLED_TOOLS=()
MISSING_TOOLS=()

for tool in "${ALL_TOOLS[@]}"; do
    if command_exists "$tool"; then
        echo -e "${GREEN}- $tool: Installed${NC}"
        INSTALLED_TOOLS+=("$tool")
    else
        echo -e "${RED}- $tool: Not installed${NC}"
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

        # Check for required tools
        for req_tool in "sudo" "wget" "make"; do
            if ! command_exists "$req_tool"; then
                echo -e "${RED}Error: '$req_tool' is required for installation but not found.${NC}"
                echo "Please install it first and try again."
                exit 1
            fi
        done

        sudo apt update || echo -e "${YELLOW}Warning: Failed to update package lists. Installation might fail.${NC}"

        # Install APT packages
        for tool in "${APT_TOOLS[@]}"; do
            if [[ " ${MISSING_TOOLS[*]} " =~ " ${tool} " ]] || [[ " ${MISSING_TOOLS[*]} " =~ " aafire " ]]; then
                echo ""
                echo "Installing $tool..."
                if sudo apt install -y "$tool"; then
                    echo -e "${GREEN}$tool installed successfully.${NC}"
                else
                    echo -e "${RED}Error: Failed to install $tool using apt.${NC}"
                fi
            fi
        done

        # Install ponysay
        if [[ " ${MISSING_TOOLS[*]} " =~ " ponysay " ]]; then
            echo ""
            echo "Installing ponysay..."
            echo "Attempting to download ponysay from $PONYSAY_DEB_URL"
            if wget -O "$PONYSAY_DEB_FILE" "$PONYSAY_DEB_URL"; then
                echo "Download complete. Installing $PONYSAY_DEB_FILE..."
                set +e
                sudo dpkg -i "$PONYSAY_DEB_FILE"
                DPKG_EXIT_CODE=$?
                set -e

                if [ $DPKG_EXIT_CODE -eq 0 ]; then
                    echo -e "${GREEN}ponysay installed successfully.${NC}"
                    rm "$PONYSAY_DEB_FILE"
                else
                    echo -e "${YELLOW}Attempting to fix dependencies...${NC}"
                    set +e
                    if sudo apt --fix-broken install -y && sudo dpkg -i "$PONYSAY_DEB_FILE"; then
                        echo -e "${GREEN}ponysay installed successfully after fixing dependencies.${NC}"
                        rm "$PONYSAY_DEB_FILE"
                    else
                        echo -e "${RED}Failed to install ponysay. You can try installing manually later.${NC}"
                    fi
                    set -e
                fi
            else
                echo -e "${RED}Failed to download ponysay.${NC}"
            fi
        fi

        # Install GitHub tools
        if [[ " ${MISSING_TOOLS[*]} " =~ " hollywood " ]]; then
            install_from_github "hollywood" "$HOLLYWOOD_REPO"
        fi

        # For bb, we'll try the snap version or suggest manual installation
        if [[ " ${MISSING_TOOLS[*]} " =~ " bb " ]]; then
            echo ""
            echo "Installing bb..."
            if command_exists "snap"; then
                if sudo snap install bb; then
                    echo -e "${GREEN}bb installed successfully via snap.${NC}"
                else
                    echo -e "${YELLOW}Failed to install bb via snap. You can try: sudo apt install bb${NC}"
                    echo -e "${YELLOW}Or install it manually from: https://github.com/nothings/aa-bb${NC}"
                fi
            else
                echo -e "${YELLOW}Snap not available. You can try: sudo apt install bb${NC}"
                echo -e "${YELLOW}Or install it manually from: https://github.com/nothings/aa-bb${NC}"
            fi
        fi

        echo ""
        echo -e "${GREEN}Installation attempts finished.${NC}"
        echo "Updated status:"
        for tool in "${ALL_TOOLS[@]}"; do
            if command_exists "$tool"; then
                echo -e "${GREEN}- $tool: Installed${NC}"
            else
                echo -e "${RED}- $tool: Not installed${NC}"
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
    echo -e "${GREEN}All tools are already installed. Excellent!${NC}"
    press_any_key
fi

# --- Demonstrations ---

section_header "Let's see these tools in action!"
press_any_key

# Fortune Examples
if command_exists "fortune"; then
    section_header "fortune Examples"
    
    display_command fortune
    fortune
    press_any_key

    display_command fortune -s  # short fortunes
    fortune -s
    press_any_key

    display_command fortune computers  # computer-related fortunes
    if fortune computers 2>/dev/null; then
        true
    else
        echo -e "${YELLOW}Computer fortunes not available, using default.${NC}"
        fortune
    fi
    press_any_key
fi

# Cowsay Examples
if command_exists "cowsay"; then
    section_header "cowsay Examples"
    
    display_command cowsay "Hello from cowsay!"
    cowsay "Hello from cowsay!"
    press_any_key

    echo "Different cow modes:"
    for mode in "-b" "-d" "-g" "-p" "-s" "-t" "-w" "-y"; do
        mode_name=""
        case $mode in
            "-b") mode_name="Borg mode" ;;
            "-d") mode_name="Dead mode" ;;
            "-g") mode_name="Greedy mode" ;;
            "-p") mode_name="Paranoid mode" ;;
            "-s") mode_name="Stoned mode" ;;
            "-t") mode_name="Tired mode" ;;
            "-w") mode_name="Wired mode" ;;
            "-y") mode_name="Youthful mode" ;;
        esac
        display_command cowsay $mode "\"$mode_name\""
        cowsay $mode "$mode_name"
        echo ""
    done
    press_any_key

    display_command cowsay -f elephant "I'm an elephant!"
    if cowsay -f elephant "I'm an elephant!" 2>/dev/null; then
        true
    else
        echo -e "${YELLOW}Elephant cow file not found, using default.${NC}"
        cowsay "I'm an elephant! (Default cow)"
    fi
    press_any_key
fi

# Figlet Examples
if command_exists "figlet"; then
    section_header "figlet Examples"
    
    display_command figlet "FIGLET DEMO"
    figlet "FIGLET DEMO"
    press_any_key

    echo "Different figlet fonts:"
    for font in "standard" "slant" "banner" "big" "script" "bubble"; do
        display_command figlet -f $font "\"$font\""
        if figlet -f $font "$font" 2>/dev/null; then
            true
        else
            echo -e "${YELLOW}Font '$font' not found, using default.${NC}"
            figlet "$font (default)"
        fi
        press_any_key
    done

    if command_exists "showfigfonts"; then
        echo "Want to see all available fonts? Here they are:"
        display_command showfigfonts
        echo -e "${CYAN}(This might take a while - showing first few...)${NC}"
        showfigfonts | head -20
        press_any_key
    fi
fi

# Toilet Examples
if command_exists "toilet"; then
    section_header "toilet Examples"
    
    display_command toilet "TOILET DEMO"
    toilet "TOILET DEMO"
    press_any_key

    echo "Toilet with filters and effects:"
    
    filters=("metal:Shiny Metal" "gay:Rainbow" "border:Border")
    for filter_info in "${filters[@]}"; do
        IFS=':' read -r filter_name display_name <<< "$filter_info"
        display_command toilet -F $filter_name "\"$display_name\""
        if toilet -F $filter_name "$display_name" 2>/dev/null; then
            true
        else
            echo -e "${YELLOW}Filter '$filter_name' not available, using default.${NC}"
            toilet "$display_name (default)"
        fi
        press_any_key
    done
fi

# Ponysay Examples
if command_exists "ponysay"; then
    section_header "ponysay Examples"
    
    display_command PYTHONWARNINGS=ignore ponysay "Greetings from ponyland!"
    PYTHONWARNINGS=ignore ponysay "Greetings from ponyland!"
    press_any_key

    display_command PYTHONWARNINGS=ignore ponysay -q  # random quote
    PYTHONWARNINGS=ignore ponysay -q
    press_any_key
fi

# Lolcat Examples
if command_exists "lolcat"; then
    section_header "lolcat Examples"
    
    display_command echo "\"Rainbow text!\"" \| lolcat
    echo "Rainbow text!" | lolcat
    press_any_key

    display_command figlet "RAINBOW" \| lolcat
    if command_exists "figlet"; then
        figlet "RAINBOW" | lolcat
    else
        echo "RAINBOW" | lolcat
    fi
    press_any_key
fi

# AAfire Example
if command_exists "aafire"; then
    section_header "aafire Examples"
    
    echo -e "${YELLOW}Starting ASCII fireplace (press 'q' to quit)...${NC}"
    display_command aafire
    echo -e "${CYAN}(This will run for 5 seconds, then auto-quit)${NC}"
    timeout 5s aafire || true
    press_any_key
fi

# Hollywood Example
if command_exists "hollywood"; then
    section_header "hollywood Examples"
    
    echo -e "${YELLOW}Starting Hollywood hacker simulation (press Ctrl+C to quit)...${NC}"
    display_command hollywood
    echo -e "${CYAN}(This will run for 10 seconds, then auto-quit)${NC}"
    timeout 10s hollywood || true
    press_any_key
fi

# BB Example
if command_exists "bb"; then
    section_header "bb Examples"
    
    echo -e "${YELLOW}Starting BB ASCII art demo (press 'q' to quit)...${NC}"
    display_command bb
    echo -e "${CYAN}(This will run for 8 seconds, then auto-quit)${NC}"
    timeout 8s bb || true
    press_any_key
fi

# --- Combination Examples ---

section_header "COMBINATION EXAMPLES - The Real Fun!"

echo -e "${PURPLE}Now let's see how these tools work together!${NC}"
echo ""

if command_exists "fortune" && command_exists "cowsay"; then
    display_command fortune \| cowsay
    fortune | cowsay
    press_any_key
fi

if command_exists "fortune" && command_exists "cowsay" && command_exists "lolcat"; then
    display_command fortune \| cowsay \| lolcat
    fortune | cowsay | lolcat
    press_any_key
fi

if command_exists "fortune" && command_exists "ponysay"; then
    display_command fortune \| ponysay
    PYTHONWARNINGS=ignore fortune | ponysay
    press_any_key
fi

if command_exists "figlet" && command_exists "lolcat"; then
    display_command echo "\"AWESOME\"" \| figlet \| lolcat
    echo "AWESOME" | figlet | lolcat
    press_any_key
fi

if command_exists "toilet" && command_exists "lolcat"; then
    display_command echo "\"COLORFUL\"" \| toilet \| lolcat
    echo "COLORFUL" | toilet | lolcat
    press_any_key
fi

if command_exists "fortune" && command_exists "figlet" && command_exists "lolcat"; then
    display_command fortune -s \| figlet \| lolcat
    fortune -s | figlet | lolcat
    press_any_key
fi

# Creative examples
section_header "CREATIVE COMBINATIONS"

if command_exists "date" && command_exists "toilet" && command_exists "lolcat"; then
    display_command date \| toilet -f mono12 -F metal \| lolcat
    date | toilet | lolcat
    press_any_key
fi

if command_exists "whoami" && command_exists "figlet" && command_exists "cowsay" && command_exists "lolcat"; then
    display_command whoami \| figlet \| cowsay -n \| lolcat
    whoami | figlet | cowsay -n | lolcat
    press_any_key
fi

# Useful aliases suggestion
section_header "SUGGESTED ALIASES FOR YOUR ~/.bashrc"

echo -e "${CYAN}Add these to your ~/.bashrc for quick access:${NC}"
echo ""
echo -e "${GREEN}alias rainbow='lolcat'${NC}"
echo -e "${GREEN}alias big='figlet'${NC}"
echo -e "${GREEN}alias say='cowsay'${NC}"
echo -e "${GREEN}alias pony='ponysay'${NC}"
echo -e "${GREEN}alias wisdom='fortune | cowsay | lolcat'${NC}"
echo -e "${GREEN}alias ponywisdom='fortune | ponysay'${NC}"
echo -e "${GREEN}alias bigtext='figlet | lolcat'${NC}"
echo -e "${GREEN}alias fire='aafire'${NC}"
echo -e "${GREEN}alias hacker='hollywood'${NC}"
echo ""

section_header "TIPS AND TRICKS"

echo -e "${CYAN}Pro Tips:${NC}"
echo "• Pipe any command output through lolcat for rainbow colors"
echo "• Use figlet or toilet to make any text large and fancy"
echo "• Combine fortune with any text-display tool for random entertainment"
echo "• Add these to shell scripts for colorful output"
echo "• Use in your bash prompt (PS1) for a fun terminal"
echo "• Great for system monitoring scripts and notifications"
echo ""

echo -e "${PURPLE}█████████████████████████████████████████████████████████████${NC}"
echo -e "${PURPLE}██                                                         ██${NC}"
echo -e "${PURPLE}██         Thank you for exploring terminal toys!          ██${NC}"
echo -e "${PURPLE}██              Have fun and stay colorful!                ██${NC}"
echo -e "${PURPLE}██                                                         ██${NC}"
echo -e "${PURPLE}█████████████████████████████████████████████████████████████${NC}"
echo ""

if command_exists "fortune" && command_exists "ponysay" && command_exists "lolcat"; then
    echo -e "${YELLOW}One final surprise:${NC}"
    PYTHONWARNINGS=ignore fortune | ponysay | lolcat
fi

exit 0
