#!/bin/bash
#
# date-time-linux-gui.sh
#
# This script configures the panel clock format for various Linux desktop environments.
# It's designed to be idempotent, only applying changes if the current format
# doesn't match the desired format.
#
# Desired Format: %a, %b %e, %H:%M:%S (e.g., "Fri, Jun 13, 20:30:55")
#

# --- Configuration & Constants ---
# The desired date and time format string.
# %a: Abbreviated weekday name (e.g., Sun)
# %b: Abbreviated month name (e.g., Jan)
# %e: Day of the month, space-padded (e.g., " 2")
# %H: Hour (00..23)
# %M: Minute (00..59)
# %S: Second (00..59)
DESIRED_FORMAT="%a, %b %e, %H:%M:%S"
DESIRED_FORMAT_GNOME="%-d %b %Y, %H:%M:%S" # GNOME has a slightly different way to represent this

# --- Helper Functions for Output ---

# Function to print a formatted info message
# Usage: log_info "Your message here"
log_info() {
    # Blue color for info messages
    echo -e "\e[34m\xE2\x84\xB9  $1\e[0m"
}

# Function to print a formatted success message
# Usage: log_success "Your message here"
log_success() {
    # Green color for success messages
    echo -e "\e[32m\xE2\x9C\x94  $1\e[0m"
}

# Function to print a formatted warning message
# Usage: log_warn "Your message here"
log_warn() {
    # Yellow color for warning messages
    echo -e "\e[33m\xE2\x9A\xA0  $1\e[0m"
}

# Function to print a formatted error message
# Usage: log_error "Your message here"
log_error() {
    # Red color for error messages
    echo -e "\e[31m\xE2\x9D\x8C  $1\e[0m"
}

# --- Desktop Environment Detection and Configuration ---

# Detect the current desktop environment
detect_desktop_environment() {
    if [ "$XDG_CURRENT_DESKTOP" ]; then
        # Convert to lowercase for easier matching
        echo "${XDG_CURRENT_DESKTOP,,}"
    elif [ "$DESKTOP_SESSION" ]; then
        echo "${DESKTOP_SESSION,,}"
    else
        # Fallback for older systems
        echo "unknown"
    fi
}

# Configure GNOME Shell (Ubuntu, Fedora, Red Hat, CentOS with GNOME)
configure_gnome() {
    log_info "Detected GNOME environment."
    # Check if gsettings is available
    if ! command -v gsettings &> /dev/null; then
        log_error "gsettings command not found. Cannot configure GNOME clock."
        return 1
    fi

    local schema="org.gnome.desktop.interface"
    local key="clock-format"
    local current_format

    current_format=$(gsettings get "$schema" "$key" 2>/dev/null)

    if [[ "$current_format" == "'24h'" ]]; then
         gsettings set "$schema" clock-show-weekday true
         gsettings set "$schema" clock-show-date true
         gsettings set "$schema" clock-show-seconds true
         log_success "GNOME clock format updated."
    elif [[ "$current_format" == "'12h'" ]]; then
         gsettings set "$schema" clock-show-weekday true
         gsettings set "$schema" clock-show-date true
         gsettings set "$schema" clock-show-seconds true
         log_success "GNOME clock format updated."
    else
        log_success "GNOME clock format already configured correctly."
    fi
}


# Configure Cinnamon (Linux Mint)
configure_cinnamon() {
    log_info "Detected Cinnamon environment."
    # Check if gsettings is available
    if ! command -v gsettings &> /dev/null; then
        log_error "gsettings command not found. Cannot configure Cinnamon clock."
        return 1
    fi

    local schema="org.cinnamon.desktop.interface"
    local key="clock-format"
    local current_format

    current_format=$(gsettings get "$schema" "$key" 2>/dev/null)

    if [[ "$current_format" != "'$DESIRED_FORMAT'" ]]; then
        log_info "Current format: $current_format. Desired: '$DESIRED_FORMAT'"
        log_info "Applying new clock format..."
        gsettings set "$schema" "$key" "$DESIRED_FORMAT"
        log_success "Cinnamon clock format updated."
    else
        log_success "Cinnamon clock format already set to the desired format."
    fi
}

# Configure MATE
configure_mate() {
    log_info "Detected MATE environment."
    if ! command -v gsettings &> /dev/null; then
        log_error "gsettings command not found. Cannot configure MATE clock."
        return 1
    fi

    local schema="org.mate.panel.applet.clock"
    local key="format"
    # MATE has a separate key for the format
    if gsettings get "$schema" custom-format-enabled | grep -q "false"; then
        log_info "Enabling custom format for MATE clock applet..."
        gsettings set "$schema" custom-format-enabled true
    fi

    local current_format
    current_format=$(gsettings get "$schema" custom-format 2>/dev/null)

    if [[ "$current_format" != "'$DESIRED_FORMAT'" ]]; then
        log_info "Current format: $current_format. Desired: '$DESIRED_FORMAT'"
        log_info "Applying new clock format..."
        gsettings set "$schema" custom-format "$DESIRED_FORMAT"
        log_success "MATE clock format updated."
    else
        log_success "MATE clock format already set to the desired format."
    fi
}


# Configure XFCE (Xubuntu, Debian with XFCE)
configure_xfce() {
    log_info "Detected XFCE environment."
    # Check if xfconf-query is available
    if ! command -v xfconf-query &> /dev/null; then
        log_error "xfconf-query command not found. Cannot configure XFCE clock."
        return 1
    fi

    local channel="xfce4-panel"
    # Find the clock plugin properties
    local clock_props=$(xfconf-query -c "$channel" -l -v | grep "plugin-.*clock")

    if [ -z "$clock_props" ]; then
        log_warn "Could not find an XFCE clock plugin in the panel."
        return 1
    fi

    # Assuming the first clock found is the one to change
    local clock_plugin_name=$(echo "$clock_props" | head -n 1 | awk '{print $1}')
    log_info "Found clock plugin: $clock_plugin_name"

    # Properties for XFCE clock
    local key_format="digital-format"
    local current_format

    current_format=$(xfconf-query -c "$channel" -p "$clock_plugin_name/$key_format" 2>/dev/null)

    if [[ "$current_format" != "$DESIRED_FORMAT" ]]; then
        log_info "Current format: $current_format. Desired: $DESIRED_FORMAT"
        log_info "Applying new clock format..."
        xfconf-query -c "$channel" -p "$clock_plugin_name/$key_format" -s "$DESIRED_FORMAT"
        log_success "XFCE clock format updated."
    else
        log_success "XFCE clock format already set to the desired format."
    fi
}

# --- Main Script Logic ---

main() {
    echo "--- Clock Format Configuration Script ---"
    
    # Get the detected desktop environment
    de=$(detect_desktop_environment)
    log_info "Desktop Environment: $de"

    # Route to the correct configuration function
    case "$de" in
        *gnome*)
            configure_gnome
            ;;
        *cinnamon*)
            configure_cinnamon
            ;;
        *mate*)
            configure_mate
            ;;
        *xfce*)
            configure_xfce
            ;;
        *)
            log_error "Unsupported desktop environment: '$de'."
            log_info "This script currently supports GNOME, Cinnamon, MATE, and XFCE."
            exit 1
            ;;
    esac

    echo "---------------------------------------"
}

# Run the main function
main


