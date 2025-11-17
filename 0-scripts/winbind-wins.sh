#!/bin/bash

# --- winbind-wins.sh ---
# Description: Installs Samba/Winbind and configures Name Service Switch (NSS)
# to enable Linux to resolve Windows hostnames using WINS/NetBIOS broadcasts.

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Configuration Variables ---
NSS_CONFIG="/etc/nsswitch.conf"
SMB_CONFIG="/etc/samba/smb.conf"
HOST_TO_TEST="Yor"
# The actual IP address of the Windows host, used for explicit comparison
HOST_CORRECT_IP="192.168.1.29"
WORKGROUP_NAME="" # Will be set by get_workgroup function

# Function to print section headers
print_header() {
    echo -e "\n${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}================================================================${NC}"
}

# Function to print sub-headers
print_subheader() {
    echo -e "\n${MAGENTA}${BOLD}--- $1 ---${NC}"
}

# Function to show command before running it
run_command() {
    local description="$1"
    shift
    echo -e "${YELLOW}${description}${NC}"
    echo -e "${GREEN}→ $*${NC}"
    "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}✗ Command failed with exit code $exit_code${NC}"
        return $exit_code
    fi
    return 0
}

# Function to auto-elevate script execution if not running as root
auto_elevate() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Root privileges required. Re-executing script with sudo...${NC}"
        # Preserve environment variables (-E) and pass all arguments ("$@")
        # Exit the current process and replace it with the sudo command
        exec sudo -E bash "$0" "$@"
    fi
}

# Function to display introduction and prompt for continuation
script_intro() {
    print_header "Winbind WINS Hostname Resolution Setup"
    echo "This script will automatically configure your Linux system to resolve"
    echo "Windows hostnames (NetBIOS names) like '$HOST_TO_TEST' without needing DNS."
    echo ""
    echo "Actions to be performed (requires root/sudo):"
    echo "1. Check and install Samba, Winbind, and NSS libraries (if missing)."
    echo "2. Prompt for your Windows Workgroup/Domain Name."
    echo "3. Modify /etc/nsswitch.conf to prioritize NetBIOS (wins) resolution."
    echo "4. Modify /etc/samba/smb.conf to enable WINS name resolution."
    echo "5. Restart necessary services (smbd, nmbd, winbind, and NSS cache)."
    echo "6. Test resolution for the host '$HOST_TO_TEST'."
    echo "----------------------------------------------------------------"

    read -r -p "Do you want to continue with the setup? [y/N]: " confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Setup aborted by user.${NC}"
        exit 0
    fi
}

# Function to check if packages are installed
check_packages() {
    print_subheader "Checking Required Packages"
    
    local missing_packages=()
    local packages_to_check
    
    if command -v dpkg &> /dev/null; then
        packages_to_check="samba winbind libnss-winbind"
        for pkg in $packages_to_check; do
            if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                missing_packages+=("$pkg")
            else
                echo -e "${GREEN}✓${NC} $pkg is already installed"
            fi
        done
    elif command -v rpm &> /dev/null; then
        packages_to_check="samba samba-winbind-clients"
        for pkg in $packages_to_check; do
            if ! rpm -q "$pkg" &>/dev/null; then
                missing_packages+=("$pkg")
            else
                echo -e "${GREEN}✓${NC} $pkg is already installed"
            fi
        done
    else
        echo -e "${RED}Error: Cannot determine package manager${NC}"
        exit 1
    fi
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        echo -e "${GREEN}All required packages are already installed. Skipping installation.${NC}"
        return 0
    else
        echo -e "${YELLOW}Missing packages: ${missing_packages[*]}${NC}"
        return 1
    fi
}

# Function to detect package manager and install packages
install_packages() {
    if check_packages; then
        return 0
    fi
    
    print_subheader "Installing Missing Packages"
    
    local PACKAGE_MANAGER
    local PACKAGES
    
    if command -v apt &> /dev/null; then
        PACKAGE_MANAGER="apt"
        PACKAGES="samba winbind libnss-winbind"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        PACKAGES="samba samba-winbind-clients"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
        PACKAGES="samba samba-winbind-clients"
    else
        echo -e "${RED}Error: Unsupported package manager. Please install samba and winbind manually.${NC}"
        exit 1
    fi
    
    run_command "Installing packages" $PACKAGE_MANAGER install -y $PACKAGES
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to install packages. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Packages installed successfully.${NC}"
}

