#!/bin/bash
# Author: Roy Wiseman 2025-05

# github-gh-auth-login.sh
# This script helps you log into GitHub CLI (`gh`) using a Personal Access Token (PAT),
# avoiding the need for a web browser, and checks if gh is installed.

# This will mimic Ctrl+L to quick-clear the screen *without* removing history
# This may not work in GNOME terminal, but is useful in many other terminals
softclear() { printf '\033[H\033[2J'; }

softclear

echo -e "GitHub CLI Authentication Script\n=================================="

# --- Check if gh is installed ---
echo -e "\nChecking for GitHub CLI (gh)..."
if ! command -v gh &> /dev/null; then
    echo -e "\nError: GitHub CLI (gh) is not found in your PATH."
    echo "gh is required for this script to work."
    echo -e "\nPlease install gh first. You can find installation instructions here:"
    echo "  https://cli.github.com/manual/installation"
    echo -e "\nFor Debian/Ubuntu/Raspbian:"
    echo "  sudo apt update"
    echo "  sudo apt install gh -y"
    echo -e "\nFor Fedora/CentOS/RHEL (using dnf):"
    echo "  sudo dnf install 'dnf-command(config-manager)'"
    echo "  sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo"
    echo "  sudo dnf install gh"
    echo -e "\nFor macOS (using Homebrew):"
    echo "  brew install gh"
    echo -e "\nPlease install gh and run the script again."
    exit 1 # Exit with an error code
fi
echo "GitHub CLI (gh) found."

echo -e "\nThis script will guide you through logging into GitHub CLI (gh)\nwithout needing a web browser."
echo -e "Instead, we will use a Personal Access Token (PAT).\n"
read -p "Press Enter to continue..."

softclear

# Step 1: Explain why a PAT is needed and how to generate it
echo -e "Step 1: Generate a Personal Access Token (PAT)"
echo -e "---------------------------------------------"
echo -e "Since you are using SSH from a remote terminal, GitHub CLI would normally\ntry to open a web browser, which we want to avoid."
echo -e "Instead, we'll use a PAT to authenticate.\n"
echo -e "Follow these steps to generate a PAT:"
echo -e "  1. Open GitHub in a browser on your local machine."
echo -e "  2. Go to: https://github.com/settings/tokens"
echo -e "  3. Click 'Generate new token (classic)'."
echo -e "  4. Give it a name, like 'GitHub CLI Auth'."
echo -e "  5. Select the following permissions:"
echo -e "       - 'repo' (for repository access)"
echo -e "       - 'read:org' (if needed for organizational repositories)"
echo -e "       - 'write:public_key' (if using SSH authentication)."
echo -e "  6. Click 'Generate token' and copy it."
echo -e "  7. Keep it safe! You will only see it once.\n"
read -p "Press Enter once you've generated the token..."

softclear

# Step 2: Use the token to authenticate
echo -e "Step 2: Authenticate GitHub CLI (gh) with the PAT"
echo -e "---------------------------------------------------"
echo -e "Now that you have your token, we will use it to log in."
echo -e "Please paste your Personal Access Token below and press Enter:"
read -s GH_PAT # Read the token silently into the variable GH_PAT

# Check if a token was actually entered
if [ -z "$GH_PAT" ]; then
    echo -e "\nNo token was entered. Authentication cancelled."
    exit 1 # Exit with an error code
fi

echo -e "\nAttempting to authenticate gh using the provided token..."

# Finally, run the `gh auth login` command, piping the token to it
# This avoids the browser prompt and uses the token directly.
echo "$GH_PAT" | gh auth login --with-token

# Check the exit status of the gh auth login command
if [ $? -eq 0 ]; then
    echo -e "\nGitHub CLI authentication successful!"
    echo "You should now be able to use gh commands."
else
    echo -e "\nGitHub CLI authentication failed."
    echo "Please double-check your Personal Access Token and ensure it has the correct permissions."
    echo "You can try running 'gh auth status' to see if any authentication exists."
fi

# It's good practice to unset the variable containing the sensitive token
unset GH_PAT

echo -e "\nScript finished."
