#!/bin/bash
# Author: Roy Wiseman 2025-02

# =============================================================================
# Dwarf Fortress Classic (64-bit) Complete Setup Script for Debian/Ubuntu
# =============================================================================
# This script aims to install necessary 64-bit libraries, apply fixes,
# and configure Dwarf Fortress Classic (64-bit version) on Debian-based systems.
# Version: 3.0 (Includes ncurses symlink fix)
# =============================================================================

# --- Configuration ---
# Path to your Dwarf Fortress installation folder
DF_PATH="/opt/dwarf_fortress_legacy/0.47.05" # <-- MODIFY THIS TO YOUR ACTUAL DF PATH!

# Path to the Dwarf Fortress init.txt file
DF_INIT_FILE="$DF_PATH/data/init/init.txt"

# Path to the DF libs directory
DF_LIBS_PATH="$DF_PATH/libs"
# ---------------------

echo "======================================================"
echo "Dwarf Fortress Classic (64-bit) Setup Script v3.0"
echo "======================================================"

# Function to install required 64-bit libraries
install_required_libraries() {
    echo "Step 1: Installing required 64-bit libraries..."
    echo "----------------------------------------"

    echo "Updating package lists..."
    sudo apt-get update

    echo "Installing 64-bit SDL, GTK, OpenAL, Ncurses, and terminfo libraries..."
    REQUIRED_PACKAGES=(
        libsdl1.2debian
        libsdl-image1.2
        libsdl-ttf2.0-0
        libglu1-mesa
        libgtk2.0-0      # Often used by DF launcher or for window hints
        libopenal1       # For sound
        libncursesw6     # For terminal interface (wide character)
        ncurses-term     # Comprehensive terminfo definitions, good for SSH
    )

    sudo apt-get install -y "${REQUIRED_PACKAGES[@]}"

    if [ $? -eq 0 ]; then
        echo "✓ 64-bit libraries installation attempt complete."
        echo "  Please check for any individual package errors above."
    else
        echo "✗ Some packages might have failed to install. Please check the output."
    fi
    echo ""
}

# Function to fix ncurses probing by creating a symlink
fix_ncurses_probing_symlink() {
    echo "Step 2: Fixing ncurses probing issue for Dwarf Fortress..."
    echo "----------------------------------------"

    if [ ! -d "$DF_LIBS_PATH" ]; then
        echo "✗ Error: DF libs directory not found at $DF_LIBS_PATH. Cannot create ncurses symlink."
        return 1
    fi

    SYSTEM_NCURSESW_PATH="/lib/x86_64-linux-gnu/libncursesw.so.6" # Standard path on Debian/Ubuntu 64-bit

    if [ -f "$SYSTEM_NCURSESW_PATH" ]; then
        DF_NCURSESW_SYMLINK="$DF_LIBS_PATH/libncursesw.so"
        echo "Creating symlink for ncurses in DF's libs directory:"
        echo "  $DF_NCURSESW_SYMLINK -> $SYSTEM_NCURSESW_PATH"
        if sudo ln -sf "$SYSTEM_NCURSESW_PATH" "$DF_NCURSESW_SYMLINK"; then
            echo "✓ Successfully created ncurses symlink."
        else
            echo "✗ Error creating ncurses symlink. Check permissions or if paths are correct."
        fi
    else
        echo "✗ System library $SYSTEM_NCURSESW_PATH not found."
        echo "  Ensure libncursesw6 was installed correctly in Step 1."
    fi
    echo ""
}

# Function to fix libstdc++ version conflicts
fix_libstdcpp_conflict() {
    echo "Step 3: Checking for libstdc++ version conflicts..."
    echo "----------------------------------------"

    if [ ! -d "$DF_LIBS_PATH" ]; then
        echo "✗ Error: DF libs directory not found at $DF_LIBS_PATH"
        return 1
    fi

    if [ -f "$DF_LIBS_PATH/libstdc++.so.6" ]; then
        echo "Found bundled libstdc++.so.6. Renaming to avoid potential conflicts..."
        if sudo mv "$DF_LIBS_PATH/libstdc++.so.6" "$DF_LIBS_PATH/libstdc++.so.6.dfbackup"; then
            echo "✓ Successfully renamed $DF_LIBS_PATH/libstdc++.so.6 to libstdc++.so.6.dfbackup"
            echo "  DF will now use the system's compatible libstdc++.so.6"
        else
            echo "✗ Error renaming libstdc++.so.6. Check permissions."
            return 1
        fi
    else
        echo "✓ No bundled libstdc++.so.6 found in DF libs directory, or already renamed."
    fi
    echo ""
}

