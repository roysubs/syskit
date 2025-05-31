#!/bin/bash
# Author: Roy Wiseman 2025-03

# kvm-get.sh: Idempotent script to install and configure KVM.
# This script will install necessary packages and guide through
# setting up KVM for both local and remote headless server usage.

# --- Configuration ---
# Set to true to attempt to automatically configure a default bridge
# named 'br0' using netplan if a primary interface is found.
# Set to false to skip automatic bridge creation.
CONFIGURE_BRIDGE_AUTOMATICALLY=true
# Set a default user to add to libvirt groups.
# Leave empty to prompt, or set to a specific username.
DEFAULT_USER=""

# --- Helper Functions ---
ech_cmd() {
    echo "⚙️  Running: $@"
    "$@"
    echo "---"
}

ech_info() {
    echo "ℹ️  $@"
    echo "---"
}

ech_warn() {
    echo "⚠️  $@"
    echo "---"
}

ech_success() {
    echo "✅ $@"
    echo "---"
}

# --- Script Start ---
ech_info "Starting KVM Setup Script"
set -e # Exit immediately if a command exits with a non-zero status.

# 1. Check for Root/Sudo Privileges
if [ "$(id -u)" -ne 0 ]; then
    ech_warn "This script needs to be run with sudo or as root."
    # Attempt to re-run with sudo
    if command -v sudo >/dev/null 2>&1; then
        ech_info "Attempting to re-run with sudo..."
        sudo "$0" "$@"
        exit $?
    else
        ech_warn "sudo not found. Please run this script as root."
        exit 1
    fi
fi

# --- System Checks ---

# 2. Check for Virtualization Support
ech_info "Checking for CPU virtualization support..."
if ! egrep -c '(vmx|svm)' /proc/cpuinfo > /dev/null; then
    ech_warn "CPU virtualization support (VT-x or AMD-V) is NOT enabled in your BIOS/UEFI."
    ech_warn "Please enable it in your BIOS/UEFI settings to use KVM."
    exit 1
else
    ech_success "CPU virtualization support is enabled."
fi

if ! kvm-ok > /dev/null 2>&1; then
    ech_info "kvm-ok utility not found, installing cpu-checker..."
    ech_cmd apt update
    ech_cmd apt install -y cpu-checker
    if ! kvm-ok; then
        ech_warn "KVM acceleration can NOT be used. Please check 'kvm-ok' output for details."
        exit 1
    fi
else
    if ! kvm-ok; then
        ech_warn "KVM acceleration can NOT be used. Please check 'kvm-ok' output for details."
        exit 1
    fi
fi
ech_success "KVM acceleration can be used."

# --- Package Installation ---
ech_info "Installing KVM and related packages..."
# qemu-kvm: The KVM hypervisor
# libvirt-daemon-system: The libvirt daemon providing the management API
# libvirt-clients: Command-line tools to manage VMs (virsh)
# bridge-utils: Utilities for configuring network bridges
# virtinst: Tools to create VMs (e.g., virt-install)
# virt-manager: GUI for managing VMs (optional, but useful for local GUI)
# spice-vdagent: For better integration if using SPICE for remote console (install in guest)
# qemu-system-x86: The QEMU emulator for x86 architecture

PACKAGES_TO_INSTALL="qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager"

for pkg in $PACKAGES_TO_INSTALL; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        ech_cmd apt update # Run update once before installing
        break
    fi
done

for pkg in $PACKAGES_TO_INSTALL; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        ech_info "Installing $pkg..."
        ech_cmd apt install -y "$pkg"
    else
        ech_info "$pkg is already installed."
    fi
done
ech_success "KVM packages installed."

# --- User and Group Management ---
ech_info "Configuring user for KVM management..."

CURRENT_USER=${SUDO_USER:-$(whoami)}
TARGET_USER=""

if [ -n "$DEFAULT_USER" ]; then
    TARGET_USER="$DEFAULT_USER"
    ech_info "Using pre-configured user: $TARGET_USER"
