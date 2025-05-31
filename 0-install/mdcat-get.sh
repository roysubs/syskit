#!/bin/bash
# Author: Roy Wiseman 2025-05

# Define the location where mdcat will be installed
INSTALL_DIR="/usr/local/bin"
MD_CAT_BIN="$INSTALL_DIR/mdcat"
README_FILE="$INSTALL_DIR/mdcat-README.md" # mdcat's README, renamed for clarity

# Function to install jq if not present
ensure_jq_installed() {
  if ! command -v jq &> /dev/null; then
    echo "jq not found, attempting to install it..."
    if command -v apt &> /dev/null;   then sudo apt update && sudo apt install -y jq
    elif command -v yum &> /dev/null;  then sudo yum install -y jq
    elif command -v dnf &> /dev/null;  then sudo dnf install -y jq
    elif command -v pacman &> /dev/null; then sudo pacman -Syu --noconfirm jq
    elif command -v zypper &> /dev/null; then sudo zypper install -y jq
    else
      echo "Error: Could not find a known package manager (apt, yum, dnf, pacman, zypper) to install jq." >&2
      echo "Please install jq manually and re-run the script." >&2
      exit 1
    fi
    if ! command -v jq &> /dev/null; then
      echo "Error: jq installation failed or was not found after attempting installation." >&2
      echo "Please install jq manually and re-run the script." >&2
      exit 1
    fi
    echo "jq installed successfully."
  else
    echo "jq is already installed."
  fi
}

# Function to download and install mdcat
install_mdcat() {
  echo "Attempting to install the latest version of mdcat to $INSTALL_DIR..."

  ensure_jq_installed

  echo "Fetching the latest mdcat release URL..."
  LATEST_URL=$(curl -s https://api.github.com/repos/swsnr/mdcat/releases/latest | jq -r ".assets[] | select(.name | test(\".*x86_64-unknown-linux-gnu.tar.gz$\")) | .browser_download_url")

  if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" == "null" ]; then
    echo "Error: Could not find the latest mdcat release URL for x86_64-unknown-linux-gnu." >&2
    echo "This might be due to rate limiting by GitHub API, jq parsing issues, or no suitable asset found." >&2
    exit 1
  fi

  DL_TMP_FILE=$(mktemp --suffix=.tar.gz)
  if [ -z "$DL_TMP_FILE" ]; then
    echo "Error: Could not create temporary file for download." >&2
    exit 1
  fi

  echo "Downloading mdcat from $LATEST_URL to $DL_TMP_FILE..."
  if ! wget --show-progress "$LATEST_URL" -O "$DL_TMP_FILE"; then
    echo "Error: Failed to download mdcat from $LATEST_URL." >&2
    rm -f "$DL_TMP_FILE"
    exit 1
  fi

  TEMP_DIR=$(mktemp -d)
  if [ -z "$TEMP_DIR" ]; then
    echo "Error: Could not create temporary directory for extraction." >&2
    rm -f "$DL_TMP_FILE"
    exit 1
  fi

  echo "Extracting mdcat to $TEMP_DIR..."
  if ! tar -xzf "$DL_TMP_FILE" -C "$TEMP_DIR"; then
    echo "Error: Failed to extract mdcat tarball." >&2
    rm -f "$DL_TMP_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  # Dynamically find the extracted directory name (it often includes version info)
  EXTRACTED_SUBDIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)
  if [ -z "$EXTRACTED_SUBDIR" ]; then
      # If no subdirectory, assume files are directly in TEMP_DIR (less common for tarballs)
      EXTRACTED_SUBDIR="$TEMP_DIR"
  fi
  
  EXTRACTED_MDCAT_PATH="$EXTRACTED_SUBDIR/mdcat"
  EXTRACTED_README_PATH="$EXTRACTED_SUBDIR/README.md"

  if [ ! -f "$EXTRACTED_MDCAT_PATH" ]; then
    echo "Error: Could not find 'mdcat' binary in the extracted files (expected at $EXTRACTED_MDCAT_PATH)." >&2
    echo "Contents of $EXTRACTED_SUBDIR:" >&2
    ls -lA "$EXTRACTED_SUBDIR" >&2
    rm -f "$DL_TMP_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  echo "Preparing to install mdcat to $MD_CAT_BIN..."

  SUDO_CMD=""
  if [ "$(id -u)" -ne 0 ]; then # If not already root
    if sudo -v &>/dev/null; then # Check if sudo is usable & update timestamp
      SUDO_CMD="sudo"
      echo "Using sudo for installation to $INSTALL_DIR."
    else
      echo "Error: Root privileges are required to install to $INSTALL_DIR, but sudo is not available/configured or password not entered." >&2
      echo "Please run this script as root, or ensure you can use sudo." >&2
      rm -f "$DL_TMP_FILE"
      rm -rf "$TEMP_DIR"
      exit 1
    fi
  else
    echo "Running as root, sudo prefix not needed for installation commands."
  fi

  # Ensure INSTALL_DIR exists (it really should for /usr/local/bin)
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "Warning: Installation directory $INSTALL_DIR does not exist." >&2
    echo "Attempting to create $INSTALL_DIR (using $SUDO_CMD if applicable)..." >&2
    if ! $SUDO_CMD mkdir -p "$INSTALL_DIR"; then
      echo "Error: Failed to create $INSTALL_DIR." >&2
      rm -f "$DL_TMP_FILE"
      rm -rf "$TEMP_DIR"
      exit 1
    fi
  fi

  echo "Moving mdcat binary to $MD_CAT_BIN..."
  if ! $SUDO_CMD mv "$EXTRACTED_MDCAT_PATH" "$MD_CAT_BIN"; then
    echo "Error: Failed to move mdcat binary to $MD_CAT_BIN using $SUDO_CMD." >&2
    echo "Attempted: $SUDO_CMD mv \"$EXTRACTED_MDCAT_PATH\" \"$MD_CAT_BIN\"" >&2
    rm -f "$DL_TMP_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  if ! $SUDO_CMD chmod +x "$MD_CAT_BIN"; then
      echo "Warning: Failed to set execute permissions on $MD_CAT_BIN using $SUDO_CMD." >&2
      # This is unlikely to be a fatal error if mv preserves permissions and original is executable
  fi

  if [ -f "$EXTRACTED_README_PATH" ]; then
    echo "Moving README.md to $README_FILE..."
    if ! $SUDO_CMD mv "$EXTRACTED_README_PATH" "$README_FILE"; then
      echo "Warning: Failed to move README.md to $README_FILE using $SUDO_CMD. Continuing." >&2
    fi
  else
    echo "Warning: README.md not found in the archive. Skipping."
  fi

  # Cleanup
  rm -f "$DL_TMP_FILE"
  rm -rf "$TEMP_DIR"

  echo "mdcat installation to $INSTALL_DIR completed successfully."
  echo "$MD_CAT_BIN should now be available system-wide (if $INSTALL_DIR is in PATH)."
}

