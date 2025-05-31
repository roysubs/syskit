#!/bin/bash
# Author: Roy Wiseman 2025-01

# --- Script Configuration ---
# Stop on any error
set -e

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

warning() {
    echo "[WARNING] $1"
}

error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_command_exists() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 command not found. Please install it and try again."
    fi
}

# --- Step 0: Prerequisites and Initial Setup ---
info "Starting Azure VM Setup Script..."
info "This script will guide you through:"
info "1. Installing the Azure CLI (if not already installed)."
info "2. Logging into your Azure account."
info "3. Creating a Resource Group."
info "4. Creating a Free Tier-eligible Linux Virtual Machine."
info "5. Connecting to the Virtual Machine via SSH."

warning "IMPORTANT: This script attempts to create resources within Azure's Free Tier."
warning "It is YOUR responsibility to understand Azure's Free Tier terms and conditions to avoid unexpected costs."
warning "Visit https://azure.microsoft.com/free for the latest details."
warning "You will be prompted for inputs like resource names and usernames."
echo

# Check for essential tools
check_command_exists "curl"
check_command_exists "ssh"
# `gpg` and package managers will be checked during az cli installation if needed

# --- Step 1: Install Azure CLI (if not present) ---
install_azure_cli() {
    info "Checking for Azure CLI..."
    if command -v az &> /dev/null; then
        info "Azure CLI is already installed."
        az --version
        return
    fi

    info "Azure CLI not found. Attempting installation..."
    warning "This will require sudo privileges."

    # Universal installer script (recommended by Microsoft for most Linux distros)
    # See: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=script
    if curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash; then
        info "Azure CLI installed successfully using DEB script."
    elif curl -sL https://aka.ms/InstallAzureCLIRpm | sudo bash; then
        info "Azure CLI installed successfully using RPM script."
    else
        # Fallback to distribution-specific if the universal script fails or user prefers
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS_ID=$ID
        else
            error_exit "Cannot determine Linux distribution to install Azure CLI. Please install it manually."
        fi

        if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
            info "Detected Debian-based system. Installing Azure CLI using apt..."
            sudo apt-get update -y
            sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg

            sudo mkdir -p /etc/apt/keyrings
            curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
                gpg --dearmor |
                sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
            sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

            AZ_REPO=$(lsb_release -cs)
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
                sudo tee /etc/apt/sources.list.d/azure-cli.list

            sudo apt-get update -y
            sudo apt-get install -y azure-cli
        elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "fedora" ]]; then
            info "Detected RPM-based system. Installing Azure CLI using dnf/yum..."
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            
            # For RHEL 9 / CentOS Stream 9+ or Fedora
            if command -v dnf &> /dev/null; then
                if [[ "$OS_ID" == "rhel" && "$(rpm -E %{rhel})" == "9" ]] || [[ "$OS_ID" == "centos" && "$(rpm -E %{centos_stream})" == "9" ]] || [[ "$OS_ID" == "fedora" ]]; then
                     sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
                elif [[ "$OS_ID" == "rhel" && "$(rpm -E %{rhel})" == "8" ]] || [[ "$OS_ID" == "centos" && "$(rpm -E %{centos_stream})" == "8" ]]; then
                     sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
                else # RHEL 7 / CentOS 7
                     echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
                fi
                sudo dnf install -y azure-cli || sudo yum install -y azure-cli # Fallback to yum if dnf fails or for older systems
            else # Fallback for very old systems without dnf
                 echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
                 sudo yum install -y azure-cli
            fi
        else
            error_exit "Unsupported Linux distribution ($OS_ID). Please install Azure CLI manually from: https://learn.microsoft.com/cli/azure/install-azure-cli-linux"
        fi
    fi

    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI installation failed. Please check the output and try manually."
    else
        info "Azure CLI installed successfully!"
        az --version
        info "You might need to restart your shell or run 'exec $SHELL' for the 'az' command to be available in the current session."
    fi
}

install_azure_cli
echo

