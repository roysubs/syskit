#!/bin/bash
# Author: Roy Wiseman 2025-01
# Tool to run a pip package inside a temporary venv
#
# PURPOSE: This script helps you safely run Python packages from PyPI without
# polluting your system Python installation. Modern Debian/Ubuntu systems use
# "externally managed" Python environments, which means 'pip install' commands
# fail with errors. This script creates isolated temporary virtual environments
# for running packages, solving that problem.

set -e  # Exit on error

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to show detailed help about Debian's pip restrictions
show_debian_help() {
    echo ""
    echo -e "${YELLOW}${BOLD}⚠️  Debian blocks system-wide 'pip install' commands${NC}"
    echo ""
    echo -e "${BLUE}Reason:${NC} Debian marks its Python as an ${BOLD}externally managed environment${NC}"
    echo -e "to prevent breaking system packages installed via ${BOLD}apt${NC}."
    echo -e "You'll see an error like:"
    echo -e "${RED}error: externally-managed-environment${NC}"
    echo ""
    echo -e "${GREEN}You have several safe options:${NC}"
    echo ""
    echo -e " ${BOLD}1.${NC} Use a ${BOLD}virtual environment (recommended):${NC}"
    echo -e "    python3 -m venv ~/.venv && source ~/.venv/bin/activate"
    echo -e "    pip install --upgrade pip"
    echo -e "    pip install <package>"
    echo ""
    echo -e "    (Add this to ~/.bashrc to auto-activate:)"
    echo -e "    ${BLUE}source ~/.venv/bin/activate${NC}"
    echo ""
    echo -e " ${BOLD}2.${NC} Install packages in your user site (no root needed):"
    echo -e "    pip install --user <package>"
    echo -e "    → goes into ~/.local/lib/python3.X/site-packages"
    echo ""
    echo -e " ${BOLD}3.${NC} Temporarily bypass Debian's restriction (unsafe but possible):"
    echo -e "    PIP_BREAK_SYSTEM_PACKAGES=1 pip install <package>"
    echo ""
    echo -e " ${BOLD}4.${NC} Permanently allow pip to modify the system (not recommended!):"
    echo -e "    echo 'export PIP_BREAK_SYSTEM_PACKAGES=1' >> ~/.bashrc"
    echo -e "    source ~/.bashrc"
    echo ""
    echo -e " ${BOLD}5.${NC} (Extreme) Remove the management lock file:"
    echo -e "    sudo rm /usr/lib/python3*/EXTERNALLY-MANAGED"
    echo -e "    ⚠️  This may break Debian's package management!"
    echo ""
    echo -e "${GREEN}Best practice:${NC} use virtual environments or pipx to stay clean and safe."
    echo ""
    echo -e "${BLUE}This script (venv-run.sh) automates option #1 for you!${NC}"
    echo ""
    echo -e "${BLUE}Ref: Debian Python policy (Bookworm+):${NC} https://wiki.debian.org/Python"
    echo ""
}

