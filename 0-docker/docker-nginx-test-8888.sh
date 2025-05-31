#!/bin/bash
# Author: Roy Wiseman 2025-05

# nginx Docker automated deployment with example note taking app exposed on port 8888
# ────────────────────────────────────────────────

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Installing...${NC}"
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo -e "${GREEN}Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'.${NC}"
        exit 1
    else
        echo -e "${RED}❌ Failed to install Docker.${NC}"
        exit 1
    fi
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    exit 1
fi

# Set up variables
APP_DIR="webapp"
CONTAINER_NAME="nginx_webapp"
NETWORK_NAME="nginx_net"
IMAGE_NAME="nginx:latest"
PORT="8888"  # Changed from 8080 to 8888 to avoid conflicts

echo "Checking if Docker is installed..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    sudo apt update && sudo apt install -y docker.io
    sudo systemctl enable --now docker
else
    echo "Docker is already installed."
fi

# Check if Docker is running
if ! sudo systemctl is-active --quiet docker; then
    echo "Docker service is not running. Starting Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "Docker is running."
fi

# Check Docker permissions
if ! docker info &> /dev/null; then
    echo "ERROR: Docker permission denied. Attempting to fix..."
    echo "Adding current user to Docker group..."
    sudo usermod -aG docker $USER
    
    # Attempt to apply group changes immediately
    echo "Applying Docker group changes. You may need to log out and log back in for full changes."
    newgrp docker
    if ! docker info &> /dev/null; then
        echo "ERROR: Docker permissions still not applied. Please log out and log back in."
        exit 1
    fi
fi

echo "Creating a Docker network ($NETWORK_NAME) if not exists..."
docker network inspect $NETWORK_NAME >/dev/null 2>&1 || docker network create $NETWORK_NAME

echo "Creating the web application directory ($APP_DIR)..."
mkdir -p $APP_DIR

echo "Generating a simple note-taking web application..."
cat <<EOL > $APP_DIR/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Simple Note App</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; max-width: 600px; margin: auto; }
        textarea { width: 100%; height: 300px; font-size: 16px; }
        button { margin-top: 10px; padding: 10px; font-size: 16px; }
    </style>
</head>
<body>
    <h2>Simple Note-Taking App</h2>
    <textarea id="note" placeholder="Write your notes here..."></textarea>
    <button onclick="saveNote()">Save Note</button>
    <script>
        const noteBox = document.getElementById('note');
        noteBox.value = localStorage.getItem('note') || '';
        function saveNote() {
            localStorage.setItem('note', noteBox.value);
            alert('Note saved!');
        }
    </script>
</body>
</html>
EOL

echo "Creating an Nginx configuration..."
cat <<EOL > $APP_DIR/default.conf
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOL

echo "Pulling the latest Nginx Docker image..."
docker pull $IMAGE_NAME

echo "Stopping and removing any existing container ($CONTAINER_NAME)..."
docker stop $CONTAINER_NAME 2>/dev/null && docker rm $CONTAINER_NAME 2>/dev/null

echo "Running the Nginx container serving the web app..."
docker run -d --name $CONTAINER_NAME --network $NETWORK_NAME \
    -p $PORT:80 -v "$(pwd)/$APP_DIR:/usr/share/nginx/html:ro" \
    -v "$(pwd)/$APP_DIR/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    $IMAGE_NAME

# docker run -d --name nginx_webapp --network nginx_net \
#     -p 8888:80 -v "/home/user/syskit/0-scripts/webapp:/usr/share/nginx/html:ro" \
#     -v "/home/user/syskit/0-scripts/webapp/default.conf:/etc/nginx/conf.d/default.conf:ro" \
#     nginx:latest


echo "Deployment completed!"
echo "Nginx container is now running and serving the web app on port $PORT."
echo "Access your note-taking web app at: http://localhost:$PORT"

