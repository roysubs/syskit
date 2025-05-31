#!/bin/bash
# Author: Roy Wiseman 2025-03

# add-path.sh - Generic script to add directories to PATH
# Usage: source add-path.sh <directory> [options]

show_usage() {
    cat << 'EOF'
add-path.sh - Add directories to PATH

USAGE:
    source add-path.sh <directory> [options]
    . add-path.sh <directory> [options]

OPTIONS:
    -bashrc     Save to ~/.bashrc for future sessions
    -profile    Save to ~/.profile instead of ~/.bashrc
    -root       Save to /root/.bashrc (requires sudo/root access)
    -system     Save to /etc/environment (system-wide, requires sudo)
    -dups       Clean duplicate entries from PATH
    -prepend    Add to beginning of PATH (default behavior)
    -append     Add to end of PATH
    -check      Only check if directory is in PATH (no modifications)
    -help       Show this help message

EXAMPLES:
    add-path /some/path                    # Shows warning (as it must be sourced)
    . add-path /some/path                  # Add to current session only
    . add-path /some/path -system -dups -prepend
            # Add to current session and prepend to system (highest priority)
            # and prune the current PATH of duplicates

NOTES:
    - Script MUST be sourced (with 'source' or '.') to modify current session PATH
    - Use absolute paths or paths will be resolved relative to HOME
    - -system option requires sudo privileges
    - -root option may require sudo depending on permissions

PATH LOADING ORDER REFERENCE:
/etc/environment:
    Loaded FIRST by PAM (Pluggable Authentication Modules) during login
    Applied to ALL login methods (console, SSH, GUI) before shell initialization
    System-wide, affects all users and all shells (not just bash)
    It uses a KEY="value" format, i.e. does not use normal shell script syntax

Login Shell (Console/SSH):
    /etc/environment → /etc/profile → ~/.bash_profile → ~/.bash_login → ~/.profile → ~/.bashrc

Non-Login Shell (Terminal in GUI):
    /etc/environment → ~/.bashrc only

GUI Login (Desktop Environment):
    /etc/environment → /etc/profile → ~/.profile (unless ~/.bash_profile exists)
    Note: Some DEs may have additional environment handling
EOF
}

# Color codes for output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Function to clean duplicate entries from PATH
clean_path() {
    PATH=$(echo "$PATH" | tr ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')
    echo -e "${GREEN}✓${NC} Cleaned duplicate entries from PATH"
}

# Function to check if directory is in PATH
is_in_path() {
    local DIR="$1"
    [[ ":$PATH:" == *":$DIR:"* ]]
}

# Function to add directory to PATH
add_to_current_path() {
    local DIR="$1"
    local POSITION="$2"  # "prepend" or "append"
    
    if is_in_path "$DIR"; then
        echo -e "${YELLOW}!${NC} $DIR is already in current PATH"
        return 0
    fi
    
    if [[ "$POSITION" == "append" ]]; then
        export PATH="$PATH:$DIR"
        echo -e "${GREEN}✓${NC} Added $DIR to end of current PATH"
    else
        export PATH="$DIR:$PATH"
        echo -e "${GREEN}✓${NC} Added $DIR to beginning of current PATH"
    fi
}

# Function to add directory to profile file
add_to_profile() {
    local DIR="$1"
    local PROFILE_FILE="$2"
    local POSITION="$3"
    
    # Create the export line
    local EXPORT_LINE
    if [[ "$POSITION" == "append" ]]; then
        EXPORT_LINE="export PATH=\"\$PATH:$DIR\""
    else
        EXPORT_LINE="export PATH=\"$DIR:\$PATH\""
    fi
    
    # Check if already exists (exact match)
    if grep -qxF "$EXPORT_LINE" "$PROFILE_FILE" 2>/dev/null; then
        echo -e "${YELLOW}!${NC} $DIR already configured in $PROFILE_FILE"
        return 0
    fi
    
    # Check if directory is already referenced in the file (loose check)
    if grep -q "$DIR" "$PROFILE_FILE" 2>/dev/null; then
        echo -e "${YELLOW}!${NC} $DIR may already be referenced in $PROFILE_FILE (manual check recommended)"
    fi
    
    # Add to file
    if [[ -w "$PROFILE_FILE" ]] || [[ ! -e "$PROFILE_FILE" && -w "$(dirname "$PROFILE_FILE")" ]]; then
        echo "$EXPORT_LINE" >> "$PROFILE_FILE"
        echo -e "${GREEN}✓${NC} Added $DIR to $PROFILE_FILE"
    else
        echo -e "${RED}✗${NC} Cannot write to $PROFILE_FILE (permission denied)"
        return 1
    fi
}

# Function to add to /etc/environment (system-wide)
add_to_system() {
    local DIR="$1"
    local POSITION="$2"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}✗${NC} System-wide configuration requires root privileges"
        echo -e "    Try: sudo -E source add-path.sh $DIR -system"
        return 1
    fi
    
    # /etc/environment uses different syntax
    local ENV_FILE="/etc/environment"
    
    # Check if PATH line exists in /etc/environment
    if grep -q "^PATH=" "$ENV_FILE" 2>/dev/null; then
        if grep -q "$DIR" "$ENV_FILE"; then
            echo -e "${YELLOW}!${NC} $DIR may already be in system PATH"
        else
            # Modify existing PATH line
            if [[ "$POSITION" == "append" ]]; then
                sed -i "s|^PATH=\"\\(.*\\)\"|PATH=\"\\1:$DIR\"|" "$ENV_FILE"
            else
                sed -i "s|^PATH=\"\\(.*\\)\"|PATH=\"$DIR:\\1\"|" "$ENV_FILE"
            fi
            echo -e "${GREEN}✓${NC} Added $DIR to system PATH in $ENV_FILE"
        fi
    else
        # Add new PATH line
        echo "PATH=\"$DIR:\$PATH\"" >> "$ENV_FILE"
        echo -e "${GREEN}✓${NC} Created system PATH entry in $ENV_FILE"
    fi
}

