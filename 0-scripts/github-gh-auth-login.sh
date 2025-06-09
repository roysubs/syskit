#!/bin/bash
# Author: Roy Wiseman, with modifications by Google's Gemini
# Version: 2.1
# Date: 2025-06-09

# github-gh-auth.sh
# A user-friendly script to explain and handle GitHub CLI (gh) authentication.
# It checks for both 'gh' and 'git' dependencies, detects SSH sessions,
# and offers the most appropriate auth method with clearer instructions.

# A softer clear that doesn't wipe the scrollback buffer.
softclear() {
    printf '\033[H\033[2J'
}

# --- Function to Explain GitHub CLI ---
explain_gh() {
    echo "-------------------------------------"
    echo "What is the GitHub CLI ('gh')?"
    echo "-------------------------------------"
    echo
    echo "'gh' is the official command-line tool for GitHub."
    echo "It brings pull requests, issues, Actions, and other GitHub features"
    echo "to your terminal, so you can do all your work in one place."
    echo
    echo "With 'gh', you can:"
    echo "  - Manage repositories (cloning, creating, forking)"
    echo "  - Handle pull requests and issues directly from the terminal"
    echo "  - Interact with GitHub Actions workflows"
    echo "  - Authenticate securely to work with private repositories."
    echo
    echo "This script will help you get authenticated."
    echo
    read -p "Press Enter to continue..."
}

# --- Main Script Logic ---
softclear
echo "=================================="
echo "GitHub CLI (gh) Authentication"
echo "=================================="
echo

# --- Step 1: Explain what gh is ---
explain_gh
softclear

# --- Step 2: Check for Prerequisites (gh and git) ---
echo "--> Checking for required tools: 'gh' and 'git'..."

# Check for GitHub CLI (gh)
if ! command -v gh &> /dev/null; then
    echo -e "\n❌ Error: GitHub CLI ('gh') is not found."
    echo "   'gh' is required for this script to work."
    echo "   Please install it first: https://cli.github.com/manual/installation"
    echo "   Common commands:"
    echo "     Debian/Ubuntu: sudo apt update && sudo apt install gh -y"
    echo "     Fedora/RHEL:   sudo dnf install gh"
    echo "     macOS (brew):  brew install gh"
    exit 1
fi

# Check for Git
if ! command -v git &> /dev/null; then
    echo -e "\n❌ Error: Git is not found."
    echo "   The GitHub CLI ('gh') requires Git to be installed."
    echo "   Please install Git first. You can find instructions here:"
    echo "   https://git-scm.com/book/en/v2/Getting-Started-Installing-Git"
    echo "   Common commands:"
    echo "     Debian/Ubuntu: sudo apt install git -y"
    echo "     Fedora/RHEL:   sudo dnf install git"
    echo "     macOS (brew):  brew install git"
    exit 1
fi

echo "✅ All required tools ('gh' and 'git') are installed."
echo

# --- Step 3: Detect Environment and Choose Auth Method ---
auth_method=""
echo "--> Choosing an authentication method..."

# Detect if we are in an SSH session
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "It looks like you're connected via SSH."
    echo "The recommended method is using a Personal Access Token (PAT)."
    read -p "Do you want to try the web browser login anyway? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        auth_method="web"
    else
        auth_method="pat"
    fi
else
    echo "It looks like you're on a local machine with a graphical UI."
    echo "The easiest method is to log in with your web browser."
    read -p "Do you want to proceed with the web browser login? (Y/n): " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        auth_method="pat"
    else
        auth_method="web"
    fi
fi

echo
read -p "Press Enter to begin the selected authentication process..."
softclear

# --- Step 4: Perform Authentication ---

if [ "$auth_method" == "web" ]; then
    # --- Web-based Authentication ---
    echo "-------------------------------------"
    echo "Step: Authenticate via Web Browser"
    echo "-------------------------------------"
    echo
    echo "The script will now launch GitHub CLI's interactive login."
    echo
    echo "You will be asked a few setup questions first:"
    echo "  1. What account to log into? (Choose GitHub.com)"
    echo "  2. Preferred protocol for Git? (HTTPS is a safe default)"
    echo "  3. Authenticate Git with your credentials? (Choose Yes)"
    echo
    echo "After answering, 'gh' will give you a ONE-TIME CODE."
    echo
    echo "Finally, it will open a browser window. Paste the code there and"
    echo "click 'Authorize' to grant access, as shown in the image you provided."
    echo
    read -p "Press Enter to start the web login..."

    # The -w flag hints at a web login, but gh auth login is fully interactive.
    # We will let the user interact with it directly.
    if gh auth login; then
        echo -e "\n✅ GitHub CLI authentication successful!"
    else
        echo -e "\n❌ GitHub CLI authentication failed."
        echo "   Please review the error messages above and try again."
    fi

elif [ "$auth_method" == "pat" ]; then
    # --- PAT-based Authentication ---
    echo "------------------------------------------------"
    echo "Step 1: Generate a Personal Access Token (PAT)"
    echo "------------------------------------------------"
    echo
    echo "Follow these steps on a machine with a web browser:"
    echo "  1. Open this URL: https://github.com/settings/tokens/new"
    echo "  2. For 'Note', give the token a name (e.g., 'gh-cli-on-server')."
    echo "  3. Set an expiration date (highly recommended for security)."
    echo "  4. Select the following 'scopes' to match the web-auth permissions:"
    echo "     - 'repo'        (Full control of repositories)"
    echo "     - 'read:org'    (Read org and team membership)"
    echo "     - 'workflow'    (Manage GitHub Actions)"
    echo "     - 'gist'        (Create gists)"
    echo "  5. Click 'Generate token' and COPY THE TOKEN immediately."
    echo
    read -p "Press Enter once you have copied your token..."
    softclear

    echo "------------------------------------------------"
    echo "Step 2: Authenticate gh with your PAT"
    echo "------------------------------------------------"
    echo
    echo "Please paste your Personal Access Token and press Enter:"
    read -s GH_PAT

    if [ -z "$GH_PAT" ]; then
        echo -e "\nNo token was entered. Authentication cancelled."
        exit 1
    fi

    echo -e "\n--> Attempting to authenticate..."
    if echo "$GH_PAT" | gh auth login --with-token; then
        echo -e "\n✅ GitHub CLI authentication successful!"
    else
        echo -e "\n❌ GitHub CLI authentication failed. Please check your token."
    fi
    unset GH_PAT
fi

echo -e "\nTo verify your status, you can run: gh auth status"
echo "Script finished."