# Function to show usage
show_usage() {
    local script_name=$(basename "$0")
    echo ""
    echo "===================================="
    echo "  venv-run - Python Package Runner"
    echo "===================================="
    echo ""
    print_info "This script runs Python packages in isolated temporary environments."
    echo ""
    echo "Why use this?"
    echo "  • Modern Debian/Ubuntu prevents 'pip install' for security reasons"
    echo "  • This creates a clean, temporary virtual environment"
    echo "  • No system pollution - everything is isolated"
    echo "  • Automatically cleans up after use (or keeps if you want)"
    echo ""
    echo "What about pipx?"
    echo -e "  • ${BOLD}pipx${NC} installs apps PERMANENTLY in isolated environments"
    echo -e "  • ${BOLD}venv-run${NC} (this script) creates TEMPORARY isolated environments"
    echo ""
    echo "  Use pipx for: tools you want to keep (like black, poetry, httpie)"
    echo "  Use venv-run for: one-time use, testing, or temporary tools"
    echo ""
    echo "  Example: 'pipx install httpie' → httpie always available"
    echo "           'venv-run httpie https://...' → use once, auto-cleanup"
    echo ""
    echo "Usage: $script_name [options] <package-name> [parameters for the package]"
    echo "       $script_name -p <dir>      # Just activate/create a venv (no package)"
    echo ""
    echo "Options:"
    echo "  -p, --path <dir>    Install to a specific directory (e.g., ~/myvenv)"
    echo "  -k, --keep          Keep the environment after running (don't ask)"
    echo "  -c, --cleanup       Clean up the environment after running (don't ask)"
    echo "  -h, --help          Show this help message and Debian pip explanation"
    echo ""
    echo "Note: All options must come BEFORE the package name."
    echo "      Everything after the package name is passed to that package."
    echo ""
    echo "Special Mode:"
    echo "  $script_name -p ~/myvenv"
    echo "    └─ Create or activate a venv without installing anything"
    echo ""
    echo "Real Working Examples:"
    echo ""
    echo "  $script_name httpie https://httpbin.org/get"
    echo "    └─ Modern HTTP client for testing APIs"
    echo ""
    echo "  $script_name yt-dlp --list-formats 'https://youtube.com/watch?v=dQw4w9WgXcQ'"
    echo "    └─ YouTube downloader (shows available formats)"
    echo ""
    echo "  $script_name pipenv --version"
    echo "    └─ Python dependency manager"
    echo ""
    echo "  $script_name -p ~/my-http-env httpie https://httpbin.org/get"
    echo "    └─ Install httpie to a specific directory for reuse"
    echo ""
    echo "  $script_name -k httpie https://httpbin.org/json"
    echo "    └─ Keep environment active after running (no prompt)"
    echo ""
    echo "  $script_name -c yt-dlp --version"
    echo "    └─ Auto cleanup after running (no prompt)"
    echo ""
    echo "If you're already in a venv, this script will just install and run there."
    echo ""
}

# Variables for flags
CUSTOM_PATH=""
FORCE_KEEP=false
FORCE_CLEANUP=false
ALREADY_IN_VENV=false
SHOW_HELP=false

# Parse arguments - stop at first non-option argument (the package name)
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--path)
            CUSTOM_PATH="$2"
            shift 2
            ;;
        -k|--keep)
            FORCE_KEEP=true
            shift
            ;;
        -c|--cleanup)
            FORCE_CLEANUP=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        -*)
            # If we've already seen a positional arg, this is a parameter for the package
            if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
                POSITIONAL_ARGS+=("$1")
                shift
            else
                echo "Unknown option: $1"
                echo "Use -h or --help to see usage."
                exit 1
            fi
            ;;
        *)
            # First non-option argument is the package name
            # Everything after this is a parameter for the package
            POSITIONAL_ARGS+=("$@")
            break
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
    show_usage
    show_debian_help
    exit 0
fi

# Special case: if only --path is specified, activate/create that venv and enter it
if [ -n "$CUSTOM_PATH" ] && [ -z "$1" ]; then
    VENV_DIR=$(eval echo "$CUSTOM_PATH")
    
    if [ -f "$VENV_DIR/bin/activate" ]; then
        print_info "Activating existing virtual environment: $VENV_DIR"
        echo ""
        
        # Show what's installed in the venv
        print_info "Installed packages in this venv:"
        "$VENV_DIR/bin/pip" list 2>/dev/null || echo "  (unable to list packages)"
        echo ""
        
        print_success "Entering the virtual environment..."
        echo ""
        print_info "Type 'exit' to leave the venv and return to your shell"
        echo ""
        # Export VENV_DIR so it's available in the subshell
        export VENV_DIR
        # Load user's .bashrc first, then activate venv
        exec bash --rcfile <(cat <<'EOF'
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
source "$VENV_DIR/bin/activate"
trap deactivate EXIT
EOF
)
    else
        print_info "Creating new virtual environment: $VENV_DIR"
        echo ""
        python3 -m venv "$VENV_DIR"
        print_success "Virtual environment created!"
        echo ""
        
        print_info "Installed packages (fresh venv):"
        "$VENV_DIR/bin/pip" list 2>/dev/null || echo "  (unable to list packages)"
        echo ""
        
        print_info "Entering the virtual environment..."
        echo ""
        print_info "Type 'exit' to leave the venv and return to your shell"
        echo ""
        # Export VENV_DIR so it's available in the subshell
        export VENV_DIR
        # Load user's .bashrc first, then activate venv
        exec bash --rcfile <(cat <<'EOF'
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
source "$VENV_DIR/bin/activate"
trap deactivate EXIT
EOF
)
    fi
