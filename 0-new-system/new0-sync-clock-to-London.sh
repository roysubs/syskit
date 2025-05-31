#!/bin/bash
# Author: Roy Wiseman 2025-01

# Use ntpdate or timedatectl to sync the clock with an internet time server.
# This will enable automatic time synchronization using the system's default NTP servers.
sudo apt install systemd-timesyncd
sudo systemctl enable --now systemd-timesyncd
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd   # This will manually trugger an immediate sync
timedatectl status   # Check the current time synchronization status

# My system was using UTC instead of local timezone (Amsterdam, which should be CET/CEST).
# Fix it with the following:
sudo timedatectl set-timezone Europe/London   # Set my timezone
timedatectl   # Verify my timezone
# Local time: Mon 2025-02-03 09:00:00 CET
# Universal time: Mon 2025-02-03 08:00:00 UTC
# RTC time: Mon 2025-02-03 08:00:00
# Time zone: Europe/Amsterdam (CET, +0100)
sudo systemctl restart systemd-timesyncd   # Force an Immediate Time Sync:

# ntpdate has been deprecated in modern linux, but can still be used
# sudo apt install ntpdate
# sudo ntpdate time.nist.gov

echo "
To perform the equivalent on Windows, use w32tm to to sync with an internet time server:
   w32tm /resync /nowait   # sync to internet time server
   w32tm /config /update /manualpeerlist:"time.windows.com" /syncfromflags:manual   # Manually force an update
   w32tm /resync
"