# Main script logic
main() {
    # Parse arguments
    local DIRECTORY=""
    local ADD_TO_BASHRC=false
    local ADD_TO_PROFILE=false
    local ADD_TO_ROOT=false
    local ADD_TO_SYSTEM=false
    local CLEAN_DUPS=false
    local POSITION="prepend"
    local CHECK_ONLY=false
    local PROFILE_FILE="$HOME/.bashrc"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -bashrc)
                ADD_TO_BASHRC=true
                PROFILE_FILE="$HOME/.bashrc"
                ;;
            -profile)
                ADD_TO_PROFILE=true
                PROFILE_FILE="$HOME/.profile"
                ;;
            -root)
                ADD_TO_ROOT=true
                PROFILE_FILE="/root/.bashrc"
                ;;
            -system)
                ADD_TO_SYSTEM=true
                ;;
            -dups)
                CLEAN_DUPS=true
                ;;
            -prepend)
                POSITION="prepend"
                ;;
            -append)
                POSITION="append"
                ;;
            -check)
                CHECK_ONLY=true
                ;;
            -help|--help|-h)
                show_usage
                return 0
                ;;
            -*)
                echo -e "${RED}✗${NC} Unknown option: $1"
                echo "Use -help for usage information"
                return 1
                ;;
            *)
                if [[ -z "$DIRECTORY" ]]; then
                    DIRECTORY="$1"
                else
                    echo -e "${RED}✗${NC} Multiple directories specified. Use one directory at a time."
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # Show usage if no directory specified
    if [[ -z "$DIRECTORY" ]]; then
        show_usage
        return 0
    fi
    
    # Resolve directory path
    if [[ "$DIRECTORY" == /* ]]; then
        # Absolute path
        RESOLVED_DIR="$DIRECTORY"
    elif [[ "$DIRECTORY" == ~* ]]; then
        # Home-relative path
        RESOLVED_DIR="${DIRECTORY/#\~/$HOME}"
    else
        # Relative path - make it absolute based on current directory
        RESOLVED_DIR="$(realpath "$DIRECTORY" 2>/dev/null)"
        if [[ $? -ne 0 ]]; then
            RESOLVED_DIR="$PWD/$DIRECTORY"
        fi
    fi
    
    # Verify directory exists
    if [[ ! -d "$RESOLVED_DIR" ]]; then
        echo -e "${RED}✗${NC} Directory does not exist: $RESOLVED_DIR"
        return 1
    fi
    
    echo -e "${BLUE}Processing:${NC} $RESOLVED_DIR"
    
    # Check if directory is already in PATH
    if is_in_path "$RESOLVED_DIR"; then
        echo -e "${GREEN}✓${NC} Directory is already in current PATH"
        if [[ "$CHECK_ONLY" == true ]]; then
            return 0
        fi
    else
        echo -e "${YELLOW}!${NC} Directory is not in current PATH"
        if [[ "$CHECK_ONLY" == true ]]; then
            return 1
        fi
    fi
    
    # Check if script was sourced
    if ! (return 0 2>/dev/null); then
        echo -e "\n${RED}WARNING:${NC} This script was not sourced!"
        echo -e "  The script must be sourced to modify the current session PATH."
        echo -e "  Usage: ${GREEN}source add-path.sh $DIRECTORY${NC} or ${GREEN}. add-path.sh $DIRECTORY${NC}"
        if [[ "$ADD_TO_BASHRC" == true ]] || [[ "$ADD_TO_PROFILE" == true ]] || [[ "$ADD_TO_ROOT" == true ]] || [[ "$ADD_TO_SYSTEM" == true ]]; then
            echo -e "  Profile modifications would still work, but current session won't be updated."
        fi
        return 1
    fi
    
    # Clean duplicates if requested (do this first)
    if [[ "$CLEAN_DUPS" == true ]]; then
        clean_path
    fi
    
    # Add to current session PATH
    add_to_current_path "$RESOLVED_DIR" "$POSITION"
    
    # Add to profile files if requested
    if [[ "$ADD_TO_SYSTEM" == true ]]; then
        add_to_system "$RESOLVED_DIR" "$POSITION"
    fi
    
    if [[ "$ADD_TO_BASHRC" == true ]] || [[ "$ADD_TO_PROFILE" == true ]] || [[ "$ADD_TO_ROOT" == true ]]; then
        add_to_profile "$RESOLVED_DIR" "$PROFILE_FILE" "$POSITION"
    fi
    
    echo -e "\n${GREEN}Current PATH:${NC}"
    echo "$PATH" | tr ':' '\n' | nl -nln -w3 -s': '
}

# Run main function with all arguments
main "$@"
