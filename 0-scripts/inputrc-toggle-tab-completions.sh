#!/bin/bash
# Author: Roy Wiseman 2025-01
#
# Purpose: Generic script to toggle between two sets of configuration settings
#
# Toggles between Bash default tab completion and PowerShell-style tab completion
# Can be adapted for other toggle settings by changing the configuration blocks.

# ===== CONFIGURATION - MODIFY THIS SECTION FOR DIFFERENT TOGGLE SETTINGS =====

# Settings description - what are we toggling?
SETTING_NAME="tab completion"
CONFIG_FILE="$HOME/.inputrc"
BACKUP_FILE="$HOME/.inputrc.bak"

# Define the marker comments we'll use to identify our settings block
START_MARKER="# --- BEGIN TOGGLE-TAB-COMPLETION SETTINGS ---"
END_MARKER="# --- END TOGGLE-TAB-COMPLETION SETTINGS ---"

# First style settings block
STYLE_1_NAME="PowerShell-style"
STYLE_1_DESC="PowerShell-style tab completion is ENABLED:
# - Tab cycles through completion options (menu-complete)
# - Shift+Tab cycles backward
# - Shows all possibilities if there's ambiguity
# - Case-insensitive completion"
STYLE_1_SETTINGS="# ${STYLE_1_DESC}

# Cycle through completions with Tab
TAB: menu-complete

# Cycle backward with Shift+Tab
\"\e[Z\": menu-complete-backward

# Show all ambiguous completions before cycling
set show-all-if-ambiguous on

# Case-insensitive completion
set completion-ignore-case on"

# Second style settings block
STYLE_2_NAME="Bash default"
STYLE_2_DESC="Bash default tab completion is ENABLED:
# - Tab shows all possible completions at once
# - Case-sensitive completion
# - Requires double-tab to see all options"
STYLE_2_SETTINGS="# ${STYLE_2_DESC}

# Default tab behavior (shows all possibilities)
# TAB: complete

# Default case sensitivity
set completion-ignore-case off

# Default ambiguity behavior (double-tab to see all)
set show-all-if-ambiguous off"

# ===== END CONFIGURATION =====

# Define color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting ${SETTING_NAME} settings check...${NC}"

# Check if config file exists, create it if it doesn't
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}Creating new $CONFIG_FILE file...${NC}"
    touch "$CONFIG_FILE"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Could not create $CONFIG_FILE. Check permissions.${NC}"
        exit 1
    fi
fi

# Create a backup of the current config file
TIMESTAMP=$(date +"%Y%m%d.%H%M%S")
BACKUP_FILE="$CONFIG_FILE.bak.$TIMESTAMP"
cp -f "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${BLUE}Created backup at $BACKUP_FILE${NC}"

# Function to display current status
check_current_status() {
    if grep -q "$STYLE_1_DESC" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${GREEN}Current status: $STYLE_1_NAME ${SETTING_NAME} is ENABLED${NC}"
        echo -e "${YELLOW}Features enabled:${NC}"
        echo "$STYLE_1_DESC" | grep -v "^#.*#" | grep "^#" | sed 's/^# - /  • /'
        return 0  # Style 1 is active
    elif grep -q "$STYLE_2_DESC" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${GREEN}Current status: $STYLE_2_NAME ${SETTING_NAME} is ENABLED${NC}"
        echo -e "${YELLOW}Features enabled:${NC}"
        echo "$STYLE_2_DESC" | grep -v "^#.*#" | grep "^#" | sed 's/^# - /  • /'
        return 1  # Style 2 is active
    else
        echo -e "${BLUE}Current status: No custom ${SETTING_NAME} settings detected${NC}"
        echo -e "${YELLOW}System is likely using default settings:${NC}"
        echo "$STYLE_2_DESC" | grep -v "^#.*#" | grep "^#" | sed 's/^# - /  • /'
        return 1  # Treat as Style 2 default
    fi
}