# Function to set PRINT_MODE to TEXT
fix_print_mode() {
    echo "Step 4: Setting PRINT_MODE to TEXT..."
    echo "----------------------------------------"

    if [ ! -f "$DF_INIT_FILE" ]; then
        echo "✗ Error: init.txt file not found at $DF_INIT_FILE"
        return 1
    fi

    if [ ! -f "${DF_INIT_FILE}.backup_original_setup" ]; then # Use a unique backup name
        sudo cp "$DF_INIT_FILE" "${DF_INIT_FILE}.backup_original_setup"
        echo "✓ Created backup: ${DF_INIT_FILE}.backup_original_setup"
    else
        echo "✓ Backup ${DF_INIT_FILE}.backup_original_setup already exists."
    fi

    echo "Current PRINT_MODE setting:"
    grep "\[PRINT_MODE:" "$DF_INIT_FILE" | head -1
    sudo sed -i 's/\[PRINT_MODE:.*\]/\[PRINT_MODE:TEXT\]/' "$DF_INIT_FILE"
    echo "New PRINT_MODE setting:"
    grep "\[PRINT_MODE:" "$DF_INIT_FILE" | head -1

    if grep -q "\[PRINT_MODE:TEXT\]" "$DF_INIT_FILE"; then
        echo "✓ PRINT_MODE successfully set to TEXT"
    else
        echo "✗ Warning: PRINT_MODE may not have been set correctly."
    fi
    echo ""
}

# Function to create a convenient launch script
create_launch_script() {
    echo "Step 5: Creating launch script..."
    echo "----------------------------------------"

    LAUNCH_SCRIPT="$DF_PATH/launch_df.sh"
    sudo tee "$LAUNCH_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# Dwarf Fortress Classic Launcher (for 64-bit)
# Created by setup script

# Set a common TERM type if running in specific environments like SSH
# You can change 'xterm' to 'linux', 'vt100', or your preferred type
# if you encounter terminal issues.
export TERM=xterm

echo "Launching Dwarf Fortress from: $DF_PATH (TERM=\$TERM)"
cd "$DF_PATH"
exec ./df "\$@"
EOF

    sudo chmod +x "$LAUNCH_SCRIPT"
    if [ -f "$LAUNCH_SCRIPT" ]; then
        echo "✓ Created launch script: $LAUNCH_SCRIPT"
    else
        echo "✗ Error creating launch script"
    fi
    echo ""
}

# Function to create system-wide symlink
create_system_symlink() {
    echo "Step 6: Creating system-wide symlink..."
    echo "----------------------------------------"

    SYMLINK_PATH="/usr/local/bin/dwarf-fortress"
    LAUNCH_SCRIPT="$DF_PATH/launch_df.sh"

    if [ -f "$LAUNCH_SCRIPT" ]; then
        if [ -L "$SYMLINK_PATH" ] || [ -f "$SYMLINK_PATH" ]; then # Check if it exists as link or file
            sudo rm -f "$SYMLINK_PATH"
        fi
        sudo ln -s "$LAUNCH_SCRIPT" "$SYMLINK_PATH"
        if [ -L "$SYMLINK_PATH" ]; then
            echo "✓ Created system symlink: $SYMLINK_PATH -> $LAUNCH_SCRIPT"
            echo "  You can now run DF from anywhere with: dwarf-fortress"
        else
            echo "✗ Error creating system symlink"
        fi
    else
        echo "✗ Launch script not found, cannot create symlink"
    fi
    echo ""
}

# Function to verify the installation
verify_installation() {
    echo "Step 7: Verifying installation..."
    echo "----------------------------------------"
    DF_EXECUTABLE="$DF_LIBS_PATH/Dwarf_Fortress"

    if [ ! -d "$DF_PATH" ]; then echo "✗ DF directory not found at $DF_PATH"; return 1; fi
    if [ ! -f "$DF_EXECUTABLE" ]; then echo "✗ DF executable not found at $DF_EXECUTABLE"; return 1; fi

    EXECUTABLE_TYPE=$(file "$DF_EXECUTABLE")
    if echo "$EXECUTABLE_TYPE" | grep -q "ELF 64-bit"; then
        echo "✓ DF executable is 64-bit."
    else
        echo "✗ WARNING: DF executable ($DF_EXECUTABLE) might not be 64-bit! Found: $EXECUTABLE_TYPE"
    fi

    if [ -f "$DF_INIT_FILE" ] && grep -q "\[PRINT_MODE:TEXT\]" "$DF_INIT_FILE"; then
        echo "✓ init.txt found with PRINT_MODE:TEXT"
    else
        echo "✗ init.txt not found or PRINT_MODE not set to TEXT"
    fi

    if [ -L "$DF_LIBS_PATH/libncursesw.so" ] && [ "$(readlink "$DF_LIBS_PATH/libncursesw.so")" = "$SYSTEM_NCURSESW_PATH" ]; then
        echo "✓ Ncurses symlink $DF_LIBS_PATH/libncursesw.so correctly points to $SYSTEM_NCURSESW_PATH"
    else
        echo "✗ Ncurses symlink $DF_LIBS_PATH/libncursesw.so is missing or incorrect."
        echo "  Expected target: $SYSTEM_NCURSESW_PATH"
        if [ -L "$DF_LIBS_PATH/libncursesw.so" ]; then
             echo "  Actual target: $(readlink "$DF_LIBS_PATH/libncursesw.so")"
        fi
    fi

    echo ""
    echo "Checking for remaining missing libraries (for $DF_EXECUTABLE):"
    MISSING_LIBS=$(ldd "$DF_EXECUTABLE" 2>/dev/null | grep "not found")
    if [ -n "$MISSING_LIBS" ]; then
        echo "$MISSING_LIBS"
        echo "✗ Some libraries appear to be missing. Ensure packages from Step 1 installed."
    else
        echo "✓ No obviously missing libraries reported by ldd for the main executable."
    fi

    echo "✓ Installation verification complete"
    echo ""
}

