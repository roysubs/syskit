These scripts are designed to always deploy in a repeatable/idempotent manner. If the container exists,
they simply provide additional notes to refresh a user on usage for that container without affecting
the running container (i.e. various important how-to information for Plex or EmulatorJS).

Docker resouce sharing (particularly the kernel) is amazingly lightweight. You can run docker on very
old systems with almost no overhead from running them as a local install (i.e. great for old systems).

Docker images are usually stored on Linux at: /var/lib/docker (can be changed in daemon.json). Images
themselves are usually in a directory related to the storage driver Docker is using (e.g., overlay2).   

Always run docker commands without sudo. This is standard practice and makes managing containers much
more convenient.

LinuxServer.io / lscr.io are almost always the best/simplest Docker images to use.
Images by category is probably the easiest way to review them.
https://docs.linuxserver.io/images-by-category/#administration

'Docker Desktop' Setup
==========
- For a simple setup where you have a Windows desktop and a headless Linux server, setup Docker Desktop
on Windows, uncheck Windows containers (they are of limited usefulness for now), and then connect to
the headless Linux server (or to WSL2 on this host if using containers there).
- Docker Desktop defaults to the local Docker engine (i.e., the one it installs inside WSL2 at setup),
but you can change it to connect to a remote Docker engine over SSH or TCP.
  1. Install Docker Desktop as normal; you don't have to enable/use WSL2 if you don't want to (or you
     can just let it install, it won't hurt).
  2. Connect to your remote Linux machine at Settings → Docker Engine or Settings → Resources → Advanced.
     Look for "Docker Daemon" connection settings and connect via SSH to the remote Linux server. Or, in
     the Docker CLI, you can just set:
       docker -H ssh://user@remote-server.example.com ps   # -H sets the Docker Host.
  3. For permanent config, to always connect to your remote system:
       export DOCKER_HOST=ssh://user@your-remote-linux-ip
  Or configure the connection inside the Docker Desktop GUI.
Notes: Your remote server must already have Docker installed and running.
You need SSH access to the remote server (with public key auth ideally for no-password access).
Some GUIs (like the Docker Dashboard) work better than others with remote connections — but it does show
your containers/images etc from the remote server.
You don't need to install WSL2 or a Linux distro locally unless you want to manage local containers too.
VSCode with the Remote Containers extension can also connect over SSH if you want an even easier GUI.