# Function to apply new settings
apply_settings() {
    local new_settings="${START_MARKER}
${1}
${END_MARKER}"
    local temp_file=$(mktemp)

    # Copy the original file
    cat "$CONFIG_FILE" > "$temp_file"

    # Check if our block exists and remove it
    if grep -q "$START_MARKER" "$temp_file"; then
        echo -e "${BLUE}Found existing settings block, updating...${NC}"
        # Remove existing block
        awk -v start="$START_MARKER" -v end="$END_MARKER" '
            BEGIN { printing = 1 }
            $0 ~ start { printing = 0; next }
            $0 ~ end { printing = 1; next }
            printing { print }
        ' "$temp_file" > "${temp_file}.new"
        mv -f "${temp_file}.new" "$temp_file"
    fi

    # Append the new settings
    echo "" >> "$temp_file"  # Add a newline for cleanliness
    echo "$new_settings" >> "$temp_file"

    # Check for and remove any consecutive empty lines
    awk 'BEGIN{emptyCount=0}
        /^$/ {emptyCount++; if (emptyCount<=1) print; next}
        {emptyCount=0; print}' "$temp_file" > "${temp_file}.new"
    mv -f "${temp_file}.new" "$temp_file"

    # Replace the original file
    mv -f "$temp_file" "$CONFIG_FILE"
}

# Function to apply changes to current session
apply_to_current_session() {
    echo -e "${GREEN}Applying changes to current session...${NC}"
    
    # Method 1: Reload the entire .inputrc file
    if command -v bind >/dev/null 2>&1; then
        bind -f "$CONFIG_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully reloaded .inputrc${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: Some settings may not have applied correctly${NC}"
        fi
    fi
    
    # Method 2: Apply specific settings directly via bind commands
    echo -e "${BLUE}Applying individual settings...${NC}"
    
    if [[ "$1" == *"menu-complete"* ]]; then
        # PowerShell-style settings
        bind 'TAB: menu-complete' 2>/dev/null
        bind '"\e[Z": menu-complete-backward' 2>/dev/null
        bind 'set show-all-if-ambiguous on' 2>/dev/null
        bind 'set completion-ignore-case on' 2>/dev/null
        echo -e "${GREEN}✓ Applied PowerShell-style tab completion${NC}"
    else
        # Bash default settings
        bind 'TAB: complete' 2>/dev/null
        bind 'set show-all-if-ambiguous off' 2>/dev/null
        bind 'set completion-ignore-case off' 2>/dev/null
        echo -e "${GREEN}✓ Applied Bash default tab completion${NC}"
    fi
    
    # Method 3: For persistent effect, suggest exec bash as alternative
    echo -e "\n${YELLOW}Note: If changes don't seem to take effect immediately, you can:${NC}"
    echo -e "${BLUE}  1. Run: ${GREEN}exec bash${NC} ${BLUE}(restarts bash without losing session)${NC}"
    echo -e "${BLUE}  2. Or source this script: ${GREEN}source $0${NC}"
    echo -e "${BLUE}  3. Or start a new terminal session${NC}"
}

# Check the current status
echo -e "${BLUE}Checking current ${SETTING_NAME} settings...${NC}"
check_current_status
current_is_style_1=$?

# Determine which style to apply based on current status
if [ $current_is_style_1 -eq 0 ]; then
    echo -e "\n${YELLOW}About to switch to: $STYLE_2_NAME ${SETTING_NAME}${NC}"
    new_style="$STYLE_2_SETTINGS"
    new_style_name="$STYLE_2_NAME"
else
    echo -e "\n${YELLOW}About to switch to: $STYLE_1_NAME ${SETTING_NAME}${NC}"
    new_style="$STYLE_1_SETTINGS"
    new_style_name="$STYLE_1_NAME"
fi

# Confirm before making changes
echo -e "\n${RED}This will modify your $CONFIG_FILE file.${NC}"
read -p "Do you want to continue? [y/N] " -n 1 -r
echo  # Move to a new line

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Apply the new settings
    apply_settings "$new_style"
    echo -e "\n${GREEN}Successfully updated to $new_style_name ${SETTING_NAME}!${NC}"

    # Show the settings that were changed
    echo -e "\n${BLUE}Settings summary:${NC}"
    if [[ "$new_style_name" == "$STYLE_1_NAME" ]]; then
        echo "$STYLE_1_DESC" | grep -v "^#.*#" | grep "^#" | sed 's/^# - /  • /'
    else
        echo "$STYLE_2_DESC" | grep -v "^#.*#" | grep "^#" | sed 's/^# - /  • /'
    fi

    # Apply changes to the current session
    apply_to_current_session "$new_style"
    
    # Ask if user wants to restart bash for full effect
    echo -e "\n${YELLOW}For the most reliable application of changes, would you like to restart bash?${NC}"
    echo -e "${BLUE}This will run 'exec bash' to restart your shell without losing your session.${NC}"
    read -p "Restart bash now? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Restarting bash...${NC}"
        exec bash
    fi
    
else
    echo -e "\n${YELLOW}Operation cancelled. No changes were made.${NC}"
fi

# We only exit if NOT being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit 0
fi
