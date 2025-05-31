#!/bin/bash
# Author: Roy Wiseman 2025-04

# Function to print headers in yellow
print_header() {
    echo -e "\e[33m$1\e[0m"
}

# Function to print commands in green before executing them
run_command() {
    echo -e "\e[32m$1\e[0m"
    eval "$1"
}

# Step 1: Check if SSH agent is running
print_header "\nStep 1: Checking if the SSH agent is running..."
SSH_AGENT_PID=$(pgrep -u "$USER" ssh-agent)
if [ -n "$SSH_AGENT_PID" ]; then
    echo "SSH agent is already running (PID: $SSH_AGENT_PID). Using existing agent."
    eval "$(ssh-agent -s)"
else
    print_header "No SSH agent running. Starting a new one..."
    eval "$(ssh-agent -s)"
fi

# Step 2: List currently added SSH keys
print_header "\nStep 2: Checking if any SSH keys are loaded..."
run_command "ssh-add -l"

# If no keys are found, add the default key
if [ $? -ne 0 ]; then
    echo "No SSH keys found in the agent. Attempting to add your default key..."
    run_command "ssh-add ~/.ssh/id_rsa 2>/dev/null || ssh-add ~/.ssh/id_ed25519 2>/dev/null"
fi

print_header "\nSSH keys after adding (if needed):"
run_command "ssh-add -l"

# Step 3: Verify SSH connection to GitHub
print_header "\nStep 3: Testing SSH connection to GitHub..."
run_command "ssh -T git@github.com"

# Step 4: Check the remote URL
print_header "\nStep 4: Checking your Git remote URL..."
run_command "git remote -v"

# Step 5: Suggest switching to SSH if using HTTPS
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [[ "$REMOTE_URL" == https* ]]; then
    echo "Your remote URL is using HTTPS. It is recommended to use SSH for authentication."
    echo "To switch to SSH, run the following command:"
    echo -e "\e[32mgit remote set-url origin git@github.com:your-username/your-repository.git\e[0m"
fi

# Step 6: List existing SSH keys
print_header "\nStep 5: Listing SSH keys in ~/.ssh directory..."
run_command "ls -l ~/.ssh"

# Step 7: Display SSH public key to check if it's added to GitHub
if [ -f ~/.ssh/id_rsa.pub ]; then
    print_header "\nYour SSH public key (~/.ssh/id_rsa.pub):"
    run_command "cat ~/.ssh/id_rsa.pub"
elif [ -f ~/.ssh/id_ed25519.pub ]; then
    print_header "\nYour SSH public key (~/.ssh/id_ed25519.pub):"
    run_command "cat ~/.ssh/id_ed25519.pub"
else
    print_header "\nNo public SSH key found. You may need to generate one."
    echo -e "Run: \e[32mssh-keygen -t ed25519 -C 'your-email@example.com'\e[0m"
fi

# Step 8: Provide final instructions
print_header "\nFinal Instructions:"
echo "If your SSH key is missing, add it to GitHub under Settings -> SSH and GPG keys."
echo "If problems persist, try restarting your SSH agent with: eval \"\$(ssh-agent -s)\" and re-running ssh-add."
echo -e "\nDone!"