elif [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
    read -r -p "Do you want to add the current user '$CURRENT_USER' to the 'libvirt' and 'kvm' groups? (Y/n): " ADD_CURRENT_USER_CHOICE
    ADD_CURRENT_USER_CHOICE=${ADD_CURRENT_USER_CHOICE:-Y}
    if [[ "$ADD_CURRENT_USER_CHOICE" =~ ^[Yy]$ ]]; then
        TARGET_USER="$CURRENT_USER"
    fi
fi

if [ -z "$TARGET_USER" ]; then
    read -r -p "Enter the username to add to 'libvirt' and 'kvm' groups (e.g., your regular user): " INPUT_USER
    if id "$INPUT_USER" &>/dev/null; then
        TARGET_USER="$INPUT_USER"
    else
        ech_warn "User '$INPUT_USER' not found. Skipping user group addition."
    fi
fi

if [ -n "$TARGET_USER" ]; then
    if ! groups "$TARGET_USER" | grep -q '\blibvirt\b'; then
        ech_cmd usermod -aG libvirt "$TARGET_USER"
        ech_success "Added user '$TARGET_USER' to the 'libvirt' group."
    else
        ech_info "User '$TARGET_USER' is already in the 'libvirt' group."
    fi

    if ! groups "$TARGET_USER" | grep -q '\blkvm\b'; then
        # The 'kvm' group might not exist on all systems or be strictly necessary
        # if libvirt is configured correctly with udev rules.
        # However, adding it can prevent some permission issues.
        if getent group kvm > /dev/null; then
            ech_cmd usermod -aG kvm "$TARGET_USER"
            ech_success "Added user '$TARGET_USER' to the 'kvm' group."
        else
            ech_info "Group 'kvm' does not exist. Skipping addition for user '$TARGET_USER'."
        fi
    else
        ech_info "User '$TARGET_USER' is already in the 'kvm' group."
    fi
    ech_warn "User '$TARGET_USER' may need to log out and log back in for group changes to take effect."
fi


# --- Service Management ---
ech_info "Ensuring libvirtd service is running and enabled..."
if ! systemctl is-active --quiet libvirtd; then
    ech_cmd systemctl start libvirtd
    ech_success "Started libvirtd service."
else
    ech_info "libvirtd service is already active."
fi

if ! systemctl is-enabled --quiet libvirtd; then
    ech_cmd systemctl enable libvirtd
    ech_success "Enabled libvirtd service to start on boot."
else
    ech_info "libvirtd service is already enabled."
fi

# --- Networking Setup (Optional: Basic Bridge) ---
# This section attempts to set up a basic bridge for VMs to connect to the host network.
# It's a common setup but might need adjustment based on your specific network configuration.

# Check if netplan is used (common on modern Ubuntu)
if command -v netplan >/dev/null 2>&1 && [ "$CONFIGURE_BRIDGE_AUTOMATICALLY" = true ]; then
    ech_info "Attempting to configure a network bridge 'br0' using netplan."
    ech_warn "This is an automated attempt and might require manual adjustment."
    ech_warn "Backup your netplan configuration in /etc/netplan before proceeding if unsure."

    # Find the primary network interface (heuristic)
    PRIMARY_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n1)

    if [ -z "$PRIMARY_IFACE" ]; then
        ech_warn "Could not automatically determine the primary network interface. Skipping bridge creation."
    elif ip link show br0 > /dev/null 2>&1; then
        ech_info "Network bridge 'br0' already exists. Skipping creation."
    else
        ech_info "Primary network interface detected: $PRIMARY_IFACE"
        read -r -p "Do you want to attempt to create a bridge 'br0' using this interface with netplan? (Y/n): " CREATE_BRIDGE_CHOICE
        CREATE_BRIDGE_CHOICE=${CREATE_BRIDGE_CHOICE:-Y}

        if [[ "$CREATE_BRIDGE_CHOICE" =~ ^[Yy]$ ]]; then
            NETPLAN_FILE="/etc/netplan/01-netcfg.yaml" # Common default, might vary
            if [ ! -f "$NETPLAN_FILE" ]; then
                # Try to find any yaml file in netplan dir
                NETPLAN_FILE_CANDIDATE=$(find /etc/netplan -name "*.yaml" -print -quit)
                if [ -n "$NETPLAN_FILE_CANDIDATE" ]; then
                    NETPLAN_FILE="$NETPLAN_FILE_CANDIDATE"
                else
                    ech_warn "No netplan configuration file found. Cannot create bridge automatically."
                    # Create a very basic one if none exists
                    ech_info "Creating a new netplan configuration file for the bridge: /etc/netplan/99-kvm-bridge.yaml"
                    NETPLAN_FILE="/etc/netplan/99-kvm-bridge.yaml"
                    cat <<EOF > "$NETPLAN_FILE"
network:
  version: 2
  renderer: networkd