# Function to get user input for the Workgroup
get_workgroup() {
    print_subheader "Workgroup Configuration"
    # Default is typically "WORKGROUP"
    read -r -p "Enter your Windows Workgroup/Domain Name (e.g., WORKGROUP): " WORKGROUP_NAME
    if [ -z "$WORKGROUP_NAME" ]; then
        WORKGROUP_NAME="WORKGROUP"
        echo -e "${YELLOW}Using default Workgroup: $WORKGROUP_NAME${NC}"
    else
        echo -e "${GREEN}Using Workgroup: $WORKGROUP_NAME${NC}"
    fi
}

# Function to modify /etc/nsswitch.conf
configure_nsswitch() {
    print_subheader "Configuring $NSS_CONFIG"
    
    # First, backup the original file if not already backed up
    if [ ! -f "${NSS_CONFIG}.backup" ]; then
        run_command "Creating backup" cp "$NSS_CONFIG" "${NSS_CONFIG}.backup"
    fi
    
    # Check current hosts line
    echo -e "${YELLOW}Current hosts line:${NC}"
    grep "^hosts:" "$NSS_CONFIG"
    
    # Check if 'wins' is already present and correctly positioned BEFORE dns
    if grep "^hosts:.*wins.*dns" "$NSS_CONFIG" | grep -q "wins"; then
        echo -e "${GREEN}✓ 'wins' already found and correctly positioned before DNS in $NSS_CONFIG.${NC}"
        
        # But verify it's in the right spot (before mdns and dns, after mymachines)
        if ! grep "^hosts:.*mymachines wins.*dns" "$NSS_CONFIG" &>/dev/null; then
            echo -e "${YELLOW}⚠ 'wins' exists but may not be optimally positioned. Reconfiguring...${NC}"
            # Remove existing wins entries first
            sudo sed -i '/^hosts:/ s/wins //g' "$NSS_CONFIG"
            # Then add it in the correct position
            sudo sed -i '/^hosts:/ s/mymachines /mymachines wins /' "$NSS_CONFIG"
            echo -e "${GREEN}✓ Repositioned 'wins' for optimal resolution order${NC}"
        fi
    else
        echo -e "${YELLOW}Adding 'wins' to the hosts resolution order (before mdns and dns)${NC}"
        # First remove any existing 'wins' entries
        sudo sed -i '/^hosts:/ s/wins //g' "$NSS_CONFIG"
        # Then add it in the correct position after mymachines
        sudo sed -i '/^hosts:/ s/mymachines /mymachines wins /' "$NSS_CONFIG"
        echo -e "${GREEN}✓ Update applied${NC}"
    fi
    
    echo -e "${YELLOW}New hosts line:${NC}"
    grep "^hosts:" "$NSS_CONFIG"
}