# --- Main script execution ---

# Check if mdcat is already installed and executable at the target location
# `command -v` is a good primary check if /usr/local/bin is reliably in PATH
if command -v mdcat &> /dev/null && [ -x "$MD_CAT_BIN" ]; then
  echo "mdcat is already installed at $MD_CAT_BIN and is executable."
else
  # Provide more detailed feedback if one of the conditions failed
  if ! command -v mdcat &> /dev/null; then
    echo "mdcat not found by 'command -v'."
  elif [ ! -x "$MD_CAT_BIN" ]; then # mdcat found by command -v but not our target, or not executable
    echo "mdcat found by 'command -v' but either not at $MD_CAT_BIN or not executable there."
  fi
  install_mdcat # This will attempt to install to /usr/local/bin

  # Post-install check
  if command -v mdcat &> /dev/null && [ -x "$MD_CAT_BIN" ]; then
    echo "mdcat successfully installed/verified at $MD_CAT_BIN."
  else
    echo "Error: mdcat installation was attempted, but it's still not found or not executable at $MD_CAT_BIN." >&2
    echo "Please check for errors above. Manual installation might be required." >&2
    exit 1 # Exit if installation failed to make mdcat available
  fi
fi

echo ""
echo "mdcat-get.sh finished."
echo "If this script was run for the first time from another script (like your h-* scripts),"
echo "that parent script should execute 'hash -r' after this installer completes"
echo "to ensure the shell recognizes the newly installed 'mdcat' command."
echo ""
echo "You should now be able to use 'mdcat'. Try: mdcat --version"

exit 0
