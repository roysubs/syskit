#!/bin/bash
# Author: Roy Wiseman 2025-05

# Function to print in green text
print_step() {
    echo -e "\033[1;32m$1\033[0m"
}

# Step 1: Install ClamAV
print_step "Step 1: Installing ClamAV and chkrootkit..."
if ! command -v clamscan &>/dev/null; then
    echo "Installing ClamAV and necessary services..."
    sudo apt update && sudo apt install -y clamav clamav-daemon
    sudo apt install chkrootkit
sudo chkrootkit
else
    echo "ClamAV is already installed."
fi
if ! command -v chrootkit &>/dev/null; then
    sudo apt update && sudo apt install -y chkrootkit
else
    echo "chkrootkit is already installed."
fi

# Step 2: Stop freshclam service to avoid lock issues
print_step "Step 2: Run chkrootkit..."
sudo chkrootkit

# Step 3: Stop freshclam service to avoid locks then update the virus database
print_step "Step 3: Stop freshclam service to avoid locks then update the virus database"
print_step "Stopping freshclam service temporarily..."
sudo systemctl stop clamav-freshclam
print_step "Updating ClamAV virus database..."
if ! sudo freshclam; then
    echo "Failed to update the database. Attempting to fix..."
    sudo rm -rf /var/lib/clamav/*
    sudo freshclam
fi

# Step 4: Fix log file issues
print_step "Step 4: Ensuring freshclam log file is writable..."
LOG_FILE="/var/log/clamav/freshclam.log"
if [ ! -f "$LOG_FILE" ]; then
    echo "Creating freshclam log file..."
    sudo touch "$LOG_FILE"
fi
sudo chown clamav:clamav "$LOG_FILE"
sudo chmod 640 "$LOG_FILE"

# Step 5: Restart freshclam service
print_step "Step 5: Restarting freshclam service..."
sudo systemctl start clamav-freshclam
sudo systemctl enable clamav-freshclam

# Step 6: Verify freshclam service status
print_step "Step 6: Checking freshclam service status..."
if systemctl is-active --quiet clamav-freshclam; then
    echo "freshclam service is running."
else
    echo "Error: freshclam service is not running. Please investigate."
    exit 1
fi

# Step 7: Scan the home directory
print_step "Step 7: Scanning the home directory (~)..."
SCAN_LOG="$HOME/clamav_scan.log"
clamscan -r ~ --log="$SCAN_LOG" --quiet

# Display scan summary
print_step "Step 8: Scan summary..."
if grep -q "Infected files: 0" "$SCAN_LOG"; then
    echo "No threats detected in the home directory."
else
    echo "Potential threats detected. Please review the log at: $SCAN_LOG"
    grep -E "FOUND" "$SCAN_LOG"
fi

# Step 9: Cleanup and next steps
print_step "Step 9: Cleanup and recommendations..."
echo "To keep ClamAV updated automatically, ensure the freshclam service is running."
echo "To perform regular scans, consider creating a cron job."
echo "Script execution completed."