fi

# Check if the user provided the package name
if [ -z "$1" ]; then
    show_usage
    exit 1
fi

# Check if already in a virtual environment
if [ -n "$VIRTUAL_ENV" ]; then
    ALREADY_IN_VENV=true
    print_info "Already in a virtual environment: $VIRTUAL_ENV"
    print_info "Will install the package here and run it."
    echo ""
fi

# Ensure python3-venv is installed (only if not in venv)
if [ "$ALREADY_IN_VENV" = false ] && ! dpkg -l 2>/dev/null | grep -q "^ii.*python3-venv"; then
    echo ""
    print_warning "python3-venv is not installed on your system."
    echo ""
    print_info "What is python3-venv?"
    echo "  python3-venv is Python's built-in tool for creating virtual environments."
    echo "  This script uses it to create isolated environments for packages."
    echo ""
    print_info "This will install: python3-venv"
    echo "  Size: ~10 KB (very small)"
    echo "  Time: ~5 seconds"
    echo ""
    read -p "Do you want to proceed with the installation? [y/N] " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled. Exiting..."
        exit 0
    fi
    
    echo ""
    print_info "Installing python3-venv..."
    sudo apt update && sudo apt install -y python3-venv
    
    print_success "python3-venv installed successfully!"
    echo ""
fi

# Extract package name and parameters
PACKAGE=$1
shift  # Remove the package name from arguments
PARAMS="$@"  # Remaining arguments to pass to the package

# Determine venv directory
if [ -n "$CUSTOM_PATH" ]; then
    # User specified a custom path
    VENV_DIR=$(eval echo "$CUSTOM_PATH")  # Expand ~ if present
    VENV_IS_TEMP=false
    print_info "Using custom directory: $VENV_DIR"
elif [ "$ALREADY_IN_VENV" = true ]; then
    # Already in a venv, use it
    VENV_DIR="$VIRTUAL_ENV"
    VENV_IS_TEMP=false
else
    # Create temporary directory
    VENV_DIR=$(mktemp -d -t venv-XXXXXX)
    VENV_IS_TEMP=true
fi

