#!/bin/bash
# Author: Roy Wiseman 2025-02 (Adapted for HTTPS)

# Connect a git project to GitHub using HTTPS.
# This script sets up the Git Credential Helper (so you don't have to type passwords constantly)
# and switches the project to HTTPS if it was cloned via SSH.

set -e

# Color functions
red() { echo -e "\033[1;31m$*\033[0m"; }
green() { echo -e "\033[1;32m$*\033[0m"; }
yellow() { echo -e "\033[1;33m$*\033[0m"; }

# Function to run commands and show them
run_cmd() {
  green "\$ $*"
  eval "$@"
}

# Function to pause with a message
pause_msg() {
    echo -e "\n\033[1;33m$1\033[0m"
    read -rp "Press Enter to continue..." </dev/tty
}

echo
yellow "=== GitHub HTTPS Setup & Connect ==="
echo "Connect a git project to GitHub using HTTPS."
echo "Since GitHub no longer accepts account passwords, this requires a Personal Access Token (PAT)."
echo "This script will:"
echo "1. Configure Git to remember your credentials."
echo "2. Help you generate a GitHub Token."
echo "3. Switch your repository from SSH to HTTPS."
pause_msg ""

# Step 1: Check/Set Git User Name and Email
green "\nStep 1: Checking Git user name and email..."

GIT_USER_NAME=$(git config --global user.name || echo "")
GIT_USER_EMAIL=$(git config --global user.email || echo "")

echo "Current Git User Name:   ${GIT_USER_NAME:-Not Set}"
echo "Current Git User Email:  ${GIT_USER_EMAIL:-Not Set}"

if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
  red "\nGit user name or email is not set globally."
  read -rp "Do you want to set them now? (y/n): " -n 1 -r </dev/tty
  echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        NEW_USER_NAME=""
        while [ -z "$NEW_USER_NAME" ]; do
            read -rp "Enter your Git user name: " NEW_USER_NAME </dev/tty
        done

        NEW_USER_EMAIL=""
        EMAIL_REGEX="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
        while [[ ! "$NEW_USER_EMAIL" =~ $EMAIL_REGEX ]]; do
            read -rp "Enter your Git user email: " NEW_USER_EMAIL </dev/tty
        done

        if run_cmd "git config --global user.name \"$NEW_USER_NAME\""; then
            green " Git user name set."
        else
            red " Failed to set Git user name. Exiting."
            exit 1
        fi

        if run_cmd "git config --global user.email \"$NEW_USER_EMAIL\""; then
            green " Git user email set."
        else
            red " Failed to set Git user email. Exiting."
            exit 1
        fi

  elif [[ $REPLY =~ ^[Nn]$ ]]; then
    red "\nGit user name and email are required. Exiting."
    exit 1
  fi
else
  green "  Git user name and email are already set globally."
fi

pause_msg ""

# Step 2: Check for Git
green "\nStep 2: Checking for Git installation..."
if ! command -v git &>/dev/null; then
  red "Error: Git not found. Please install Git before proceeding."
  exit 1
fi
run_cmd "git --version"


# Step 3: Configure Credential Helper
green "\nStep 3: Configuring Git Credential Helper..."
echo "This ensures you only have to paste your token once, and Git saves it."

# Detect OS to choose the best helper
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "Detected macOS. Configuring 'osxkeychain'."
    run_cmd "git config --global credential.helper osxkeychain"
else
    # Linux / Windows (Git Bash)
    echo "Configuring 'store' helper (saves credentials to disk)."
    # Note: 'cache' is more secure (memory only) but 'store' is more permanent.
    run_cmd "git config --global credential.helper store"
fi


# Step 4: Personal Access Token (PAT) Instructions
green "\nStep 4: GitHub Personal Access Token (PAT)"
yellow "IMPORTANT: GitHub does not accept your account password for Git."
echo "You must use a Personal Access Token (PAT) as your password."
echo
echo "1. Go to: https://github.com/settings/tokens"
echo "2. Click 'Generate new token' (classic)."
echo "3. Give it a name (e.g., 'MacMini HTTPS')."
echo "4. Select scopes: Check 'repo' (Full control of private repositories)."
echo "5. Click Generate token."
echo
pause_msg "Please create your token NOW and copy it to your clipboard.\nOnce you have copied the token, press Enter."


# Step 5: Check or update Git remote (Automatic SSH to HTTPS conversion)
green "\nStep 5: Checking Git remote URL..."

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  yellow "Warning: Not currently in a Git repository."
  echo "Skipping remote URL check/update."
else
  REPO_ROOT=$(git rev-parse --show-toplevel)
  cd "$REPO_ROOT" || exit 1
  
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

  if [ -z "$REMOTE_URL" ]; then
      yellow "No 'origin' remote URL found in this repository."
  
  # Check if it is currently SSH (git@github.com:User/Repo)
  elif [[ "$REMOTE_URL" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)? ]]; then
      GIT_USER=${BASH_REMATCH[1]}
      GIT_REPO=${BASH_REMATCH[2]}
      
      # Construct HTTPS URL
      HTTPS_URL="https://github.com/${GIT_USER}/${GIT_REPO}.git"

      green "Origin remote URL is currently SSH: $REMOTE_URL"
      echo "Attempting to update 'origin' remote URL to HTTPS: $HTTPS_URL"

      git remote set-url origin "$HTTPS_URL"
      
      if [ $? -eq 0 ]; then
        green " Successfully updated 'origin' remote URL to HTTPS."
        run_cmd "git remote -v"
      else
        red " Error: Failed to set 'origin' remote URL."
      fi

  elif [[ "$REMOTE_URL" =~ ^https://github\.com ]]; then
      echo "Origin remote URL is already using HTTPS for GitHub:"
      run_cmd "git remote -v"
  else
      yellow "Remote is not a standard GitHub URL. Skipping update."
      run_cmd "git remote -v"
  fi
fi

# Step 6: Final Instructions
green "\nStep 6: Ready to Push!"
echo "Everything is configured."
echo "The NEXT time you run 'git push' or 'git pull', Git will ask for:"
green "Username: <Your GitHub Username>"
green "Password: <The Token you copied in Step 4>"
echo
echo "Because we set up the Credential Helper in Step 3,"
echo "you will only need to do this ONCE. Git will remember it afterwards."
echo
green "Try it now:"
green "git push"