EOF
                fi
            fi

            ech_info "Backing up current netplan config to ${NETPLAN_FILE}.bak..."
            cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak"

            # This is a very basic bridge config. It assumes DHCP for the bridge.
            # You might need to adjust IP addresses, DHCP settings, etc.
            # This approach moves the IP configuration from the physical interface to the bridge.
            # WARNING: This can disconnect you if you are on SSH and something goes wrong.
            # Ensure you have console access if modifying a remote server's primary interface.

            ech_info "Generating new netplan configuration for bridge 'br0' using interface '$PRIMARY_IFACE'."
            # Attempt to preserve existing configuration for the interface and move it to the bridge
            # This is a simplified approach. Complex netplan files might need manual editing.

            # Remove existing config for the primary interface if it exists in the file
            # and add the new bridge configuration. This is tricky to do robustly with sed/awk
            # for all netplan structures. For simplicity, we'll make a new config or append.
            # A safer approach for complex systems is manual configuration.

            # Let's create a dedicated config file for the bridge to avoid messing up complex existing files.
            BRIDGE_NETPLAN_FILE="/etc/netplan/99-kvm-bridge.yaml"
            ech_info "Creating/Updating netplan configuration for bridge at $BRIDGE_NETPLAN_FILE"
            cat <<EOF > "$BRIDGE_NETPLAN_FILE"
network:
  version: 2
  renderer: networkd
  ethernets:
    $PRIMARY_IFACE:
      dhcp4: no
      dhcp6: no
      # Optional: if you have specific link settings like speed/duplex, add them here.
  bridges:
    br0:
      interfaces: [$PRIMARY_IFACE]
      dhcp4: yes # Or configure static IP below
      # parameters:
      #  stp: true
      #  forward-delay: 4
      # addresses: [192.168.1.10/24] # Example static IP
      # gateway4: 192.168.1.1      # Example gateway
      # nameservers:
      #   addresses: [8.8.8.8, 8.8.4.4]
EOF
            ech_warn "Generated netplan config for br0. Review $BRIDGE_NETPLAN_FILE and apply with 'sudo netplan apply'."
            ech_warn "Applying netplan changes can disconnect your SSH session if the configuration is incorrect."
            read -r -p "Do you want to try 'sudo netplan apply' now? (y/N): " APPLY_NETPLAN_CHOICE
            APPLY_NETPLAN_CHOICE=${APPLY_NETPLAN_CHOICE:-N}
            if [[ "$APPLY_NETPLAN_CHOICE" =~ ^[Yy]$ ]]; then
                ech_cmd netplan apply
                ech_success "Netplan configuration applied. Check your network connectivity."
                ech_info "If 'br0' is up and has an IP, VMs can use it."
                ech_cmd ip addr show br0
            else
                ech_info "Skipped 'netplan apply'. Please review $BRIDGE_NETPLAN_FILE and apply manually."
            fi
        fi
    fi
elif [ "$CONFIGURE_BRIDGE_AUTOMATICALLY" = true ]; then
    ech_info "Netplan not detected. Skipping automatic bridge creation."
    ech_info "You may need to configure a network bridge manually (e.g., using /etc/network/interfaces or nmcli)."
fi

# --- Default Network ---
# Ensure the default libvirt network is active if no bridge was configured or if preferred.
if ! virsh net-list --all | grep -q ' default '; then
    ech_info "Libvirt 'default' network not found. Attempting to define and start it."
    # Create a temporary XML file for the default network
    DEFAULT_NET_XML=$(mktemp /tmp/default_network.XXXXXX.xml)
    cat > "$DEFAULT_NET_XML" <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:$(hexdump -n3 -e'/1 ":%02x"' /dev/urandom)'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
    ech_cmd virsh net-define "$DEFAULT_NET_XML"
    rm "$DEFAULT_NET_XML"
    ech_success "Defined libvirt 'default' network."
fi

if ! virsh net-list | grep -q ' default '; then
    ech_cmd virsh net-start default
    ech_success "Started libvirt 'default' NAT network."
else
    ech_info "Libvirt 'default' network is already active."
fi

if ! virsh net-list --autostart | grep -q ' default '; then
    ech_cmd virsh net-autostart default
    ech_success "Enabled autostart for libvirt 'default' network."
else
    ech_info "Autostart for libvirt 'default' network is already enabled."
fi