# Function to modify /etc/samba/smb.conf
configure_samba() {
    print_subheader "Configuring $SMB_CONFIG"
    
    # First, backup the original file if not already backed up
    if [ ! -f "${SMB_CONFIG}.backup" ]; then
        run_command "Creating backup" cp "$SMB_CONFIG" "${SMB_CONFIG}.backup"
    fi
    
    # 1. Update/Add workgroup
    if grep -q "^[[:space:]]*workgroup[[:space:]]*=" "$SMB_CONFIG"; then
        run_command "Updating workgroup setting" sudo sed -i "s/^[[:space:]]*workgroup[[:space:]]*=.*/\tworkgroup = $WORKGROUP_NAME/" "$SMB_CONFIG"
    else
        # Add to global section if not found
        run_command "Adding workgroup setting" sudo sed -i "/\[global\]/a\        workgroup = $WORKGROUP_NAME" "$SMB_CONFIG"
    fi

    # 2. Add/Update name resolve order to prioritize WINS and broadcast
    if grep -q "^[[:space:]]*name resolve order[[:space:]]*=" "$SMB_CONFIG"; then
        run_command "Updating name resolve order" sudo sed -i "s/^[[:space:]]*name resolve order[[:space:]]*=.*/\tname resolve order = wins bcast host lmhosts/" "$SMB_CONFIG"
    else
        # Add to global section if not found
        run_command "Adding name resolve order" sudo sed -i "/\[global\]/a\        name resolve order = wins bcast host lmhosts" "$SMB_CONFIG"
    fi

    # 3. Enable WINS support (helps as a local WINS server for NetBIOS)
    if ! grep -q "^[[:space:]]*wins support[[:space:]]*=" "$SMB_CONFIG"; then
        run_command "Enabling WINS support" sudo sed -i "/\[global\]/a\        wins support = yes" "$SMB_CONFIG"
    fi
    
    # 4. Network interface configuration (prevents nmbd from hanging)
    echo -e "${YELLOW}Configuring network interfaces to prevent service hangs...${NC}"
    
    # Get actual network interfaces
    local actual_interfaces
    actual_interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -3 | tr '\n' ' ')
    
    if [ -n "$actual_interfaces" ]; then
        echo -e "${YELLOW}Detected interfaces: lo $actual_interfaces${NC}"
        
        # Remove old interface settings if they exist
        sudo sed -i '/^[[:space:]]*interfaces[[:space:]]*=/d' "$SMB_CONFIG"
        sudo sed -i '/^[[:space:]]*bind interfaces only[[:space:]]*=/d' "$SMB_CONFIG"
        
        # Add new settings with actual interfaces
        sudo sed -i "/\[global\]/a\        interfaces = lo $actual_interfaces" "$SMB_CONFIG"
        sudo sed -i "/\[global\]/a\        bind interfaces only = yes" "$SMB_CONFIG"
        
        echo -e "${GREEN}✓ Network interfaces configured${NC}"
    fi
    
    # 5. Disable IPv6 in Samba (common cause of hangs)
    if ! grep -q "^[[:space:]]*disable netbios[[:space:]]*=" "$SMB_CONFIG"; then
        sudo sed -i "/\[global\]/a\        disable netbios = no" "$SMB_CONFIG"
    fi
    
    echo -e "${GREEN}✓ Samba configuration updated${NC}"
}

# Function to restart a service with timeout
restart_service_with_timeout() {
    local service_name="$1"
    local timeout=10
    
    echo -e "${YELLOW}Restarting $service_name (timeout: ${timeout}s)${NC}"
    echo -e "${GREEN}→ sudo systemctl restart $service_name${NC}"
    
    # First, try to stop the service
    sudo systemctl stop "$service_name" &>/dev/null || true
    sleep 1
    
    # Kill any hanging processes
    sudo pkill -9 "$service_name" &>/dev/null || true
    sleep 1
    
    # Start with timeout
    timeout "$timeout" sudo systemctl start "$service_name" 2>/dev/null
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo -e "${RED}✗ Timeout: $service_name took too long to start${NC}"
        echo -e "${YELLOW}⚠ Forcing service to stop and trying again...${NC}"
        sudo systemctl kill "$service_name" &>/dev/null || true
        sleep 2
        sudo systemctl start "$service_name" &>/dev/null || true
    elif [ $exit_code -ne 0 ]; then
        echo -e "${YELLOW}⚠ Warning: Could not restart $service_name (exit code: $exit_code)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $service_name restarted successfully${NC}"
    fi
    
    return 0
}

