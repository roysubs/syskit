#!/bin/bash
# Author: Roy Wiseman 2025-05

echo "🚀 Starting git-secrets installation and setup..."

# --- Configuration ---
# Set the installation prefix. Binaries will go to $PREFIX/bin, manpages to $PREFIX/share/man
INSTALL_PREFIX="$HOME/.local"
# The actual directory where binaries will be placed
BIN_DIR="$INSTALL_PREFIX/bin"
# Temporary directory for cloning the repository
TMP_DIR=$(mktemp -d)

# Function to clean up the temporary directory on exit
cleanup() {
    echo "🧹 Cleaning up temporary directory: $TMP_DIR"
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT # Register cleanup function to run on script exit (normal or error)

# --- Prerequisite Check ---
echo ""
echo "--- 0. Checking Prerequisites ---"
command -v git >/dev/null 2>&1 || { echo "❌ Error: 'git' is not installed. Please install git and try again." >&2; exit 1; }
command -v make >/dev/null 2>&1 || { echo "❌ Error: 'make' is not installed. Please install make (e.g., sudo apt-get install make) and try again." >&2; exit 1; }
echo "✅ Git and Make are available."

# --- Installation ---
echo ""
echo "--- 1. Installing git-secrets ---"

# Ensure the local bin directory exists (make install will create $PREFIX/bin if it doesn't exist)
echo "Ensuring installation directory '$BIN_DIR' can be created by 'make install' under '$INSTALL_PREFIX'..."
mkdir -p "$INSTALL_PREFIX" # Ensure the parent prefix exists
if [ $? -ne 0 ]; then
    echo "❌ Error: Could not create directory '$INSTALL_PREFIX'. Exiting."
    exit 1
fi
# mkdir -p "$BIN_DIR" # Not strictly needed as make install with PREFIX should handle it.

echo ""
echo "Cloning git-secrets repository into '$TMP_DIR/git-secrets'..."
git clone https://github.com/awslabs/git-secrets.git "$TMP_DIR/git-secrets"
if [ $? -ne 0 ]; then
    echo "❌ Error: Could not clone the git-secrets repository. Exiting."
    exit 1
fi
echo "Repository cloned."

echo ""
echo "Navigating to cloned repository and installing git-secrets..."
cd "$TMP_DIR/git-secrets" || { echo "❌ Error: Could not cd into '$TMP_DIR/git-secrets'. Exiting."; exit 1; }

echo "Running 'make install PREFIX=$INSTALL_PREFIX'..."
# This will install 'git-secrets' to $INSTALL_PREFIX/bin/git-secrets
# and man pages to $INSTALL_PREFIX/share/man/man1/git-secrets.1
make install PREFIX="$INSTALL_PREFIX"
if [ $? -ne 0 ]; then
    echo "❌ Error: 'make install' failed. Please check for errors above."
    echo "Ensure you have necessary build tools and permissions."
    exit 1
fi
echo "✅ 'git-secrets' installed successfully to '$BIN_DIR'."

# Navigate out of temp dir before it's removed (optional, good practice)
cd "$HOME"

# --- PATH Configuration ---
echo ""
echo "--- 2. Configuring PATH ---"

# Ensure the BIN_DIR is on the PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo "'$BIN_DIR' is not found in your current PATH."
    echo "To make 'git-secrets' available in new terminal sessions, add the following line to your shell configuration file (e.g., ~/.bashrc, ~/.zshrc):"
    echo ""
    echo "  export PATH=\"$BIN_DIR:\$PATH\"" # Using BIN_DIR directly
    echo ""
    echo "Adding it to ~/.bashrc for this session and future bash sessions..."
    # Add to .bashrc if not already there
    if [ -f "$HOME/.bashrc" ] && ! grep -Fxq "export PATH=\"$BIN_DIR:\$PATH\"" "$HOME/.bashrc"; then
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
        echo "Line added to ~/.bashrc."
    elif [ -f "$HOME/.bashrc" ] && grep -Fxq "export PATH=\"$BIN_DIR:\$PATH\"" "$HOME/.bashrc"; then
        echo "Line already exists in ~/.bashrc."
    else
        echo "Could not find ~/.bashrc to update automatically. Please add the export line manually."
    fi
    echo "You will need to source your .bashrc (e.g., 'source ~/.bashrc') or open a new terminal for the PATH change to take full effect."
    echo "For this current session, attempting to add it to PATH now..."
    export PATH="$BIN_DIR:$PATH"
else
    echo "'$BIN_DIR' is already in your PATH."
fi

# Check if git-secrets is available on the PATH
echo ""
echo "Verifying 'git-secrets' command availability..."
if ! command -v git-secrets &>/dev/null; then
    echo "❌ Error: 'git-secrets' command is not available on the PATH even after attempting to update it."
    echo "Please ensure '$BIN_DIR' is correctly added to your PATH and your shell configuration file is sourced."
    echo "Current PATH: $PATH"
    exit 1
fi
echo "✅ 'git-secrets' command is now available."
GIT_SECRETS_VERSION=$(git-secrets --version 2>&1) || GIT_SECRETS_VERSION="N/A (Note: git-secrets does not have a --version flag, it outputs help)"
echo "To check 'git-secrets', try: git-secrets --help (it doesn't have a --version flag)"


# --- Global GitSecrets Configuration (Run Once) ---
echo ""
echo "--- 3. Global GitSecrets Configuration ---"
echo "Adding AWS default patterns to global git-secrets configuration..."
echo "This registers common AWS secret patterns to be checked in all your repos where hooks are installed."

git secrets --add-provider --global
if [ $? -ne 0 ]; then
    echo "⚠️ Warning: Could not add global provider. This might be okay if already configured or if you prefer per-repo setup."
else
    echo "Global provider added."
fi

git secrets --register-aws --global
if [ $? -ne 0 ]; then
    echo "⚠️ Warning: Could not register AWS patterns globally. This might be okay if already configured."
else
    echo "AWS patterns registered globally."
fi
echo "Global configuration complete."

# --- Using git-secrets (Information & Examples) ---
# (This section remains the same as in the previous good version)
echo ""
echo "--- How to Use git-secrets ---"
echo "✅ 'git-secrets' is installed and globally configured with AWS patterns."
echo ""
echo "To use git-secrets in a specific repository:"
echo "1. Navigate to your git repository:"
echo "   cd /path/to/your/repo"
echo ""
echo "2. Install git hooks for the current repository (IMPORTANT):"
echo "   git secrets --install -f"
echo "   (This will add a pre-commit hook. The '-f' overwrites existing hooks created by git-secrets.)"
echo ""
echo "3. Add custom secret patterns (optional):"
echo "   git secrets --add 'MY_SECRET_PATTERN[0-9]+'"
echo "   git secrets --add --allowed 'EXAMPLE_NON_SECRET_PATTERN123' (to allow specific known strings)"
echo ""
echo "Now, git-secrets will automatically scan your commits for secrets!"

echo ""
echo "--- Common `git-secrets` Commands ---"
echo "  Scan specific files:"
echo "    git secrets --scan /path/to/file1.txt /path/to/another/file.py"
echo ""
echo "  Scan all files in the current directory (recursively):"
echo "    git secrets --scan -r ."
echo ""
echo "  Scan your entire Git history (can be slow for large repos):"
echo "    git secrets --scan-history"
echo ""
echo "  List current configuration (patterns, etc.):"
echo "    git secrets --list"
echo ""
echo "  The following command is useful for scanning currently staged files before a commit:"
echo "    git diff --cached --name-only --diff-filter=ACM | xargs -r -I {} git secrets --scan {}"
echo "    (This is often what the pre-commit hook does.)"
echo ""
echo "For more information, visit: https://github.com/awslabs/git-secrets"
echo ""
echo "🎉 Script finished!"
