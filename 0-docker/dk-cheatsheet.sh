#!/bin/bash
# Author: Roy Wiseman 2025-03

cat <<'EOF' | less -R

🛠️  Docker Container Refresher Cheat Sheet
────────────────────────────────────────────

View running containers (change to 'ps -a' to view *all* containers)
🔹 # sudo docker ps

CONTAINER ID   IMAGE             COMMAND                  CREATED             STATUS             PORTS                                   NAMES
4083bc9cbdbc   binhdocker/game   "python3 mini_game.py"   32 minutes ago      Up 32 minutes                                              vigorous_kepler
29bcdbd94bb4   debian            "bash"                   About an hour ago   Up About an hour                                           friendly_dhawan

Start the container at the ENTRYPOINT or CMD as defined in the Dockerfile
🔹 # sudo docker exec -it binhdocker/game
Start the container with /bin/bash (this fails for binhdocker/game as bash is not installed)
🔹 # sudo docker exec -it 4083bc9cbdbc /bin/bash
Start the container with /bin/sh (this will usually work as the basic sh should be there)
🔹 # sudo docker exec -it 4083bc9cbdbc /bin/sh

Stop/start/inspect/stats(cpu+memory) a container
🔹 # sudo docker stop/start/inspect/stats 4083vc9cbdbc
🔹 # sudo docker stop/start/inspect/stats binhdocker/game

Start a container with -p to expose ports
🔹 # sudo docker start 4083vc9cbdbc -p 2222:22
e.g. -p 2222:22, this will map port 22 in the container to be accessible from port 2222 on the host.
This only works if the container has something running at that port. In this example, if ssh is
available on port 22 in the container, then you can ssh to it from the host:
🔹 # ssh user@localhost -p 2222

🔹 Container IP (usually same as host unless using bridge/network):
   # sudo docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' binhdocker/game

Disk usage (of global docker environment)
🔹 # sudo docker system df

✅ View running containers (to view *all* containers, including stopped, use 'ps -a'):
🔹 # sudo docker ps

⛔ How do I delete containers I don't want anymore?
🔹 # sudo docker rm <container_id_or_name>
   ⚠️ Only works for *stopped* containers.
   Example: sudo docker rm practical_elion
   To remove *all* stopped containers:
   🔹 sudo docker container prune

🌍 How do I search Docker Hub from the command line?
🔹 # sudo docker search <image_name>
   Example: sudo docker search debian
   This queries the Docker Hub API for public images matching your term.

🕵️ How do I inspect what's in an image like binhdocker/game?
   You *can't* see the original Dockerfile unless it's published alongside the image,
   but you can view image config:
🔹 # sudo docker inspect binhdocker/game

🔍 Specifically look at the entrypoint or command used when container starts:
🔹 # sudo docker inspect binhdocker/game | grep -A 5 'Entrypoint'
🔹 # sudo docker inspect binhdocker/game | grep -A 5 'Cmd'

📦 To reverse engineer a Dockerfile (roughly) you can try:
🔹 # sudo docker history binhdocker/game
   This shows the layers of the image, which often gives clues like:
   - which base image was used
   - commands that were run (RUN, COPY, etc.)
   But it won’t show the exact Dockerfile unless the creator published it.

🚀 Start a running container using the CMD or ENTRYPOINT (defined in Dockerfile):
🔹 # sudo docker exec -it <container_name_or_id>
⚠️ Note: This is wrong in your original notes — 'docker exec' only works on *already running* containers.
To *start* and *run* an image from scratch:
🔹 # sudo docker run -it binhdocker/game

🧑

💻 Start a shell inside a running container:
🔹 # sudo docker exec -it <container_id_or_name> /bin/bash   # If bash is installed
🔹 # sudo docker exec -it <container_id_or_name> /bin/sh     # More likely to work on minimal images

📊 Monitor CPU and memory usage:
🔹 # sudo docker stats <container_id_or_name>

🔍 Inspect container metadata:
🔹 # sudo docker inspect <container_id_or_name>

⏹️ Start / Stop / Restart containers:
🔹 # sudo docker start <name>
🔹 # sudo docker stop <name>
🔹 # sudo docker restart <name>

🌐 Expose container ports to the host:
🔹 # sudo docker run -p 8888:80 nginx
   This maps port 80 in the container to port 8888 on the host.

🔐 Example: SSH into a container if SSH is running inside it:
🔹 # sudo docker run -d -p 2222:22 my_ssh_image
🔹 # ssh user@localhost -p 2222

📡 Get a container's IP address:
🔹 # sudo docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container_name>

💾 Docker disk usage overview (volumes, images, containers):
🔹 # sudo docker system df

🧹 Clean up dangling (unused) images, networks, build cache, stopped containers:
🔹 # sudo docker system prune -a
   ⚠️ DANGER: This removes *all* unused images, stopped containers, etc.

📁 Save an image to a .tar file:
🔹 # sudo docker save binhdocker/game > game.tar

📁 Load an image from a .tar file:
🔹 # sudo docker load < game.tar

🔄 Commit container changes to a new image:
🔹 # sudo docker commit <container_id> newimagename
   Handy for preserving manual changes you made inside a container shell.

🧰 Create a container but don’t start it immediately:
🔹 # sudo docker create -it binhdocker/game
   Then start it later with:
   🔹 # sudo docker start -ai <container_id>

────────────────────────────────────────────
📘 Tip: Give containers friendly names when creating them:
🔹 # sudo docker run -it --name mygame binhdocker/game
────────────────────────────────────────────

EOF
