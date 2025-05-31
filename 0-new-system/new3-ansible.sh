#!/bin/bash
# Author: Roy Wiseman 2025-02

# Step by step installation and configuration of ansible

# Define text formatting for output
GREEN='\033[0;32m'
YELLOW='\033[0;93m'
NC='\033[0m' # No color

echo
echo "This script will guide you step by step to install and configure Ansible on a Debian-based Linux system."
echo "Ansible is a powerful tool for automating IT infrastructure."
echo

# Step 1: Update and Upgrade System Packages
echo -e "${YELLOW}Step 1: Updating and upgrading system packages.${NC}"
echo "Ensure this system has the latest updates and security patches."
echo "Press Enter to continue or CTRL+C to exit."
read
# Only update if at least 2 days have passed since the last update
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then
    echo -e "Running: ${GREEN}sudo apt update && sudo apt upgrade -y${NC}"
    sudo apt update && sudo apt upgrade -y
    echo
    echo -e "${GREEN}System updated and upgraded successfully!${NC}"
else
    echo "Last update was less than 2 days ago so we will skip the update."
    echo
fi


# Step 2: Install Required Dependencies
echo -e "${YELLOW}Step 2: Installing required dependencies.${NC}"
echo "These include Python3, pip3, and sshpass, which are needed by Ansible."
echo "Press Enter to continue."
read
echo -e "Running: ${GREEN}sudo apt install -y python3 python3-pip sshpass${NC}"
sudo apt install -y python3 python3-pip sshpass
# # Alternatively, use this to test each pacjage
# install-if-missing() { if ! dpkg-query -l "$1" >/dev/null; then sudo apt install -y $1; fi; }
# install-if-missing python3
# install-if-missing python3-pip
# install-if-missing sshpass
echo
echo -e "${GREEN}Dependencies installed successfully!${NC}"
echo

# # Step 3: Add Ansible PPA and Install Ansible
# echo -e "${YELLOW}Step 3: Adding Ansible PPA and installing Ansible.${NC}"
# echo "The default Ansible version in Debian repositories may not be the latest as"
# echo "Ansible is owned by Red Hat so we'll use a PPA to get the latest stable release."
# echo "Press Enter to continue."
# read
# echo -e "Running: ${GREEN}sudo apt install -y software-properties-common${NC}"
# sudo apt install -y software-properties-common
# echo -e "Running: ${GREEN}sudo add-apt-repository --yes --update ppa:ansible/ansible${NC}"
# sudo add-apt-repository --yes --update ppa:ansible/ansible
#
# There are issues currently where add-apt-repository will throw an error for the above.
# Tried the below but it also doesn't work. This only means that we might have a slightly
# older version of Ansible, so we can ignore this.
# DEBIAN_VERSION=$(lsb_release -c | awk '{print $2}')
# # Check if the Debian version is detected
# if [ -z "$DEBIAN_VERSION" ]; then
#   echo "Unable to detect Debian version."
#   exit 1
# fi
# # Check if the Debian version is "bookworm"
# if [ "$DEBIAN_VERSION" != "bookworm" ]; then
#   echo "This script is only intended for Debian bookworm."
#   exit 1
# fi
# echo "Detected Debian version: $DEBIAN_VERSION"
# echo "Adding Ansible repository to sources list..."
# echo "deb http://deb.debian.org/debian $DEBIAN_VERSION-backports main" | sudo tee /etc/apt/sources.list.d/ansible.list
# echo "Adding Ansible GPG key..."
# curl -fsSL https://packages.ansible.com/keys/ansible.asc | sudo tee /etc/apt/trusted.gpg.d/ansible.asc
# echo "Updating package list..."
# sudo apt update
# echo "Ansible repository added and package list updated. You can now install or upgrade Ansible."
echo -e "Running: ${GREEN}sudo apt install -y ansible${NC}"
sudo apt install -y ansible
echo
echo -e "${GREEN}Ansible installed successfully! Checking version...${NC}"
ansible --version
echo

