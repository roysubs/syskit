#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02

# Finding All Disks:
# lsblk -o NAME,SIZE,TYPE,MOUNTPOINT: Lists block devices.
# lsblk -d -n -o NAME : get all block devices (disks) without partitions. Generate a report for each disk.
# lsblk /dev/disk: Detailed information about the specific disk.
# smartctl -a /dev/disk: Provides a SMART status report for the disk.
# nvme smart-log /dev/disk: Shows NVMe disk statistics (only for NVMe drives).
# hdparm -I /dev/disk: Provides detailed information about the disk.
# The results of each command are written to the report file, prefixed with the command that was run.
# lsblk is in the 'util-linux' package

# Ensure the script can find the necessary tools
export PATH=$PATH:/usr/sbin:/sbin
# Check if 2 days have passed since the last update
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update; fi
HOME_DIR="$HOME"
scriptname=$(basename "$0" .sh)   # Get scriptname minus extension.

pkg_install() {
    local pkgs=("$@")
    if command -v zypper &>/dev/null; then
        sudo zypper refresh && sudo zypper install -y "${pkgs[@]}"
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${pkgs[@]}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "${pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm "${pkgs[@]}"
    elif command -v apk &>/dev/null; then
        sudo apk add "${pkgs[@]}"
    elif command -v brew &>/dev/null; then
        brew install "${pkgs[@]}"
    fi
}

for cmd in smartctl nvme hdparm lsblk; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing disk monitoring tools..."
        pkg_install smartmontools nvme-cli hdparm util-linux 2>/dev/null || true
        break
    fi
done
    echo ""
    read -n 1 -s -r -p "Press any key to continue, or Ctrl+C to abort..."
    echo # Move to a new line after key press
    echo "Continuing based on user confirmation..."
fi

echo ""
echo "Dependency check/awareness section complete."
echo "Proceeding with the main script functionality..."
####################








# Function to generate report for each disk
generate_report() {
    local disk=$1
    local report_dir="$HOME_DIR/reports"
    local report_file="$report_dir/system-${disk}-disk-report.txt"
    mkdir -p $report_dir
    echo "Generating report for $disk..."

    # Initialize the report file
    echo "Disk Report for $disk" > "$report_file"
    echo "=========================" >> "$report_file"

    # List the commands and outputs to include in the report
    commands=(
        "lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,MOUNTPOINT"
        "lsblk /dev/$disk"
        "sudo smartctl -a /dev/$disk"
        "sudo nvme smart-log /dev/$disk"
        "sudo hdparm -I /dev/$disk"
    )

    # Run each command and append to the report
    for cmd in "${commands[@]}"; do
        echo -e "\nRunning: $cmd\n" >> "$report_file"
        if eval "$cmd" >> "$report_file" 2>&1; then
            echo -e "\n*** Command executed successfully" >> "$report_file"
        else
            echo -e "\n*** Error executing $cmd" >> "$report_file"
            echo -e "*** Full error: $(eval $cmd 2>&1)" >> "$report_file"
        fi
        echo -e "\n=========================" >> "$report_file"
    done

    echo "Report saved as $report_file"
}

# Find all disks (excluding partitions) and generate reports
disks=$(lsblk -d -n -o NAME -e 1,7,11,253)

# Loop through each disk (e.g., sda, sdb, sdc)
for disk in $disks; do
    generate_report "$disk"
done

echo "All disk reports generated in $HOME_DIR"

