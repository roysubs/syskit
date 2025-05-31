#!/bin/bash
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

# Install tools if not already installed
PACKAGES=("smartmontools" "nvme-cli" "hdparm" "util-linux")
install-if-missing() { if ! dpkg-query -W "$1" > /dev/null 2>&1; then sudo apt install -y $1; fi; }
for package in "${PACKAGES[@]}"; do install-if-missing $package; done

# If there are missing tools, install them
if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "The following tools/packages are missing: ${missing_tools[@]}"
    echo "Updating package lists and installing missing tools..."
    sudo apt-get update
    sudo apt-get install -y "${missing_tools[@]}"
else
    echo "Required tools are already installed..."
fi


####################
# Define required packages
REQUIRED_PACKAGES=("smartmontools" "nvme-cli" "hdparm" "util-linux")

# --- Function to check and install packages on Debian-based systems ---
install_debian_dependencies() {
    local missing_packages=()
    local pkg

    echo "Checking for required packages using dpkg..."
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            echo "Package '$pkg' is not installed."
            missing_packages+=("$pkg")
        else
            echo "Package '$pkg' is already installed."
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "The following packages are missing: ${missing_packages[*]}"
        echo "Updating package lists and installing missing packages using apt-get..."
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}"

        echo "Verifying installations..."
        local final_missing=()
        for pkg in "${missing_packages[@]}"; do
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                final_missing+=("$pkg")
            fi
        done

        if [ ${#final_missing[@]} -gt 0 ]; then
            echo "ERROR: The following packages could still not be installed: ${final_missing[*]}"
            echo "Please try to install them manually and re-run the script."
            exit 1
        else
            echo "All required packages were successfully installed."
        fi
    else
        echo "All required packages are already installed."
    fi
}

# --- Main dependency check logic ---

# Check if dpkg-query and apt-get are available
if command -v dpkg-query >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    echo "Debian-based system detected. Proceeding with automated dependency check."
    install_debian_dependencies
else
    echo "---------------------------------------------------------------------"
    echo "WARNING: Cannot automatically check or install packages."
    echo "         The 'dpkg-query' and/or 'apt-get' commands were not found."
    echo "---------------------------------------------------------------------"
    echo ""
    echo "This script requires the following packages to be installed:"
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        echo "  - $pkg"
    done
    echo ""
    echo "Please ensure these are installed using your system's package manager."
    echo "If you are sure the dependencies are installed, you can proceed."
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

