#!/bin/bash
# Author: Roy Wiseman 2025-01

# ==============================================================================
# Script Name: new0-disable-power-settings.sh
# Description: This script attempts to disable various power-saving features
#              on a Linux system to prevent it from sleeping, suspending,
#              or hibernating. It targets systemd services, logind configuration,
#              USB autosuspend, and PCI runtime power management.
# Author:      Your Name/Adapted by AI
# Version:     1.1
# Last Updated: 2025-05-26
#
# IMPORTANT:
# 1. Run this script with caution. Disabling power-saving features will
#    increase power consumption.
# 2. This script requires root privileges for most of its operations.
#    It will attempt to re-run itself with sudo if not already root.
# 3. Some operations, especially direct writes to /sys, might not be
#    supported by all hardware or kernel versions, leading to messages
#    like "Invalid argument" or "Operation not permitted".
# ==============================================================================

# --- Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
#  Prevent errors in a pipeline from being masked.
set -o pipefail

# --- Constants ---
LOGIND_CONFIG_FILE="/etc/systemd/logind.conf"
BACKUP_SUFFIX=".bak_$(date +%Y%m%d_%H%M%S)"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARN] $1"
}

error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Function to check for command existence
command_exists() {
    command -v "$1" &> /dev/null
}

# --- Sudo Check ---
# Ensure the script is run as root. If not, re-execute with sudo.
if [[ "${EUID}" -ne 0 ]]; then
    info "This script needs to be run as root."
    info "Attempting to re-execute with sudo..."
    # shellcheck disable=SC2068 # We want word splitting for $@
    if sudo -E bash "$0" "$@"; then
        exit 0
    else
        error_exit "Failed to re-execute with sudo. Please run as root."
    fi
fi

# --- Main Script Logic ---

# Function to mask systemd targets related to sleep, suspend, and hibernate
configure_systemd_targets() {
    info "Masking systemd sleep, suspend, hibernate, and hybrid-sleep targets..."
    local targets_masked=0
    if systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target; then
        info "Successfully masked systemd power targets."
        targets_masked=1
    else
        warn "Failed to mask one or more systemd power targets. They might already be masked or another issue occurred."
    fi

    # Reload systemd to apply changes if targets were masked
    if [[ "$targets_masked" -eq 1 ]]; then
        if systemctl daemon-reload; then
            info "Systemd daemon reloaded."
        else
            warn "Failed to reload systemd daemon. A reboot might be required for all changes to take effect."
        fi
    fi
    # Note: `swapoff -a` was removed as it's generally not the best way to prevent hibernation
    # and can have negative side effects. Masking hibernate.target is preferred.
    # If you need to prevent hibernation via swap, ensure no resume= kernel parameter is set
    # and that hibernate.target is masked.
}

# Function to configure /etc/systemd/logind.conf
configure_logind() {
    info "Configuring ${LOGIND_CONFIG_FILE} to ignore lid switch actions..."
    if [[ ! -f "${LOGIND_CONFIG_FILE}" ]]; then
        warn "${LOGIND_CONFIG_FILE} not found. Skipping logind configuration."
        return 1
    fi

    # Create a backup of the original logind.conf
    info "Backing up ${LOGIND_CONFIG_FILE} to ${LOGIND_CONFIG_FILE}${BACKUP_SUFFIX}"
    if ! cp "${LOGIND_CONFIG_FILE}" "${LOGIND_CONFIG_FILE}${BACKUP_SUFFIX}"; then
        warn "Failed to create backup of ${LOGIND_CONFIG_FILE}. Proceeding without backup."
    fi

    local changes_made=0
    # Define settings to change
    declare -A settings
    settings=(
        ["HandleLidSwitch"]="ignore"
        ["HandleLidSwitchExternalPower"]="ignore"
        ["HandleLidSwitchDocked"]="ignore"
        ["IdleAction"]="ignore" # Added to prevent idle suspend/shutdown
    )

    for key in "${!settings[@]}"; do
        local value="${settings[$key]}"
        # Check if the line exists and is different, or if it's commented out
        if grep -q "^\s*#\?\s*${key}\s*=" "${LOGIND_CONFIG_FILE}"; then
            # If it exists (commented or not), replace it
            if ! sed -i -E "s/^\s*#?\s*${key}\s*=.*/${key}=${value}/" "${LOGIND_CONFIG_FILE}"; then
                warn "Failed to set ${key}=${value} in ${LOGIND_CONFIG_FILE}"
            else
                info "Set ${key}=${value} in ${LOGIND_CONFIG_FILE}"
                changes_made=1
            fi
        else
            # If it doesn't exist, append it
            if ! echo "${key}=${value}" >> "${LOGIND_CONFIG_FILE}"; then
                 warn "Failed to append ${key}=${value} to ${LOGIND_CONFIG_FILE}"
            else
                info "Appended ${key}=${value} to ${LOGIND_CONFIG_FILE}"
                changes_made=1
            fi
        fi
    done

    if [[ "$changes_made" -eq 1 ]]; then
        info "Restarting systemd-logind service to apply changes..."
        if systemctl restart systemd-logind; then
            info "systemd-logind restarted successfully."
        else
            warn "Failed to restart systemd-logind. A reboot might be required."
        fi
    else
        info "No changes made to ${LOGIND_CONFIG_FILE} as settings seemed already correct or file was not writable."
    fi
}

