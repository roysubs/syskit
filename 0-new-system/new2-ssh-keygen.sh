#!/bin/bash
# Author: Roy Wiseman 2025-02

# Purpose: Assist users in generating and configuring SSH keys for secure remote access.

echo "This script will generate a new SSH key pair and configure it for remote access."
echo

# Explain SSH Keys
echo "SSH keys are a pair of cryptographic keys used for secure authentication between"
echo "this computer and a remote server. They consist of a private key (kept secure on"
echo "this machine) and a public key (shared with the remote server)."
echo

read -p "Do you want to proceed with generating a new SSH key pair? (yes/no): " proceed
if [[ "$proceed" != "yes" ]]; then
  echo "Exiting the setup wizard."
  exit 0
fi

# Generate SSH Key Pair
echo
echo "Generating an SSH key pair..."
read -p "Enter the file path for your new SSH key (default: ~/.ssh/id_rsa): " key_path
key_path=${key_path:-~/.ssh/id_rsa}

if [[ -f "$key_path" ]]; then
  echo "A key already exists at $key_path. Do you want to overwrite it?"
  read -p "(Overwriting will replace your existing key) (yes/no): " overwrite
  if [[ "$overwrite" != "yes" ]]; then
    echo "Aborting key generation to avoid overwriting your existing key. Exiting!"
    exit 1
  fi
fi
# Run ssh-keygen
echo -e "ssh-keygen -t rsa -b 4096 -f \"$key_path\" -C \"$(whoami)@$(hostname)\""
ssh-keygen -t rsa -b 4096 -f "$key_path" -C "$(whoami)@$(hostname)"

# Guide the User to Add the Public Key to Remote Servers
echo
echo "Your SSH key pair has been generated!"
echo "Private key (KEEP THIS FILE SECRET):     $key_path"
echo "Public key (SHARE WITH REMOTE SERVERS):  ${key_path}.pub"
echo

# Show public key content
echo "Contents of your public key:"
cat "${key_path}.pub"
echo

# Explain Adding the Public Key to a Remote Server
echo "To use this SSH key for secure access to a remote server, you need to add the public key"
echo "to the server. Do this by copying the public key to the server's authorized_keys at:"
echo "   ~/.ssh/authorized_keys."
echo "The easiest way to do this is with the 'ssh-copy-id' command."
echo

read -p "Would you like to copy your public key to a remote server now? (yes/no): " copy_now
if [[ "$copy_now" == "yes" ]]; then
  echo "   ssh-copy-id -i \"${key_path}.pub\" \"remote_user\""
  read -p "Enter the remote server username (e.g., user@hostname): " remote_user
  ssh-copy-id -i "${key_path}.pub" "$remote_user"
  if [[ $? -eq 0 ]]; then
    echo "Public key successfully added to the remote server!"
  else
    echo "Failed to add the public key. Please check the server details and try again."
  fi
else
  echo "Manually copy the key to other servers by running:"
  echo "   ssh-copy-id -i ${key_path}.pub user@hostname"
fi

# Test the SSH Key
echo
echo "Testing SSH key authentication..."
read -p "Enter the remote server username for testing (or press Enter to skip): " test_user
if [[ -n "$test_user" ]]; then
  ssh "$test_user" "echo 'SSH key authentication successful!'"
else
  echo "Skipping test. Make sure to test your SSH setup before relying on it!"
fi

echo
echo "SSH key setup is complete. You can now use this key to securely access remote servers."
echo