# Function to restart services and test
restart_services() {
    print_subheader "Restarting Services and Clearing Caches"
    
    # Stop all services first to avoid conflicts
    echo -e "${YELLOW}Stopping all Samba services first...${NC}"
    sudo systemctl stop smbd nmbd winbind 2>/dev/null || true
    sleep 2
    
    # Force kill any hanging processes
    sudo pkill -9 smbd &>/dev/null || true
    sudo pkill -9 nmbd &>/dev/null || true
    sudo pkill -9 winbindd &>/dev/null || true
    sleep 1
    
    # Restart core services with timeout protection
    restart_service_with_timeout "smbd"
    restart_service_with_timeout "nmbd"
    restart_service_with_timeout "winbind"
    
    # Check service status
    echo ""
    echo -e "${YELLOW}Checking service status...${NC}"
    for service in smbd nmbd winbind; do
        if sudo systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓${NC} $service is running"
        else
            echo -e "${RED}✗${NC} $service is NOT running (this may cause issues)"
        fi
    done
    
    # If nmbd fails, it might not be critical for WINS client functionality
    if ! sudo systemctl is-active --quiet nmbd; then
        echo ""
        echo -e "${YELLOW}${BOLD}NOTE:${NC} ${YELLOW}nmbd failed to start. This is the NetBIOS Name Server daemon.${NC}"
        echo -e "${YELLOW}For WINS client functionality, this may not be critical.${NC}"
        echo -e "${YELLOW}The system can still resolve names via winbind and WINS queries.${NC}"
    fi

    # --- AGGRESSIVE CACHE FLUSH LOGIC ---
    echo ""
    echo -e "${YELLOW}Flushing all DNS/NSS caches...${NC}"
    
    # 1. Clear systemd-resolved cache (most modern systems)
    if command -v resolvectl &> /dev/null; then
        run_command "Flushing systemd-resolved cache" sudo resolvectl flush-caches 2>/dev/null || true
    fi
    
    # 2. Restart nscd (older systems)
    if command -v nscd &> /dev/null; then
        run_command "Restarting nscd" sudo systemctl restart nscd 2>/dev/null || true
    fi

    # 3. Force NetBIOS resolution cache cleanup (Samba's specific cache)
    echo -e "${YELLOW}Cleaning Samba internal NetBIOS cache files...${NC}"
    run_command "Removing Samba cache files" sudo rm -f /var/cache/samba/browse.dat /var/cache/samba/unexpected.tdb /var/cache/samba/*.tdb 2>/dev/null || true

    # 4. Use wbinfo to manually flush the cache
    if command -v wbinfo &> /dev/null; then
        run_command "Flushing Winbind cache" sudo wbinfo --online-status > /dev/null 2>&1 || true
    fi
    # --- END AGGRESSIVE CACHE FLUSH LOGIC ---

    echo -e "${GREEN}✓ Services restarted and caches flushed${NC}"
}

# Function to perform verification tests
test_and_finish() {
    print_header "Verification Tests"
    
    # Test 1: getent (NSS check)
    print_subheader "Test 1: NSS Resolution (getent hosts)"
    echo -e "${GREEN}→ getent hosts $HOST_TO_TEST${NC}"
    local getent_output
    getent_output=$(getent hosts "$HOST_TO_TEST" 2>&1)
    echo "$getent_output"
    
    # Test 2: nmblookup (NetBIOS check)
    print_subheader "Test 2: NetBIOS Resolution (nmblookup)"
    echo -e "${GREEN}→ nmblookup $HOST_TO_TEST${NC}"
    local nmblookup_output
    nmblookup_output=$(nmblookup "$HOST_TO_TEST" 2>&1)
    echo "$nmblookup_output"

    # Test 3: Direct ping test to catch the "System error" issue
    print_subheader "Test 3: Actual Ping Test (Critical)"
    echo -e "${GREEN}→ ping -c 1 -W 2 $HOST_TO_TEST${NC}"
    local ping_output
    ping_output=$(ping -c 1 -W 2 "$HOST_TO_TEST" 2>&1)
    local ping_exit=$?
    echo "$ping_output"
    
    # Analysis
    print_header "Results Analysis"
    
    # Check if getent returns the correct IP FIRST
    local first_ip
    first_ip=$(echo "$getent_output" | head -1 | awk '{print $1}')
    
    echo -e "${BOLD}Analysis:${NC}"
    echo "• First IP returned by getent: ${YELLOW}$first_ip${NC}"
    echo "• Expected correct IP: ${GREEN}$HOST_CORRECT_IP${NC}"
    
    if echo "$getent_output" | grep -q "$HOST_CORRECT_IP"; then
        echo -e "${GREEN}✓${NC} getent found the correct IP ($HOST_CORRECT_IP)"
    else
        echo -e "${RED}✗${NC} getent did NOT find the correct IP ($HOST_CORRECT_IP)"
    fi
    
    if echo "$nmblookup_output" | grep -q "$HOST_CORRECT_IP"; then
        echo -e "${GREEN}✓${NC} nmblookup found the correct IP ($HOST_CORRECT_IP)"
    else
        echo -e "${RED}✗${NC} nmblookup did NOT find the correct IP"
    fi
    
    # THE CRITICAL TEST: Did ping actually work?
    if [ $ping_exit -eq 0 ] && echo "$ping_output" | grep -q "from $HOST_CORRECT_IP"; then
        echo -e "${GREEN}✓${NC} ping succeeded to the CORRECT IP ($HOST_CORRECT_IP)"
        echo ""
        print_header "SUCCESS! ✓"
        echo -e "${GREEN}${BOLD}You can now ping '$HOST_TO_TEST' by name reliably.${NC}"
    elif [ $ping_exit -eq 0 ]; then
        # Ping succeeded but to wrong IP
        echo -e "${YELLOW}⚠${NC} ping succeeded but may be using the wrong IP"
        echo ""
        print_header "PARTIAL SUCCESS"
        echo -e "${YELLOW}Name resolution is working, but may be returning multiple IPs.${NC}"
        echo -e "${YELLOW}The system is using: $first_ip${NC}"
        echo ""
        echo -e "${YELLOW}${BOLD}PROBLEM IDENTIFIED:${NC}"
        echo "Multiple IP addresses are registered for '$HOST_TO_TEST'."
        echo "The FIRST IP returned (${YELLOW}$first_ip${NC}) is being used by ping."
        echo ""
        echo -e "${CYAN}${BOLD}SOLUTIONS:${NC}"
        echo "1. On Windows host '$HOST_TO_TEST', run this PowerShell command as Administrator:"
        echo -e "   ${GREEN}nbtstat -RR${NC}"
        echo "   This will release and re-register NetBIOS names."
        echo ""
        echo "2. Alternatively, flush the ARP cache on this Linux machine:"
        echo -e "   ${GREEN}sudo ip -s -s neigh flush all${NC}"
        echo ""
        echo "3. Add an entry to /etc/hosts as a workaround:"
        echo -e "   ${GREEN}echo '$HOST_CORRECT_IP    $HOST_TO_TEST' | sudo tee -a /etc/hosts${NC}"
    else
        # Ping failed completely
        echo -e "${RED}✗${NC} ping FAILED"
        echo ""
        if echo "$ping_output" | grep -q "System error"; then
            print_header "FAILURE - System Error Detected"
            echo -e "${RED}${BOLD}The 'System error' indicates NSS resolution is returning multiple IPs${NC}"
            echo -e "${RED}and the system cannot determine which one to use.${NC}"
            echo ""
            echo -e "${YELLOW}Current situation:${NC}"
            echo "• getent returns MULTIPLE IPs for '$HOST_TO_TEST'"
            echo "• The FIRST IP ($first_ip) is likely wrong/stale"
            echo "• This causes the 'System error' when ping tries to use it"
            echo ""
            echo -e "${CYAN}${BOLD}IMMEDIATE SOLUTIONS:${NC}"
            echo ""
            echo "1. ${BOLD}[RECOMMENDED]${NC} On the Windows host '$HOST_TO_TEST', run as Administrator:"
            echo -e "   ${GREEN}nbtstat -RR${NC}"
            echo "   This releases all NetBIOS registrations and re-registers with the correct IP."
            echo ""
            echo "2. Manually add to /etc/hosts (temporary workaround):"
            echo -e "   ${GREEN}echo '$HOST_CORRECT_IP    $HOST_TO_TEST' | sudo tee -a /etc/hosts${NC}"
            echo ""
            echo "3. Flush ARP cache on this machine:"
            echo -e "   ${GREEN}sudo ip -s -s neigh flush all${NC}"
            echo ""
            echo "4. Reboot both machines to force fresh NetBIOS registration."
        else
            print_header "FAILURE"
            echo -e "${RED}Ping test failed for unknown reasons.${NC}"
            echo "Check network connectivity and firewall settings."
        fi
    fi
}

# --- Main Execution ---
auto_elevate # Check for sudo and re-execute if necessary

# The rest of the script only runs as root
script_intro
install_packages
get_workgroup
configure_nsswitch
configure_samba
restart_services
test_and_finish

echo ""
print_header "Script Finished"