# Step 4: Set Up SSH Key for Ansible (without overwriting existing key)
echo -e "${YELLOW}Step 4: Setting up SSH keys for secure communication.${NC}"
echo "Ansible uses SSH to communicate with managed hosts. If you already have an SSH key, we won't overwrite it."
echo "We'll check if an SSH key already exists and only create a new one if necessary."
echo "Press Enter to continue."
read
# Check if an SSH key already exists
if [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ]; then
  echo -e "${GREEN}SSH key already exists. Skipping key generation.${NC}"
else
  echo -e "Running: ${GREEN}ssh-keygen -t ed25519${NC}"
  ssh-keygen -t ed25519
  echo -e "${GREEN}SSH key generated successfully!${NC}"
fi
echo
echo "For now, we setup Ansible locally, so don't need to copy the SSH key to a remote machine at this time."
echo "When you're ready to manage remote machines, use the following to copy your SSH key to a remote machine:"
echo -e "${GREEN}ssh-copy-id user@remote_host${NC}"
echo "Where 'user' is the username on the remote machine and 'remote_host' is its IP address or hostname."
echo

# Step 5: Configure the Inventory File
echo -e "${YELLOW}Step 5: Configuring the Ansible inventory file.${NC}"
echo "The inventory file at /etc/ansible/hosts defines the hosts that"
echo "Ansible will manage. For now, we will add just localhost. Later,"
echo "you can add remote hosts. The structure should look like this:"
echo -e "${GREEN}
[local]
localhost ansible_connection=local

[remote]
remote_host_1 ansible_host=192.168.1.10 ansible_user=username
remote_host_2 ansible_host=192.168.1.11 ansible_user=username
${NC}"
echo "Note the above as pressing Enter will go to fullscreen vi to add hosts"
echo "Press Enter to edit the inventory file."
read
echo -e "Running: ${GREEN}sudo vi /etc/ansible/hosts${NC}"
sudo [ ! -d /etc/ansible ] && sudo mkdir /etc/ansible
sudo vi /etc/ansible/hosts
echo
echo -e "${GREEN}Inventory file configured!${NC}"
echo

# Step 6: Test Connectivity
echo -e "${YELLOW}Step 6: Testing connectivity to the managed host.${NC}"
echo "We'll use the Ansible ping module to test connectivity."
echo -e "Running: ${GREEN}ansible all -m ping${NC}"
ansible all -m ping
echo
echo -e "${GREEN}Connectivity test complete!${NC}"
echo "Note: if an interpreter warning is shown for Python3.xx, use the following:"
echo
echo -e ${GREEN}"ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3.12 ansible all -m ping${NC}"
echo -e "or you can set the ${GREEN}ANSIBLE_PYTHON_INTERPRETER${NC} before running ansible all -m ping"
echo -e "or you can set ${GREEN}inventory.ini${NC} or set ${GREEN}inventory.yml${NC} in the project folder, e.g.:"
echo -e "${GREEN}
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3.12
${NC}"

# Step 7: Optional: Install Additional Collections
echo -e "${YELLOW}Step 7: (Optional) Installing additional collections.${NC}"
echo "You can extend Ansible's functionality by installing collections from Ansible Galaxy."
echo "Press Enter to skip or specify a collection to install (e.g., community.general):"
read -p "Collection name (leave blank to skip): " collection_name
if [ -n "$collection_name" ]; then
  echo -e "Running: ${GREEN}ansible-galaxy collection install $collection_name${NC}"
  ansible-galaxy collection install "$collection_name"
  echo -e "${GREEN}Collection installed successfully!${NC}"
else
  echo "Skipping additional collections."
fi
echo

# Step 8: Start Using Ansible
echo -e "${YELLOW}Step 8: Start using Ansible!${NC}"
echo "You can now create playbooks to automate tasks. Playbooks are YAML files that describe the tasks to execute."
echo
echo "Example Playbook (example.yml):"
echo -e "${GREEN}"
cat <<EOF
- hosts: all
  tasks:
    - name: Ensure Nginx is installed
      apt:
        name: nginx
        state: present
EOF
echo -e "${NC}"
echo -e "Run the playbook with:   ${GREEN}ansible-playbook example.yml${NC}"
echo

echo -e "${GREEN}Ansible setup and configuration is complete! Happy automating!${NC}"