# Function to disable USB auto-suspend
# For USB devices, 'on' means power management is off (device stays on). 'auto' means PM is on.
configure_usb_autosuspend() {
    info "Attempting to disable USB auto-suspend (setting power/control to 'on')..."
    local usb_devices_path="/sys/bus/usb/devices"
    if [[ ! -d "$usb_devices_path" ]]; then
        warn "USB devices path $usb_devices_path not found. Skipping USB autosuspend configuration."
        return
    fi

    for device_path in "$usb_devices_path"/*; do
        local power_control_file="${device_path}/power/control"
        if [[ -f "${power_control_file}" && -w "${power_control_file}" ]]; then
            local current_state
            current_state=$(cat "${power_control_file}")
            if [[ "${current_state}" == "on" ]]; then
                # info "USB device ${device_path##*/} power/control already 'on'."
                : # Do nothing, already set
            else
                info "Setting power/control to 'on' for USB device ${device_path##*/} (was '${current_state}')"
                if echo "on" > "${power_control_file}"; then
                    : # Success
                else
                    # The error "Invalid argument" seen in the original output often happens here
                    # if the device/driver doesn't support the 'on' value or runtime PM control.
                    warn "Failed to write 'on' to ${power_control_file}. Device may not support it or was already in an error state."
                fi
            fi
        elif [[ -f "${power_control_file}" && ! -w "${power_control_file}" ]]; then
            warn "Skipping USB device ${device_path##*/}: power/control file not writable."
        fi
    done
    info "USB auto-suspend configuration attempt finished."
}

# Function to disable PCI(e) runtime power management
# For PCI devices, 'on' means power management is off (device stays on). 'auto' means PM is on.
configure_pci_pm() {
    info "Attempting to disable PCI(e) runtime power management (setting power/control to 'on')..."
    local pci_devices_path="/sys/bus/pci/devices"
    if [[ ! -d "$pci_devices_path" ]]; then
        warn "PCI devices path $pci_devices_path not found. Skipping PCI PM configuration."
        return
    fi

    for device_path in "$pci_devices_path"/*; do
        local power_control_file="${device_path}/power/control"
        if [[ -f "${power_control_file}" && -w "${power_control_file}" ]]; then
            local current_state
            current_state=$(cat "${power_control_file}")
             if [[ "${current_state}" == "on" ]]; then
                # info "PCI device ${device_path##*/} power/control already 'on'."
                : # Do nothing, already set
            else
                info "Setting power/control to 'on' for PCI device ${device_path##*/} (was '${current_state}')"
                # For PCI, setting to 'on' disables runtime PM.
                if echo "on" > "${power_control_file}"; then
                    : # Success
                else
                    warn "Failed to write 'on' to ${power_control_file} for device ${device_path##*/}. Device may not support it."
                fi
            fi
        elif [[ -f "${power_control_file}" && ! -w "${power_control_file}" ]]; then
            warn "Skipping PCI device ${device_path##*/}: power/control file not writable."
        fi
    done
    info "PCI(e) runtime power management configuration attempt finished."
}

# --- Execute Main Functions ---
info "Starting script to disable power-saving features."

configure_systemd_targets
configure_logind
configure_usb_autosuspend
configure_pci_pm

# --- Final Remarks and Manual Steps (from original script) ---
echo ""
info "--- Additional Guidance & Verification ---"
info "1. Masked Systemd Targets: To revert, you can use:"
info "   sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target"
info "   Followed by: sudo systemctl daemon-reload"
info "2. Logind Configuration: Original backed up to ${LOGIND_CONFIG_FILE}${BACKUP_SUFFIX} (if successful)."
info "   To revert, restore the backup and restart systemd-logind."
info "3. USB/PCI power/control: These settings are typically not persistent across reboots."
info "   For persistence, you might need udev rules or other startup scripts."
info "   Example udev rule for a USB device (e.g., /etc/udev/rules.d/90-usb-power.rules):"
info "   ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"XXXX\", ATTR{idProduct}==\"YYYY\", ATTR{power/control}=\"on\""
info "   (Replace XXXX and YYYY with actual vendor/product IDs, find with 'lsusb')"
info "4. BIOS/UEFI Settings: Check your system's BIOS/UEFI settings."
info "   Look for 'Power Management' or similar and disable any OS-independent sleep/suspend modes."
info "5. Kernel Parameters: Ensure no kernel parameters are forcing power-saving states (less common)."
info "--------------------------------------------"
info "Energy-saving feature modification attempts complete."
info "Monitor the system to confirm changes and ensure stability."
info "A reboot may be beneficial for some settings to fully apply or to clear any transient states."

exit 0
