#!/bin/bash

# --- Configuration ---
VM_NAME="Windows11_ARM"
VM_DIR="$HOME/Virtual Machines.localized/$VM_NAME.vmwarevm"
# Updated ISO Link (CrystalFetch or official MS links are best, but we will attempt a direct curl)
ISO_URL="https://software-static.download.prss.microsoft.com/dbazure/88896915-3030-4c85-9304-eb05e808246e/26100.1742.240906-0331.ge_release_svc_refresh_CLIENTCONSUMER_RET_A64FRE_en-us.iso"
ISO_PATH="$HOME/Downloads/Windows11_ARM.iso"

echo "### Starting Idempotent VMware Fusion & Windows Setup ###"

# 1. Install/Configure Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # CRITICAL: Load Homebrew into the current script session
    echo "Loading Homebrew into PATH..."
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Homebrew is already in PATH."
fi

# 2. Install VMware Fusion
if [ ! -d "/Applications/VMware Fusion.app" ]; then
    echo "Installing VMware Fusion..."
    brew install --cask vmware-fusion
else
    echo "VMware Fusion is already installed."
fi

# 3. Download Windows 11 ARM64 ISO
if [ ! -s "$ISO_PATH" ]; then
    echo "Downloading Windows 11 ARM64 ISO (This may take a while)..."
    # Added -L to follow redirects and -C - to resume if interrupted
    curl -L -C - -o "$ISO_PATH" "$ISO_URL"
else
    echo "ISO already exists and is not empty at $ISO_PATH."
fi

# 4. Create the VM Shell
if [ ! -d "$VM_DIR" ]; then
    echo "Creating VM Directory..."
    mkdir -p "$VM_DIR"
    
    cat <<EOF > "$VM_DIR/$VM_NAME.vmx"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
guestOS = "arm-windows11-64"
memsize = "8192"
numvcpus = "4"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.connectionType = "nat"
usb_xhci.present = "TRUE"
nvme0.present = "TRUE"
nvme0:0.fileName = "$VM_NAME.vmdk"
atapi.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$ISO_PATH"
managedvm.autoAddVTPM = "software"
EOF
else
    echo "VM directory already exists."
fi

# 5. Final Check and Launch
if [ -d "/Applications/VMware Fusion.app" ]; then
    echo "Launching VMware Fusion and starting VM..."
    open -a "VMware Fusion" "$VM_DIR/$VM_NAME.vmx"
else
    echo "ERROR: VMware Fusion failed to install. Please check your internet connection and run 'brew install --cask vmware-fusion' manually."
    exit 1
fi

echo "### Script Complete ###"
