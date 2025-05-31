# Use a publicly available Ubuntu Desktop VNC image
FROM dorowu/ubuntu-desktop-lxde-vnc:latest

# Switch to the root user for installation steps
USER root

# --- FIX: Remove the problematic Google Chrome repo source file ---
# This repository source seems to be missing its GPG key in the base image
# We don't need it for building Sil-Q, so we remove the source file
RUN rm -f /etc/apt/sources.list.d/google-chrome.list

# Install necessary game dependencies (for Sil-Q)
RUN apt-get update && apt-get install -y \
    gcc \
    make \
    libsdl2-dev \
    libsdl2-image-dev \
    libncurses5-dev \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Sil-Q game
# --- FIX: Corrected wget URL and tar filename typo ---
RUN wget https://github.com/sil-quirk/sil-q/archive/refs/tags/v1.5.0.tar.gz -O /tmp/sil-q-1.5.0.tar.gz && \
    tar -xvzf /tmp/sil-q-1.5.0.tar.gz -C /opt/ && \
    # The extracted directory from the source tarball is typically named 'sil-q-tagname'
    cd /opt/sil-q-1.5.0 && \
    make -f Makefile.std install && \
    rm /tmp/sil-q-1.5.0.tar.gz

# Expose the VNC port (this image usually runs on 5900)
EXPOSE 5900

# Set the VNC password (optional, but good practice)
# Default password for dorowu/ubuntu-desktop-lxde-vnc is "vncpassword" if not set here
# ENV VNC_PW=your_secure_password

# Configure the entrypoint to run Sil-Q after the VNC server starts
# This base image uses a custom entrypoint that starts VNC.
# We will add a script to launch silx when the desktop environment is ready.

# Create a script to launch Sil-Q
RUN echo '#!/bin/bash' > /usr/local/bin/start_silq.sh && \
    echo 'while ! pgrep Xtightvnc > /dev/null; do sleep 1; done' >> /usr/local/bin/start_silq.sh && \
    echo 'sleep 5' >> /usr/local/bin/start_silq.sh && \
    echo 'DISPLAY=:1 /home/user/games/sil-q/silx' >> /usr/local/bin/start_silq.sh && \
    chmod +x /usr/local/bin/start_silq.sh

# Add the script to the list of startup applications for the LXDE desktop
# This command assumes the LXDE autostart directory structure used by the base image
# You might need to adjust the path depending on the exact base image version/config
# A more robust way might be to modify the entrypoint script itself,
# but this is simpler if the autostart method works.
RUN mkdir -p /home/user/.config/autostart/ && \
    echo '[Desktop Entry]' > /home/user/.config/autostart/silq.desktop && \
    echo 'Type=Application' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Exec=/usr/local/bin/start_silq.sh' >> /home/local/bin/start_silq.sh && \ # <-- Corrected path here too
    echo 'Hidden=false' >> /home/user/.config/autostart/silq.desktop && \
    echo 'NoDisplay=false' >> /home/user/.config/autostart/silq.desktop && \
    echo 'X-GNOME-Autostart-enabled=true' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Name[en_US]=Sil-Q Game' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Name=Sil-Q Game' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Comment[en_US]=Start the Sil-Q game' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Comment=Start the Sil-Q game' >> /home/user/.config/autostart/silq.desktop && \
    echo 'StartupNotify=false' >> /home/user/.config/autostart/silq.desktop && \
    echo 'Terminal=false' >> /home/user/.config/autostart/silq.desktop && \
    chown -R user:user /home/user/.config

# The base image's entrypoint will start the VNC server and LXDE desktop.
# The .desktop file we added will launch silx within that environment.
# CMD is not needed as the base image provides an ENTRYPOINT.