# --- Firewall Configuration (Basic for SSH and VNC/SPICE) ---
ech_info "Checking firewall configuration (ufw)..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ech_info "UFW is active. Adding rules for SSH, VNC and SPICE (if not present)."
    # SSH is essential for headless server management
    if ! ufw status verbose | grep -qw "22/tcp"; then
        ech_cmd ufw allow ssh
        ech_success "Allowed SSH through UFW."
    else
        ech_info "UFW rule for SSH already exists."
    fi

    # VNC typically uses ports 5900-59xx
    # SPICE typically uses ports 5900-59xx and 5800-58xx (check virt-manager for actual ports)
    # We'll add a common range. Be more specific if needed.
    if ! ufw status verbose | grep -qw "5900:5999/tcp"; then
        ech_cmd ufw allow 5900:5999/tcp # For VNC/SPICE
        ech_success "Allowed TCP ports 5900-5999 for VNC/SPICE through UFW."
    else
        ech_info "UFW rule for TCP ports 5900-5999 already exists."
    fi

    # For libvirt default NAT network (virbr0 - 192.168.122.0/24)
    # This is usually handled internally by libvirt's rules in iptables.
    # However, if UFW's default FORWARD policy is DROP, you might need this.
    # Check current forward policy
    if grep -q "DEFAULT_FORWARD_POLICY=\"DROP\"" /etc/default/ufw; then
        if ! ufw status verbose | grep -q "ALLOW IN ON virbr0"; then
            ech_info "UFW default forward policy is DROP. Adding rules for virbr0."
            ech_cmd ufw route allow in on virbr0
            ech_cmd ufw route allow out on virbr0
            # More specific rules might be needed depending on the setup
            # e.g., ufw route allow in on virbr0 out on $PRIMARY_IFACE from 192.168.122.0/24
            ech_success "Added basic routing rules for virbr0 in UFW."
        else
            ech_info "UFW routing rules for virbr0 seem to exist."
        fi
    fi
    ech_cmd ufw reload # Reload to apply changes if any were made
else
    ech_info "UFW is not active or not installed. Skipping UFW configuration."
    ech_info "Ensure your firewall (if any) allows SSH (port 22) and VNC/SPICE ports (e.g., 5900-5999 TCP) for remote access."
fi


# --- Final Checks and Information ---
ech_success "KVM setup script finished!"
ech_info "To use KVM without sudo, your user ($TARGET_USER if set, otherwise your current user) has been added to relevant groups."
ech_info "You might need to LOG OUT and LOG BACK IN for these group changes to take full effect."
if [ "$CONFIGURE_BRIDGE_AUTOMATICALLY" = true ] && [ -n "$PRIMARY_IFACE" ] && [[ "$CREATE_BRIDGE_CHOICE" =~ ^[Yy]$ ]]; then
    ech_info "A network bridge 'br0' may have been configured. VMs using this bridge will be on your LAN."
    ech_info "If you opted out of 'netplan apply', please do it manually: sudo netplan apply"
else
    ech_info "The libvirt 'default' NAT network (virbr0) is active. VMs will be on 192.168.122.0/24 by default."
fi