# Function to display final instructions
show_final_instructions() {
    echo "========================================="
    echo "SETUP COMPLETE!"
    echo "========================================="
    echo ""
    echo "To run Dwarf Fortress Classic (64-bit):"
    echo "  Method 1: dwarf-fortress (from anywhere, uses TERM=xterm by default)"
    echo "  Method 2: cd \"$DF_PATH\" && ./df"
    echo "  Method 3: $DF_PATH/launch_df.sh"
    echo ""
    echo "If you encounter issues:"
    echo "  1. Ensure DF_PATH ('$DF_PATH') is correct in this script."
    echo "  2. Verify libraries from Step 1 installed (sudo apt-get install --reinstall <package_name>)."
    echo "  3. Check backup files created by this script (e.g., ${DF_INIT_FILE}.backup_original_setup)."
    echo "  4. Run: ldd $DF_LIBS_PATH/Dwarf_Fortress | grep 'not found'"
    echo "  5. For terminal display issues, ensure your SSH client is sending a common TERM type"
    echo "     (e.g., xterm, xterm-256color) and try setting 'export TERM=xterm' before launch."
    echo ""
    echo "Optional: gamelog.txt permission"
    echo "  If DF cannot write to gamelog.txt in '$DF_PATH',"
    echo "  you may need to adjust permissions, e.g.:"
    echo "  sudo chown -R \$(whoami):\$(whoami) \"$DF_PATH\""
    echo ""
    echo "Backup files created:"
    echo "  - ${DF_INIT_FILE}.backup_original_setup (original init.txt)"
    if [ -f "$DF_LIBS_PATH/libstdc++.so.6.dfbackup" ]; then
        echo "  - $DF_LIBS_PATH/libstdc++.so.6.dfbackup (original bundled library)"
    fi
    echo ""
    echo "Have fun digging too deep! ⚒️🏔️"
    echo "========================================="
}

# Main function
main() {
    echo "Starting Dwarf Fortress Classic (64-bit) setup..."
    echo "DF Path: $DF_PATH"
    echo ""

    if [ ! -d "$DF_PATH" ]; then
        echo "✗ Error: Dwarf Fortress directory not found at $DF_PATH. Please edit the script."
        exit 1
    fi
    if [ ! -f "$DF_LIBS_PATH/Dwarf_Fortress" ]; then
        echo "✗ Error: Main DF executable not found at $DF_LIBS_PATH/Dwarf_Fortress. Ensure DF is extracted."
        exit 1
    fi
    EXECUTABLE_TYPE_CHECK=$(file "$DF_LIBS_PATH/Dwarf_Fortress")
    if ! echo "$EXECUTABLE_TYPE_CHECK" | grep -q "ELF 64-bit"; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! WARNING: $DF_LIBS_PATH/Dwarf_Fortress does not appear to be a 64-bit executable! !!"
        echo "!! Found: $EXECUTABLE_TYPE_CHECK                                                 !!"
        echo "!! This script is intended for 64-bit Dwarf Fortress.                              !!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        read -p "Do you want to continue anyway? (yes/No): " confirm_64bit
        if [[ "$confirm_64bit" != "yes" && "$confirm_64bit" != "Yes" && "$confirm_64bit" != "YES" ]]; then
            echo "Exiting setup."
            exit 1
        fi
    fi

    install_required_libraries
    fix_ncurses_probing_symlink # NEW STEP
    fix_libstdcpp_conflict
    fix_print_mode
    create_launch_script
    create_system_symlink
    verify_installation
    show_final_instructions
}

if [ "$(id -u)" = "0" ]; then
    echo "Warning: Running as root is not ideal. This script uses sudo where needed."
    echo "It's generally safer to run as a regular user."
fi

main