# Cleanup function (only for temp directories)
cleanup() {
    if [ "$VENV_IS_TEMP" = true ] && [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        print_info "Cleaned up temporary environment"
    fi
}

# If not already in venv, set up the environment
if [ "$ALREADY_IN_VENV" = false ]; then
    echo ""
    print_info "Creating isolated environment for: $PACKAGE"
    echo ""
    
    # Create virtual environment if it doesn't exist or is invalid
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        print_info "Setting up virtual environment in $VENV_DIR..."
        # Remove any existing incomplete venv
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
    else
        print_info "Using existing virtual environment in $VENV_DIR..."
    fi
    
    # Activate the virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip quietly
    pip install --quiet --upgrade pip
fi

# Install the specified package
print_info "Installing $PACKAGE..."
pip install --quiet "$PACKAGE" || {
    print_error "Failed to install $PACKAGE"
    echo ""
    echo "Possible reasons:"
    echo "  • Package name is incorrect (check PyPI: https://pypi.org)"
    echo "  • Network connection issues"
    echo "  • Package has incompatible dependencies"
    echo ""
    
    # Cleanup if temp venv
    if [ "$VENV_IS_TEMP" = true ]; then
        cleanup
    fi
    exit 1
}

print_success "Package installed successfully!"
echo ""

# Run the package with the provided parameters
if [ -n "$PARAMS" ]; then
    print_info "Running: $PACKAGE $PARAMS"
else
    print_info "Running: $PACKAGE (no parameters)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run the package
$PACKAGE $PARAMS

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Handle environment cleanup/keep based on context
if [ "$ALREADY_IN_VENV" = true ]; then
    # Already in a venv, just inform and exit
    print_success "Done! You're still in your virtual environment."
    echo ""
elif [ "$FORCE_KEEP" = true ]; then
    # User specified --keep flag - stay in the venv
    print_success "Environment kept as requested (-k/--keep flag)."
    echo ""
    echo "Virtual environment location: $VENV_DIR"
    echo ""
    
    # Show what's installed
    print_info "Installed packages:"
    pip list 2>/dev/null || echo "  (unable to list packages)"
    echo ""
    
    print_warning "Starting a new shell with the virtual environment active..."
    print_info "To exit the venv and return to your normal shell, type: exit"
    echo ""
    # Export VENV_DIR so it's available in the subshell
    export VENV_DIR
    # Load user's .bashrc first to get their colored prompt, then activate venv
    exec bash --rcfile <(cat <<'EOF'
# Load user's bashrc to get their prompt and settings
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
# Now activate the venv - it will prepend (venv) to the existing colored prompt
source "$VENV_DIR/bin/activate"
trap deactivate EXIT
EOF
)
elif [ "$FORCE_CLEANUP" = true ]; then
    # User specified --cleanup flag
    deactivate 2>/dev/null || true
    if [ "$VENV_IS_TEMP" = true ]; then
        cleanup
    fi
    print_success "Environment cleaned up as requested (-c/--cleanup flag)."
elif [ "$VENV_IS_TEMP" = false ]; then
    # Custom path was used, ask what to do
    print_info "Custom environment created at: $VENV_DIR"
    echo ""
    echo "  [k] Keep environment active (you can run more commands)"
    echo "  [d] Deactivate but keep the directory"
    echo "  [r] Remove the directory entirely"
    echo ""
    read -p "Your choice [k/d/R]: " -n 1 -r choice
    echo ""
    echo ""
    
    if [[ $choice =~ ^[Kk]$ ]]; then
        print_success "Environment is still active!"
        echo ""
        
        print_info "Installed packages:"
        pip list 2>/dev/null || echo "  (unable to list packages)"
        echo ""
        
        echo "You can now run other commands. For example:"
        echo "  • pip list          (see installed packages)"
        echo "  • pip install <pkg> (install another package)"
        echo "  • $PACKAGE          (run the package again)"
        echo ""
        print_warning "Type 'exit' to leave the environment."
        echo ""
        echo "To reuse this environment later:"
        echo "  source $VENV_DIR/bin/activate"
        echo ""
        echo "Press Enter to continue..."
        read
        # Export VENV_DIR so it's available in the subshell
        export VENV_DIR
        exec bash --rcfile <(cat <<'EOF'
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
source "$VENV_DIR/bin/activate"
trap deactivate EXIT
EOF
)
    elif [[ $choice =~ ^[Dd]$ ]]; then
        deactivate 2>/dev/null || true
        print_success "Environment deactivated but directory kept at: $VENV_DIR"
        echo ""
        echo "To reuse this environment later:"
        echo "  source $VENV_DIR/bin/activate"
    else
        deactivate 2>/dev/null || true
        rm -rf "$VENV_DIR"
        print_success "Environment deactivated and directory removed."
    fi
else
    # Temporary environment, ask whether to keep or clean up
    print_info "What would you like to do now?"
    echo ""
    echo "  [y] Keep environment active (you can run more commands)"
    echo "  [n] Exit and clean up (default)"
    echo ""
    read -p "Your choice [y/N]: " -n 1 -r choice
    echo ""
    
    if [[ $choice =~ ^[Yy]$ ]]; then
        echo ""
        print_success "Environment is still active!"
        echo ""
        
        print_info "Installed packages:"
        pip list 2>/dev/null || echo "  (unable to list packages)"
        echo ""
        
        echo "You can now run other commands. For example:"
        echo "  • pip list          (see installed packages)"
        echo "  • pip install <pkg> (install another package)"
        echo "  • $PACKAGE          (run the package again)"
        echo ""
        print_warning "Type 'exit' to leave and clean up the environment."
        echo ""
        echo "Press Enter to continue..."
        read
        
        # Export VENV_DIR so it's available in the subshell
        export VENV_DIR
        # Start a new shell in the venv with auto-cleanup
        exec bash --rcfile <(cat <<'EOF'
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
source "$VENV_DIR/bin/activate"
trap 'deactivate; rm -rf "$VENV_DIR"' EXIT
EOF
)
    else
        deactivate 2>/dev/null || true
        cleanup
        print_success "Environment deactivated and cleaned up."
    fi
fi
