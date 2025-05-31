#!/bin/bash
# Author: Roy Wiseman 2025-04

# Why SSH is Preferred Over HTTPS for Git Operations:
# - Once set up, SSH allows you to interact with GitHub without entering credentials every time.
# - With HTTPS, you'll need to use a Personal Access Token (PAT) instead of a password, which can expire.
# - Stronger Security: SSH keys are cryptographic and tied to your machine, making them more secure than
#   storing and transmitting a PAT.
# - If someone gets your PAT, they can use it anywhere. SSH keys require access to the private key stored
#   locally.
# - Better Automation:
# - Many scripts, CI/CD pipelines, and deployment systems prefer SSH because it works seamlessly without
#   requiring interactive authentication.
# - PATs with HTTPS setups can expire, requiring you to regenerate and reconfigure them, whereas SSH keys
#   remain valid unless revoked. That said, HTTPS is sometimes preferred in locked-down environments where
#   SSH is blocked or when working across multiple devices without setting up SSH keys.

# Color codes
yellow='\e[33m'
green='\e[32m'
reset='\e[0m'

print_section() {
    echo -e "${yellow}\n[ $1 ]${reset}"
}

run_command() {
    echo -e "${green}$ $1${reset}"
    eval "$1"
    echo
}

print_section "Checking SSH Agent and Loaded Keys"
echo "Verifying if SSH agent is running and if the required keys are loaded. If no keys are listed, they might not be added."
run_command "ssh-add -l"

echo "If you see 'The agent has no identities', try adding a key with:"
echo "ssh-add ~/.ssh/id_rsa (or your actual key file)"

echo "If you get 'Could not open a connection to your authentication agent', try running:"
echo "eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_rsa"

print_section "Checking if SSH Key is Configured for GitHub"
echo "Your public key should be added to GitHub settings (SSH and GPG keys)."
echo "Checking contents of your public key (if it exists)."
run_command "cat ~/.ssh/id_*.pub 2>/dev/null || echo 'No public key found'"

echo "If no key is found, generate one using: ssh-keygen -t ed25519 -C 'your-email@example.com'"
echo "Then add it to GitHub at: https://github.com/settings/keys"

print_section "Testing SSH Connection to GitHub"
echo "If this fails with 'Permission denied', your key may not be recognized."
run_command "ssh -vT git@github.com"

echo "If you see 'No more authentication methods to try.', your key isn't recognized. Make sure it's uploaded to GitHub."

echo "If GitHub lists your key but it's still not working, try:"
echo "ssh-keygen -R github.com && ssh -T git@github.com"

print_section "Checking Git Remote URL"
echo "Verifying whether Git is using SSH or HTTPS. SSH is recommended."
run_command "git remote -v"

echo "If you see 'git@github.com:...' then SSH is being used. If it starts with 'https://github.com/', you're using HTTPS."

echo "To switch to SSH, use:"
echo "git remote set-url origin git@github.com:yourusername/yourrepo.git"

print_section "Checking Firewall and Network Issues"
echo "Testing if port 22 is blocked. If it is, we will suggest an alternative."
run_command "nc -zv github.com 22 2>&1"

echo "If you see 'open', port 22 is accessible. If not, it may be blocked."

echo "If port 22 is blocked, try using port 443:"
echo -e "${green}ssh -T -p 443 git@ssh.github.com${reset}"
echo "And configure Git to use port 443 with:"
echo "git config --global core.sshCommand 'ssh -p 443'"

print_section "Checking Expired or Invalid Personal Access Token (PAT)"
echo "If using HTTPS, verifying whether the stored PAT is still valid."
echo -e "${green}$ git credential reject https://github.com${reset}"
git credential reject https://github.com 2>/dev/null
echo -e "${green}$ git ls-remote https://github.com/ > /dev/null 2>&1 && echo 'PAT is valid' || echo 'PAT is invalid or expired'${reset}"
git ls-remote https://github.com/ > /dev/null 2>&1 && echo 'PAT is valid' || echo 'PAT is invalid or expired'

echo "If your PAT is expired, generate a new one at: https://github.com/settings/tokens"
echo "Then update Git credentials using: git credential reject https://github.com && git pull"

print_section "Final Test: Cloning a Test Repository"
echo "Trying to clone a test repository to verify access."
TEMP_DIR="/tmp/test-repo-$RANDOM"
run_command "git clone git@github.com:torvalds/linux.git $TEMP_DIR 2>/dev/null && echo 'Cloning successful' || echo 'Cloning failed'"

echo "Cleaning up test directory."
rm -rf "$TEMP_DIR"

echo -e "${yellow}Done. Check the output for errors and follow any suggested fixes.${reset}"
