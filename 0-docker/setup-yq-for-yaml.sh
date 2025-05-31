#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to ensure mikefarah/yq is installed,
# and to remove conflicting 'yq' apt packages if found.

# Exit on any error, treat unset variables as an error, and propagate pipeline errors
set -euo pipefail

# Signature string for mikefarah/yq's version output
MIKEFARAH_YQ_SIGNATURE="mikefarah/yq"
YQ_VERSION_LATEST="latest" # Or specify a version like "v4.40.5"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="${INSTALL_DIR}/yq"

# --- Helper Functions ---
log_info() {
    echo "INFO: $1"
}

log_warn() {
    echo "WARN: $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

# --- Main Logic ---

# 1. Check if the correct yq (mikefarah/yq) is installed and operational
if command -v yq &>/dev/null && yq --version 2>&1 | grep -qF "$MIKEFARAH_YQ_SIGNATURE"; then
    log_info "Correct yq (mikefarah/yq) is already installed: $(yq --version)"
    exit 0
fi

# 2. A 'yq' command might exist, but it's not mikefarah/yq, or no 'yq' is found.
if command -v yq &>/dev/null; then
    # 'yq' command exists, but it's not mikefarah/yq.
    log_warn "An existing 'yq' command was found, but it's not the desired mikefarah/yq."

    YQ_PATH=$(command -v yq)
    CURRENT_YQ_VERSION_OUTPUT=$(yq --version 2>&1 | head -n 1 || echo "Could not get version")
    log_info "Found at: ${YQ_PATH}"
    log_info "Current 'yq' version output: ${CURRENT_YQ_VERSION_OUTPUT}"

    # Check if this yq is from an apt package (commonly 'yq' or 'python3-yq' for the kislyuk/yq version)
    OWNER_INFO=""
    if command -v dpkg &>/dev/null; then
        OWNER_INFO=$(dpkg -S "${YQ_PATH}" 2>/dev/null || true) # Capture output, ignore dpkg errors if path not found
    else
        log_warn "dpkg command not found. Cannot determine if existing yq is from an apt package."
    fi

    # Check if OWNER_INFO is not empty and matches known apt package names for the other yq
    if [ -n "${OWNER_INFO}" ] && echo "${OWNER_INFO}" | grep -qE "^(yq|python3-yq):"; then
        APT_PACKAGE_NAME=$(echo "${OWNER_INFO}" | cut -d':' -f1)
        log_warn "This 'yq' at ${YQ_PATH} appears to be installed by the apt package: '${APT_PACKAGE_NAME}'."
        log_warn "This is likely 'kislyuk/yq' (a Python-based YAML processor, often a wrapper for jq), not 'mikefarah/yq'."
        log_info "Attempting to remove apt package '${APT_PACKAGE_NAME}' to avoid conflicts..."

        if sudo apt-get remove -y "${APT_PACKAGE_NAME}"; then
            log_info "Successfully removed apt package '${APT_PACKAGE_NAME}'."
            # Check if the command is now gone or different
            if command -v yq &>/dev/null; then
                if ! (yq --version 2>&1 | grep -qF "$MIKEFARAH_YQ_SIGNATURE"); then
                    log_warn "A 'yq' command still exists after removal, and it's still not mikefarah/yq."
                    log_warn "Path: $(command -v yq)"
                    log_warn "Version: $(yq --version 2>&1 | head -n 1 || echo 'Could not get version')"
                    log_warn "Proceeding with mikefarah/yq installation. Ensure your PATH is configured correctly if issues persist."
                fi
            else
                log_info "The conflicting 'yq' command is no longer found in PATH."
            fi
        else
            log_error "Failed to remove apt package '${APT_PACKAGE_NAME}' automatically."
            log_error "Please try removing it manually (e.g., 'sudo apt remove ${APT_PACKAGE_NAME}') and re-run the script."
            # Decide on strictness:
            # exit 1 # Exit if removal is critical before proceeding
            log_warn "Continuing with mikefarah/yq installation, but conflicts might occur if the old yq is still active."
        fi
    else
        log_warn "The existing 'yq' at ${YQ_PATH} is not mikefarah/yq, but it does not appear to be from the common 'yq' or 'python3-yq' apt packages (or dpkg is not available)."
        log_warn "It might be a different tool or a manually installed version of another yq."
        log_warn "mikefarah/yq will be installed to ${INSTALL_PATH}."
        log_warn "If the existing command is ${INSTALL_PATH}, it will likely be overwritten."
        log_warn "Otherwise, ensure ${INSTALL_DIR} is prioritized in your PATH to use the correct yq."
    fi
else
    log_info "'yq' command not found. Will proceed to install mikefarah/yq."
fi

# 3. Proceed with mikefarah/yq installation
log_info "Installing mikefarah/yq..."
YQ_ARCH=$(uname -m)
case "${YQ_ARCH}" in
    x86_64) YQ_BINARY="yq_linux_amd64";;
    aarch64 | arm64) YQ_BINARY="yq_linux_arm64";; # arm64 is another name for aarch64
    i386 | i686) YQ_BINARY="yq_linux_386";;
    armv7l) YQ_BINARY="yq_linux_arm";;
    *) log_error "Unsupported architecture: ${YQ_ARCH}. Cannot determine yq binary for mikefarah/yq."; exit 1;;
