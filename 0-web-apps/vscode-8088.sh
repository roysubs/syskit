#!/bin/bash
# Author: Roy Wiseman 2025-05

# Function to check if Docker is installed
check_docker() {
  if ! command -v docker &> /dev/null
  then
    echo "Docker is not installed. Installing Docker..."
    install_docker
  else
    echo "Docker is already installed."
  fi
}

# Function to install Docker
install_docker() {
  # Check OS and install Docker accordingly
  if [ -f /etc/debian_version ]; then
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker
  elif [ -f /etc/redhat-release ]; then
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
  fi
  sudo usermod -aG docker $USER
  echo "Docker has been installed. Please log out and back in for Docker group permissions to take effect."
}

# Function to check if code-server container exists
check_container() {
  if [ "$(docker ps -a -q -f name=code-server)" ]; then
    echo "The 'code-server' container already exists. Starting it..."
    start_container
  else
    echo "The 'code-server' container does not exist. Creating and running it..."
    run_container
  fi
}

# Function to run code-server container
run_container() {
  docker run -d \
    --name=code-server \
    --restart unless-stopped \
    -e PASSWORD=mystrongpassword \
    -p 8088:8080 \
    -v $(pwd):/home/coder/project \
    coder/code-server
  echo "code-server is now running on http://localhost:8088"
}

# Function to start the code-server container if it exists
start_container() {
  docker start code-server
  echo "code-server container started. You can now access it at http://localhost:8088"
}

# Main script execution
echo "Checking for Docker installation..."
check_docker

echo "Checking for 'code-server' container..."
check_container

echo "Setup complete. Access VSCode at http://localhost:8088"