# --- Step 2: Login to Azure ---
info "Step 2: Logging into Azure"
info "The Azure login process will open in your web browser. Follow the instructions to authenticate."
info "If you have multiple Azure subscriptions, you might be asked to choose one, or you can set it later using 'az account set --subscription YOUR_SUBSCRIPTION_ID'."

# Check if already logged in
if ! az account show &> /dev/null; then
    az login --use-device-code # Using device code for more robust CLI environment login
    info "Login successful."
else
    info "Already logged in to Azure as:"
    az account show -o table
fi
CURRENT_SUBSCRIPTION=$(az account show --query "name" -o tsv)
info "Current active subscription: $CURRENT_SUBSCRIPTION"
echo

# --- Step 3: Configure Default Azure Region ---
info "Step 3: Configure Azure Region"
info "Your specified location is Amsterdam, Europe. The corresponding Azure region is 'westeurope'."
DEFAULT_LOCATION="westeurope"
read -r -p "Enter Azure region to deploy resources (default: $DEFAULT_LOCATION): " LOCATION
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
info "Using Azure region: $LOCATION"

# You can list all available locations for your subscription with:
# az account list-locations -o table
echo

# --- Step 4: Create a Resource Group ---
info "Step 4: Create a Resource Group"
info "A Resource Group is a container that holds related resources for an Azure solution."
DEFAULT_RG_NAME="MyFreeTierLinuxRG-$(date +%s)" # Unique name to avoid collision
read -r -p "Enter a name for your Resource Group (default: $DEFAULT_RG_NAME): " RESOURCE_GROUP_NAME
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-$DEFAULT_RG_NAME}

info "Creating Resource Group '$RESOURCE_GROUP_NAME' in '$LOCATION'..."
if az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" -o table; then
    info "Resource Group '$RESOURCE_GROUP_NAME' created successfully."
else
    error_exit "Failed to create Resource Group '$RESOURCE_GROUP_NAME'. Check for existing group with the same name or other Azure errors."
fi
echo

# --- Step 5: Create a Free Tier Linux VM ---
info "Step 5: Create a Free Tier Linux Virtual Machine"
warning "We will attempt to create a VM using common free tier eligible parameters."
warning "Typically, 'Standard_B1s' size with an Ubuntu LTS image is free tier eligible for new accounts (750 hours/month for 12 months)."
warning "Ensure your account and chosen options meet the current Azure Free Tier criteria!"

DEFAULT_VM_NAME="MyFreeLinuxVM-$(date +%s)"
read -r -p "Enter a name for your VM (default: $DEFAULT_VM_NAME): " VM_NAME
VM_NAME=${VM_NAME:-$DEFAULT_VM_NAME}

DEFAULT_ADMIN_USER="azureuser" # Common default, you can change this
read -r -p "Enter an admin username for the VM (default: $DEFAULT_ADMIN_USER): " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-$DEFAULT_ADMIN_USER}

# Free Tier Eligible Parameters (common choices, verify with Azure documentation)
VM_SIZE="Standard_B1s"
# Using a specific Ubuntu 22.04 LTS Gen2 image URN for reliability.
# 'UbuntuLTS' often works but can sometimes point to Gen1 or other variants.
# Check available images with: az vm image list --offer UbuntuServer --publisher Canonical --sku 22_04-lts-gen2 --all -o table
# Or more generally: az vm image list --output table --all (this is a very long list)
VM_IMAGE_URN="Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
# For a minimal image, you could use: "Canonical:0001-com-ubuntu-minimal-jammy:minimal-22_04-lts-gen2:latest"

info "The following parameters will be used for VM creation:"
info "  VM Name: $VM_NAME"
info "  Resource Group: $RESOURCE_GROUP_NAME"
info "  Location: $LOCATION"
info "  Size: $VM_SIZE (Commonly Free Tier eligible)"
info "  Image: $VM_IMAGE_URN (Ubuntu Server 22.04 LTS Gen2)"
info "  Admin Username: $ADMIN_USERNAME"
info "  SSH Keys: Will be generated automatically if they don't exist (~/.ssh/id_rsa and ~/.ssh/id_rsa.pub)."
info "  Public IP SKU: Basic (often sufficient and potentially more cost-effective for free tier if not heavy use, though Standard is common in examples)"

