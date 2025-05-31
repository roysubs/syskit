#!/bin/bash
# Author: Roy Wiseman 2025-02

# Add ~/syskit to PATH in both current session (if sourced) and in .bashrc

# Optional: Prevent the script running if not sourced (uncomment this line if required)
# (return 0 2>/dev/null) || { echo "This script must be sourced (e.g. prefix with '.' or 'source')"; exit 1; }

# Function to clean duplicate entries from PATH
clean_path() {
  PATH=$(echo "$PATH" | tr ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')
}

# Function to add a directory to PATH
add_to_path() {
  local DIR="$1"
  # Resolve absolute path (handles ~/ correctly)
  DIR=$(realpath -e "$HOME/${DIR/#\~\//}") || { echo "Directory $DIR does not exist, skipping."; return 1; }

  # Add to current session if sourced
  if (return 0 2>/dev/null); then
    if [[ ":$PATH:" != *":$DIR:"* ]]; then
      echo "Adding $DIR to PATH for the current session..."
      export PATH="$DIR:$PATH"
    else
      echo "$DIR is already in the PATH for the current session."
    fi
  fi
  # Ensure it's added to .bashrc
  local PROFILE_FILE="$HOME/.bashrc"
  if ! grep -qxF "export PATH=\"$DIR:\$PATH\"" "$PROFILE_FILE"; then
    echo "Adding $DIR to PATH in $PROFILE_FILE..."
    echo "export PATH=\"$DIR:\$PATH\"" >> "$PROFILE_FILE"
  else
    echo "$DIR is already in $PROFILE_FILE."
  fi
}

echo "
Console Login (TTY Login) order of Profile files:
/etc/profile     # System-wide initialization script for login shells (all shells, not just Bash)
~/.bash_profile  # if present, user-specific, if exists, Bash does not read ~/.bash_login or ~/.profile.
~/.bash_login    # Only if ~/.bash_profile is missing.
~/.profile       # Only if both ~/.bash_profile and ~/.bash_login are missing. Default in Debian (all shells, not just Bash)
~/.bashrc        # This or user shell-specific profiles are not default but commonly called from ~/.profile

GUI Login (via Display Manager, e.g., GDM, LightDM):
GUI login sessions generally load non-login shell configurations.
However, the initialization scripts depend on the Desktop Environment (DE).
Order of Profile Files (Common DEs like GNOME, KDE, XFCE):
/etc/profile     # Loaded by the display manager. Often responsible for system-wide environment variables.
~/.profile       # This file is executed unless overridden by ~/.bash_profile or similar.
Desktop Environment-Specific: ~/.gnomerc (GNOME), ~/.xprofile (KDE and XFCE), etc
Additionally:
System-wide files specific to the DE might also run, such as /etc/X11/Xsession or scripts in /etc/X11/Xsession.d/.

XTerm Session in GUI:
By default, an xterm starts a non-login shell.
However, you can force it to start a login shell (e.g., xterm -ls).

Non-Login Shell:
Bash reads only ~/.bashrc.

Login Shell (if started with xterm -ls):
The order of files is the same as for Console Login:
/etc/profile
~/.bash_profile
~/.bash_login
~/.profile
Summary of Key Files
/etc/profile – System-wide initialization for login shells.
~/.bash_profile, ~/.bash_login, ~/.profile – User-specific login scripts.
~/.bashrc – Always read for non-login interactive shells.

Debugging Tip:
To trace exactly what is loaded in your environment:
echo \$0          # Check the current shell
bash -x --login  # Debug login shell startup scripts
bash -x          # Debug non-login shell startup scripts
"

# Clean PATH before adding new directories
clean_path

# Apply function to both directories
add_to_path "syskit"
add_to_path "syskit/0-scripts"

# Check if script was sourced
if ! (return 0 2>/dev/null); then
  echo -e "\n\033[1;31mWARNING:\033[0m This script was not sourced!"
  echo -e "  - The directories have been added to \033[1m.bashrc\033[0m and will apply next time you start a new shell."
  echo -e "  - However, \033[1mthis current session is NOT updated!\033[0m"
  echo -e "To do this, rerun this script sourced, or apply .bashrc with:"
  echo -e "    \033[1;32msource ~/.bashrc\033[0m"
else
  echo -e "\n\033[1;32mSuccess!\033[0m PATH updated for the current session and future shells."
fi

# Display updated PATH
echo -e "\nCurrent PATH:\n$PATH"