echo
ech_info "===== KVM Usage Examples ====="
echo
echo "Common virsh commands (run as user in libvirt group or with sudo):"
echo "  virsh list --all              # List all defined VMs (running or not)"
echo "  virsh list                    # List running VMs"
echo "  virsh start <vm_name>         # Start a VM"
echo "  virsh shutdown <vm_name>      # Gracefully shut down a VM"
echo "  virsh destroy <vm_name>       # Forcefully stop a VM (like pulling the plug)"
echo "  virsh undefine <vm_name>      # Delete a VM definition (does not delete disk image)"
echo "  virsh undefine <vm_name> --remove-all-storage # Delete VM and its associated storage"
echo "  virsh console <vm_name>       # Connect to serial console (if guest OS configured for it)"
echo "  virsh dominfo <vm_name>       # Show VM information"
echo "  virsh net-list                # List virtual networks"
echo "  virsh pool-list               # List storage pools"
echo
echo "Creating a new VM (example using virt-install for a cloud image):"
echo "  # Download a cloud image (e.g., Ubuntu Cloud Image)"
echo "  # wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
echo "  # Create a disk from the cloud image (qcow2 format is recommended)"
echo "  # qemu-img create -f qcow2 -b noble-server-cloudimg-amd64.img my-vm-disk.qcow2 20G"
echo "  # Create a cloud-init NoCloud ISO for initial setup (user data, network config)"
echo "  # See: https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html"
echo "  # Example user-data file (user-data.yaml):"
echo "  # #cloud-config"
echo "  # users:"
echo "  #   - name: youruser"
echo "  #     sudo: ALL=(ALL) NOPASSWD:ALL"
echo "  #     groups: users, admin"
echo "  #     home: /home/youruser"
echo "  #     shell: /bin/bash"
echo "  #     ssh_authorized_keys:"
echo "  #       - ssh-rsa AAAA..."
echo "  # password: yourpassword"
echo "  # chpasswd: { expire: False }"
echo "  # hostname: my-kvm-vm"
echo "  # runcmd:"
echo "  #   - [ apt, update ]"
echo "  #   - [ apt, install, -y, qemu-guest-agent ] # Useful for host interaction"
echo
echo "  # Create meta-data file (meta-data.yaml - can often be empty or just 'instance-id: ...'):"
echo "  # instance-id: id-myvm-$(uuidgen | cut -d- -f1)"
echo
echo "  # Generate the cloud-init ISO:"
echo "  # genisoimage -output my-cloud-init.iso -volid cidata -joliet -rock user-data.yaml meta-data.yaml"
echo
echo "  # virt-install \\"
echo "  #   --name my-test-vm \\"
echo "  #   --ram 2048 \\"
echo "  #   --vcpus 2 \\"
echo "  #   --disk path=/path/to/my-vm-disk.qcow2,format=qcow2 \\"
echo "  #   --disk path=/path/to/my-cloud-init.iso,device=cdrom \\"
echo "  #   --osinfo detect=on,name=ubuntu22.04 \\"
echo "  #   --network network=default \\" # Or --network bridge=br0 if you configured a bridge
echo "  #   --graphics none \\"           # For headless server, serial console access
echo "  #   --console pty,target_type=serial \\"
echo "  #   --import"
echo "  # After install, eject cdrom: virsh change-media my-test-vm sda --eject --config (replace sda with actual cdrom device)"
echo
echo "Connecting to VMs:"
echo "  Local GUI (if VM has a graphical environment and you installed virt-manager on the host):"
echo "    virt-manager                # Launch the Virtual Machine Manager GUI"
echo "    virt-viewer <vm_name>       # Connect directly to a VM's graphical console (SPICE or VNC)"
echo
echo "  Local X Forwarding (for GUI apps inside the VM, if X11 is running on host and sshd_config on VM allows X11Forwarding):"
echo "    ssh -X user@vm_ip_address   # Then run GUI app: e.g., 'xeyes'"
echo
echo "  Remote Access (Headless Server - assuming VM has an IP address reachable from remote system):"
echo "    1. SSH: Standard method for terminal access."
echo "       - Ensure ssh server is running in the VM."
echo "       - Connect from Windows (using PowerShell, WSL, PuTTY, MobaXterm, etc.):"
echo "         ssh user@vm_ip_address_or_hostname"
echo "       - If using the default NAT network (192.168.122.x):"
echo "         - You can SSH from the KVM host directly."
echo "         - For external access, you'd need to set up port forwarding on the KVM host:"
echo "           sudo iptables -t nat -A PREROUTING -p tcp --dport <host_port> -j DNAT --to-destination <vm_ip>:<vm_ssh_port>"
echo "           sudo iptables -I FORWARD -m state -d 192.168.122.0/24 --state NEW,RELATED,ESTABLISHED -j ACCEPT"
echo "           Consider using 'ufw route' if UFW is managing iptables."
echo "         - Or use a bridged network (br0) so the VM gets an IP on your LAN."
echo
echo "    2. VNC/SPICE for Graphical Console (if VM configured for it):"
echo "       - When creating VM with virt-install, use '--graphics vnc,listen=0.0.0.0' or '--graphics spice,listen=0.0.0.0'."
echo "         (Be cautious with listen=0.0.0.0 on public networks, consider listen=localhost and SSH port forwarding)."
echo "       - Find the VNC/SPICE port: virsh vncdisplay <vm_name> or virsh domdisplay <vm_name>"
echo "       - From Windows, use a VNC client (TightVNC, RealVNC, UltraVNC) or SPICE client (virt-viewer for Windows)."
echo "       - To connect securely: SSH port forward the VNC/SPICE port:"
echo "         ssh -L <local_port>:<kvm_host_ip_or_localhost>:<vm_vnc_spice_port> user@kvm_host_ip"
echo "         Then connect your VNC/SPICE client to localhost:<local_port> on your Windows machine."
echo
echo "    3. RDP (Remote Desktop Protocol - if VM is Windows or Linux with XRDP):"
echo "       - Install RDP server in the VM (e.g., xrdp on Linux)."
echo "       - Connect from Windows using Remote Desktop Connection to vm_ip_address."
echo "       - Similar networking considerations as SSH (bridged or port forwarding for NAT)."
echo
echo "Finding VM IP address (for default NAT network):"
echo "  virsh net-dhcp-leases default   # Shows DHCP leases for the 'default' network"
echo "  # Or login to VM console and use 'ip a'"
echo
ech_info "Script execution complete. Review output for any warnings or manual steps."
set +e # Revert to default error handling
