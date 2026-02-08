#!/bin/bash

# ==============================================================================
# M4 MAC MINI - WINDOWS 11 ARM64 INSTALLATION SCRIPT
# ==============================================================================
clear
echo "=========================================================================="
echo "💡 IMPORTANT KNOWLEDGE BASE (Read before proceeding)"
echo "=========================================================================="
echo "1. WHY UTM? VMware Fusion now requires a Broadcom login to download,"
echo "   making it difficult to script. UTM is open-source and native to M4."
echo ""
echo "2. ISO REQUIREMENT: Microsoft direct links expire. If the script fails,"
echo "   manually download the 'Windows 11 ARM64 Insider Preview' ISO to:"
echo "   ~/Downloads/Windows11_ARM.iso"
echo ""
echo "3. THE NETWORK BYPASS (CRITICAL):"
echo "   Windows 11 will get stuck on the 'Connect to Network' screen."
echo "   - Press Shift + Fn + F10"
echo "   - Type: OOBE\\BYPASSNRO"
echo "   - The VM will reboot. Select 'I don't have internet' to continue."
echo ""
echo "4. DRIVERS: This script downloads 'spice-guest-tools'. You MUST mount"
echo "   this ISO in UTM after Windows is installed to get internet/graphics."
echo "=========================================================================="
echo ""
read -p "Press [ENTER] to start the setup..."

# --- Configuration ---
VM_NAME="Windows11_M4"
ISO_PATH="$HOME/Downloads/Windows11_ARM.iso"
GUEST_TOOLS="$HOME/Downloads/spice-guest-tools.iso"

# 1. Ensure Homebrew is functional
if ! command -v brew &> /dev/null; then
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# 2. Install UTM
if [ ! -d "/Applications/UTM.app" ]; then
    echo "Installing UTM..."
    brew install --cask utm
else
    echo "UTM is already installed."
fi

# 3. Check for the Windows ISO
if [ ! -s "$ISO_PATH" ]; then
    echo "❌ ERROR: Windows 11 ARM ISO not found at $ISO_PATH."
    exit 1
fi

# 4. Download SPICE Guest Tools
if [ ! -f "$GUEST_TOOLS" ]; then
    echo "Downloading SPICE guest tools..."
    curl -L -o "$GUEST_TOOLS" https://github.com/utmapp/UTM/releases/download/v4.0.0/spice-guest-tools-0.164.iso
fi

# 5. Launch UTM
echo "✅ Setup Complete. Launching UTM..."
open -a "UTM"

echo ""
echo "FINAL STEPS IN UTM UI:"
echo "1. Click + -> Virtualize -> Windows."
echo "2. Browse for ISO: $ISO_PATH"
echo "3. Ensure 'Install drivers and SPICE tools' is checked."
echo "4. Follow the 'Shift+F10' bypass instructions printed above."