read -r -p "Do you want to proceed with VM creation? (yes/no): " CONFIRM_VM_CREATE
if [[ "$CONFIRM_VM_CREATE" != "yes" ]]; then
    info "VM creation aborted by user."
    exit 0
fi

info "Creating VM '$VM_NAME'. This may take a few minutes..."
# Using --public-ip-sku Basic as it might be more aligned with "free" for simple access.
# Standard SKU for public IP has its own costs if not covered by a specific offer.
# However, many Azure docs now default to Standard. If Basic causes issues, switch to Standard.
if az vm create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$VM_NAME" \
    --image "$VM_IMAGE_URN" \
    --size "$VM_SIZE" \
    --location "$LOCATION" \
    --admin-username "$ADMIN_USERNAME" \
    --generate-ssh-keys \
    --public-ip-sku "Basic" \
    --os-disk-size-gb 30 \
    # Ensuring a small OS disk (P6 is 64GB, often a 30GB OS disk is created for B1s which is fine)
    # Free tier usually includes certain amounts of Standard SSD Managed Disks (e.g., 2xP6 disks - 64 GiB each)
    # The default OS disk for B1s is usually a Premium SSD (e.g., P4 or P6) or Standard SSD depending on region/defaults.
    # Explicitly setting a smaller size like 30GB for the OS disk can help stay within limits if defaults are larger.
    # The command will create a default network security group (NSG) allowing SSH on port 22.
    -o table; then
    info "VM '$VM_NAME' created successfully!"
else
    error_exit "Failed to create VM '$VM_NAME'. Review the error messages from Azure."
fi
echo

# --- Step 6: Get VM Public IP and Connect via SSH ---
info "Step 6: Connect to your VM"
info "Retrieving Public IP address for '$VM_NAME'..."

VM_PUBLIC_IP=$(az vm show \
    --show-details \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$VM_NAME" \
    --query "publicIps" \
    -o tsv)

if [[ -z "$VM_PUBLIC_IP" ]]; then
    error_exit "Could not retrieve the Public IP address for '$VM_NAME'. The VM might not have a public IP or there was an issue."
fi

info "VM '$VM_NAME' Public IP Address: $VM_PUBLIC_IP"
info "Your SSH private key should be in ~/.ssh/id_rsa (or the one you specified if you didn't use --generate-ssh-keys)."
info "To connect to your VM, use the following command:"
info "  ssh $ADMIN_USERNAME@$VM_PUBLIC_IP"
echo
info "You can now try connecting to your VM in a new terminal window."
info "Example: ssh $ADMIN_USERNAME@$VM_PUBLIC_IP"
echo

# --- Step 7: Next Steps and Cleanup Reminder ---
info "Step 7: Important Next Steps & Cleanup"
warning "MANAGE YOUR RESOURCES: Remember that while this VM aims for the free tier, usage beyond free limits WILL incur costs."
warning "  - Stop your VM when not in use: 'az vm stop --resource-group $RESOURCE_GROUP_NAME --name $VM_NAME'"
warning "  - Start your VM: 'az vm start --resource-group $RESOURCE_GROUP_NAME --name $VM_NAME'"
warning "  - Deallocate (stops billing for compute, but storage costs remain): 'az vm deallocate --resource-group $RESOURCE_GROUP_NAME --name $VM_NAME'"
warning "TO AVOID ALL CHARGES associated with these resources, delete the Resource Group when you're done:"
warning "  'az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait'"
warning "  (The '--no-wait' flag runs it in the background. Remove it to see the deletion progress.)"
warning "  Deleting the resource group will delete the VM, its disks, network interface, public IP, etc."
echo
info "Script finished. Happy Hacking on Azure!"