esac

# Ensure INSTALL_DIR directory exists
if [ ! -d "${INSTALL_DIR}" ]; then
    log_info "Creating directory ${INSTALL_DIR} as it does not exist..."
    if ! sudo mkdir -p "${INSTALL_DIR}"; then
        log_error "Failed to create ${INSTALL_DIR} directory."
        exit 1
    fi
fi

TEMP_YQ_DOWNLOAD=$(mktemp) || { log_error "Failed to create temporary file for download."; exit 1; }
trap 'rm -f "${TEMP_YQ_DOWNLOAD}"' EXIT # Ensure temp file is cleaned up

log_info "Downloading ${YQ_BINARY} (${YQ_VERSION_LATEST}) from GitHub to temporary file ${TEMP_YQ_DOWNLOAD}..."
if curl -fsSL "https://github.com/mikefarah/yq/releases/${YQ_VERSION_LATEST}/download/${YQ_BINARY}" -o "${TEMP_YQ_DOWNLOAD}"; then
    log_info "Download successful. Moving to ${INSTALL_PATH} and setting permissions..."
    if sudo mv "${TEMP_YQ_DOWNLOAD}" "${INSTALL_PATH}"; then
        if ! sudo chmod +x "${INSTALL_PATH}"; then
            log_error "Failed to set executable permissions on ${INSTALL_PATH}."
            log_info "Cleaning up potentially moved file: ${INSTALL_PATH}"
            sudo rm -f "${INSTALL_PATH}" # Attempt to remove if move succeeded but chmod failed
            exit 1
        fi
        log_info "mikefarah/yq installed and made executable at ${INSTALL_PATH}."
        trap - EXIT # Clear trap as temp file is successfully moved
    else
        log_error "Failed to move downloaded yq from ${TEMP_YQ_DOWNLOAD} to ${INSTALL_PATH}."
        # TEMP_YQ_DOWNLOAD will be removed by trap
        exit 1;
    fi
else
    log_error "Failed to download mikefarah/yq from GitHub."
    # TEMP_YQ_DOWNLOAD will be removed by trap
    # curl with -f will not output the error page, but will return non-zero.
    # If a file was partially created at TEMP_YQ_DOWNLOAD, it will be cleaned by trap.
    exit 1
fi


# 4. Verification
log_info "Verifying installation..."
# Use the absolute path for verification first
if "${INSTALL_PATH}" --version 2>&1 | grep -qF "$MIKEFARAH_YQ_SIGNATURE"; then
    log_info "Verification of ${INSTALL_PATH} successful: $(${INSTALL_PATH} --version)"

    # Now check if 'yq' command in PATH resolves to the correct one
    if command -v yq &>/dev/null && yq --version 2>&1 | grep -qF "$MIKEFARAH_YQ_SIGNATURE"; then
        log_info "The 'yq' command in PATH is now correctly pointing to mikefarah/yq."
        log_info "Active yq path: $(command -v yq)"
        log_info "Active yq version: $(yq --version)"
    else
        log_warn "${INSTALL_PATH} is correct, but the 'yq' command in your PATH is not (or not yet) mikefarah/yq."
        log_warn "This can be due to PATH caching by your shell, or another yq version in a directory that appears earlier in your PATH."
        log_warn "Try opening a new terminal session or sourcing your shell profile (e.g., source ~/.bashrc)."
        if command -v yq &>/dev/null; then
            log_warn "Currently, 'yq' in PATH points to: $(command -v yq)"
            log_warn "Its version is: $(yq --version 2>&1 | head -n 1 || echo 'Could not get version')"
        else
            log_warn "Currently, 'yq' command is not found in PATH despite successful installation to ${INSTALL_PATH}."
        fi
        if ! echo "$PATH" | grep -q ":${INSTALL_DIR}"; then # Check more accurately
             if ! echo "$PATH" | grep -q "^${INSTALL_DIR}"; then
                log_warn "Important: The directory ${INSTALL_DIR} does not seem to be in your PATH or is not correctly formatted."
                log_warn "Your PATH: $PATH"
                log_warn "Please add it, for example: echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
             fi
        fi
    fi
else
    INSTALLED_YQ_VERSION_OUTPUT=$("${INSTALL_PATH}" --version 2>&1 || echo "Command failed or produced no output")
    log_error "Verification of downloaded file ${INSTALL_PATH} FAILED. It does not seem to be mikefarah/yq."
    log_error "Output of ${INSTALL_PATH} --version: ${INSTALLED_YQ_VERSION_OUTPUT}"
    log_info "Cleaning up incorrect download: ${INSTALL_PATH}"
    sudo rm -f "${INSTALL_PATH}"
    exit 1
fi

log_info "Script finished. mikefarah/yq should be correctly installed and accessible."
