#!/bin/bash
# Author: Roy Wiseman 2025-02

# Script to create/manage a Samba share
# Version 1.0

# Automatically elevate privileges with sudo if not running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Elevation required; rerunning as sudo..." 1>&2 # Print to stderr
    sudo "$0" "$@"; # Rerun the current script with sudo and pass all arguments
    exit 0 # Exit the current script after rerunning with sudo
fi

# --- Configuration ---
APP_NAME="${0##*/}"
SMB_CONF_FILE="/etc/samba/smb.conf"
SMB_CONF_BACKUP="/etc/samba/smb.conf.original_script_backup"
REQUIRED_PKGS="samba smbclient cifs-utils"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Global Variables ---
SHARE_PATH=""
SHARE_NAME=""
WRITEABLE="false" # Samba 'writable = no'
GUEST_ACCESS="false" # Samba 'guest ok = no'
USER_LIST=""
AUTO_YES="false"
CURRENT_INVOKING_USER=""

# --- Functions ---

print_step() {
    echo -e "\n${YELLOW}>>> STEP: $1${NC}"
}

print_info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}WARN: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Function to print command that will be run
print_command() {
    echo -e "${GREEN}# sudo $1${NC}"
}

# Function to run a command with sudo, print it first
run_command() {
    print_command "$1"
    if [ "$AUTO_YES" = "false" ]; then
        read -p "Run this command? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
            print_warn "Skipping command."
            return 1
        fi
    fi
    sudo bash -c "$1"
    return $?
}

# Function to run a command that doesn't need user confirmation (e.g. status checks)
run_command_no_confirm() {
    print_command "$1"
    sudo bash -c "$1"
    return $?
}

# Function to run a command that doesn't need sudo (e.g. local tests)
run_local_command() {
    echo -e "${GREEN}# $1${NC}"
    bash -c "$1"
    return $?
}


show_usage() {
    echo "Usage: $APP_NAME -p <path> [options]"
    echo ""
    echo "Summary of steps:"
    echo "  1. Update package lists."
    echo "  2. Install Samba and client utilities if not present."
    echo "  3. Ensure Samba services (smbd, nmbd) are running and enabled."
    echo "  4. Create the specified directory if it doesn't exist."
    echo "  5. Set appropriate filesystem permissions on the directory."
    echo "  6. Add/enable specified Linux users to Samba (prompts for passwords)."
    echo "  7. Backup original smb.conf (if not already done by this script)."
    echo "  8. Add or update the share configuration in $SMB_CONF_FILE (idempotently)."
    echo "  9. Validate Samba configuration."
    echo " 10. Restart Samba services."
    echo " 11. Check firewall and add Samba rules if necessary."
    echo " 12. Display summary and connection tips."
    echo ""
    echo "Options:"
    echo "  -p, --path <path>          : Absolute or relative (e.g., ~/) path to the directory to share (required)."
    echo "  -n, --name <name>          : Name of the Samba share (defaults to the last part of the path)."
    echo "  -w, --writeable            : Allow writing to the share (default is read-only)."
    echo "  -g, --guest                : Allow guest access without a password."
    echo "  -u, --users <user1,...>    : Comma-separated list of valid Linux users for authenticated access."
    echo "                               (If not given and guest not allowed, defaults to the user running the script)."
    echo "  -y, --yes                  : Automatically answer yes to prompts (use with caution)."
    echo "  -h, --help                 : Show this help message."
    exit 0
}

# Function to expand path (handles ~/, ./, ../) and get absolute path
get_absolute_path() {
    local path_to_expand="$1"
    local expanded_path

    if [[ "$path_to_expand" == "~/"* ]]; then
        if [ -n "$SUDO_USER" ]; then
            USER_HOME_DIR=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            expanded_path="$USER_HOME_DIR/${path_to_expand#\~/}"
        else
            expanded_path="$HOME/${path_to_expand#\~/}" # Should not happen if sudo is used
        fi
    elif [[ "$path_to_expand" == "~"* ]];
    then
        print_warn "Path expansion for '~user' is not fully supported. Trying basic expansion."
        # Basic expansion for ~user/path
        local temp_user_path="${path_to_expand#\~}"
        local target_user_lookup="${temp_user_path%%/*}"
        local rest_of_user_path="${temp_user_path#$target_user_lookup}" # may be empty or start with /
        rest_of_user_path="${rest_of_user_path#\/}" # remove leading / if any

        USER_HOME_DIR=$(getent passwd "$target_user_lookup" | cut -d: -f6)
        if [ -z "$USER_HOME_DIR" ]; then
            print_error "Could not resolve home directory for user in path: $target_user_lookup"
            exit 1
        fi
        if [ -n "$rest_of_user_path" ]; then
            expanded_path="$USER_HOME_DIR/$rest_of_user_path"
        else
            expanded_path="$USER_HOME_DIR"
        fi
    else
        expanded_path="$path_to_expand"
    fi
    
    if ! readlink -m "$expanded_path" > /dev/null 2>&1 && [[ ! -d "$expanded_path" && "$path_to_expand" != *"/"* && "$path_to_expand" != "."* ]]; then
         # If it's a simple name (not looking like a path) and doesn't exist, assume it's relative to current dir for readlink
         SHARE_PATH_ABS=$(readlink -m "./$expanded_path")
    else
         SHARE_PATH_ABS=$(readlink -m "$expanded_path")
    fi


    if [ -z "$SHARE_PATH_ABS" ]; then
        print_error "Failed to resolve absolute path for: $path_to_expand"
        exit 1
    fi
    echo "$SHARE_PATH_ABS"
}

# --- Sanity Checks & Argument Parsing ---
if [ "$(id -u)" -eq 0 ]; then
    print_warn "Running as root. SUDO_USER might not be set. Default user might be 'root'."
    CURRENT_INVOKING_USER="root"
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then # If sudo su - then SUDO_USER might be root
        CURRENT_INVOKING_USER="$SUDO_USER"
    fi
else
    if ! sudo -n true 2>/dev/null; then
      print_error "This script requires sudo privileges to run its commands. Please run with sudo or ensure passwordless sudo is configured if using -y."
      echo "Example: sudo $0 -p /path/to/share"
      exit 1
    fi
    if [ -n "$SUDO_USER" ]; then
      CURRENT_INVOKING_USER="$SUDO_USER"
    else
      CURRENT_INVOKING_USER="$USER" # Fallback if SUDO_USER not set (e.g. direct root login or script not via sudo)
    fi
fi


# Using getopt for robust argument parsing
ARGS=$(getopt -o p:n:wgu:yh --long path:,name:,writeable,guest,users:,yes,help -n "$APP_NAME" -- "$@")
if [ $? -ne 0 ]; then
    show_usage
    exit 1
fi
eval set -- "$ARGS"

while true; do
    case "$1" in
        -p|--path) SHARE_PATH="$2"; shift 2;;
        -n|--name) SHARE_NAME="$2"; shift 2;;
        -w|--writeable) WRITEABLE="true"; shift;;
        -g|--guest) GUEST_ACCESS="true"; shift;;
        -u|--users) USER_LIST="$2"; shift 2;;
        -y|--yes) AUTO_YES="true"; shift;;
        -h|--help) show_usage; exit 0;;
        --) shift; break;;
        *) print_error "Internal error!"; exit 1;;
    esac
done

if [ -z "$SHARE_PATH" ]; then
    print_error "Share path (-p, --path) is required."
    show_usage
    exit 1
fi

# --- Main Script Logic ---

echo "Starting Samba Share Setup: $APP_NAME"
echo "-------------------------------------"
if [ "$AUTO_YES" = "true" ]; then
    print_warn "Running in non-interactive mode (-y). Assuming 'yes' to all confirmations."
fi

# Resolve path and name
SHARE_PATH_ABS=$(get_absolute_path "$SHARE_PATH")
print_info "Absolute path to share: $SHARE_PATH_ABS"

if [ -z "$SHARE_NAME" ]; then
    SHARE_NAME=$(basename "$SHARE_PATH_ABS")
fi
print_info "Samba share name will be: [$SHARE_NAME]"

# Determine user list for Samba
EFFECTIVE_USER_LIST_SAMBA=""
if [ -n "$USER_LIST" ]; then
    EFFECTIVE_USER_LIST_SAMBA="$USER_LIST"
    print_info "Specified valid users for Samba: $EFFECTIVE_USER_LIST_SAMBA"
elif [ "$GUEST_ACCESS" = "false" ]; then
    EFFECTIVE_USER_LIST_SAMBA="$CURRENT_INVOKING_USER"
    print_info "No users specified and guest access is off. Defaulting to Samba user: $EFFECTIVE_USER_LIST_SAMBA"
else
    print_info "Guest access is enabled, and no specific users provided via -u."
fi


# Step 1: Update package list
print_step "Updating package list"
echo "Test: Checking if package lists need an update (will run update)."
run_command "apt-get update" || { print_error "Failed to update package lists."; exit 1; }

# Step 2: Install Samba and client tools
print_step "Installing Samba packages"
INSTALLED_ALL_PKGS=true
for pkg in $REQUIRED_PKGS; do
    echo "Test: Checking if $pkg is installed."
    if dpkg -s "$pkg" >/dev/null 2>&1 && dpkg -s "$pkg" | grep -q "Status: install ok installed"; then
        print_info "$pkg is already installed."
    else
        print_info "$pkg is NOT installed."
        INSTALLED_ALL_PKGS=false
    fi
done

if [ "$INSTALLED_ALL_PKGS" = "false" ]; then
    print_info "Attempting to install missing Samba packages: $REQUIRED_PKGS"
    run_command "apt-get install -y $REQUIRED_PKGS" || { print_error "Failed to install Samba packages."; exit 1; }
else
    print_info "All required Samba packages are already installed."
fi

# Step 3: Check if Samba service is running and enabled
print_step "Ensuring Samba services are running and enabled"
SERVICES_TO_CHECK="smbd nmbd"
for service in $SERVICES_TO_CHECK; do
    echo "Test: Checking status of $service service."
    if systemctl is-active --quiet "$service"; then
        print_info "$service service is active."
    else
        print_warn "$service service is not active. Attempting to start it."
        run_command "systemctl start $service" || print_error "Failed to start $service."
    fi

    echo "Test: Checking if $service service is enabled."
    if systemctl is-enabled --quiet "$service"; then
        print_info "$service service is enabled."
    else
        print_warn "$service service is not enabled. Attempting to enable it."
        run_command "systemctl enable $service" || print_error "Failed to enable $service."
    fi
done

# Step 4: Create the directory to be shared if it doesn't exist
print_step "Creating shared directory: $SHARE_PATH_ABS"
echo "Test: Checking if directory $SHARE_PATH_ABS exists."
if [ -d "$SHARE_PATH_ABS" ]; then
    print_info "Directory $SHARE_PATH_ABS already exists."
else
    print_info "Directory $SHARE_PATH_ABS does not exist. Creating it."
    run_command "mkdir -p \"$SHARE_PATH_ABS\"" || { print_error "Failed to create directory $SHARE_PATH_ABS."; exit 1; }
fi

# Step 5: Set filesystem permissions for the shared directory
print_step "Setting filesystem permissions for $SHARE_PATH_ABS"
FS_OWNER="$CURRENT_INVOKING_USER" # Default owner
FS_GROUP=$(id -gn "$FS_OWNER")    # Default group

if [ -n "$EFFECTIVE_USER_LIST_SAMBA" ]; then
    FS_OWNER=$(echo "$EFFECTIVE_USER_LIST_SAMBA" | cut -d, -f1)
    if ! id "$FS_OWNER" >/dev/null 2>&1; then
        print_warn "User '$FS_OWNER' (first from -u list) does not exist as a Linux user. Defaulting owner to $CURRENT_INVOKING_USER."
        FS_OWNER="$CURRENT_INVOKING_USER"
    fi
    FS_GROUP=$(id -gn "$FS_OWNER")
elif [ "$GUEST_ACCESS" = "true" ]; then
    FS_OWNER="nobody"
    if ! id "nogroup" >/dev/null 2>&1; then # Debian uses nogroup
        run_command "groupadd nogroup" # Ensure nogroup exists
    fi
    FS_GROUP="nogroup"
fi

print_info "Setting owner of $SHARE_PATH_ABS to $FS_OWNER:$FS_GROUP."
run_command "chown \"$FS_OWNER:$FS_GROUP\" \"$SHARE_PATH_ABS\""

FS_PERMS="0755" # Default: rwxr-xr-x
if [ "$WRITEABLE" = "true" ]; then
    if [ "$GUEST_ACCESS" = "true" ] && [ -z "$EFFECTIVE_USER_LIST_SAMBA" ]; then # Writable guest-only share
        FS_PERMS="0777" # rwxrwxrwx - guest (nobody) needs to write
        print_info "Setting permissions for writable guest access to $FS_PERMS."
    else # Writable by owner/group
        FS_PERMS="0775" # rwxrwxr-x
        print_info "Setting permissions for writable access (owner/group) to $FS_PERMS."
        print_warn "Ensure all users in '$EFFECTIVE_USER_LIST_SAMBA' have necessary group memberships or ACLs on '$SHARE_PATH_ABS' if they need to write and are not '$FS_OWNER'."
    fi
else # Read-only
    FS_PERMS="0755" # rwxr-xr-x
    print_info "Setting permissions for read-only access to $FS_PERMS."
fi
run_command "chmod $FS_PERMS \"$SHARE_PATH_ABS\""


# Step 6: Add Linux users to Samba
print_step "Managing Samba users"
if [ -n "$EFFECTIVE_USER_LIST_SAMBA" ]; then
    IFS=',' read -ra USERS_ARRAY <<< "$EFFECTIVE_USER_LIST_SAMBA"
    for user in "${USERS_ARRAY[@]}"; do
        # Trim whitespace if any
        user=$(echo "$user" | xargs)
        echo "Test: Checking if Linux user '$user' exists."
        if ! id "$user" >/dev/null 2>&1; then
            print_error "Linux user '$user' does not exist. Please create the Linux user first."
            print_warn "Skipping Samba password steps for '$user'."
            continue
        fi

        echo "Test: Checking if '$user' is already a Samba user (sudo pdbedit -L | grep \"^${user}:\")."
        if sudo pdbedit -L | grep -q "^${user}:"; then
            print_info "User '$user' already exists in Samba database. Will ensure they are enabled."
            # Optionally, could offer to reset password here. For now, just enable.
        else
            print_info "User '$user' not found in Samba database. Adding now."
            echo -e "${YELLOW}You will be prompted to set a Samba password for user '$user'.${NC}"
            # smbpasswd -a is interactive for password, can't be fully automated with -y for password part
            print_command "smbpasswd -a \"$user\""
            sudo smbpasswd -a "$user"
            if [ $? -ne 0 ]; then
                print_error "Failed to add user '$user' to Samba with smbpasswd -a."
                continue
            fi
        fi
        print_info "Enabling Samba user '$user'."
        run_command_no_confirm "smbpasswd -e \"$user\""
    done
else
    print_info "No specific users to add to Samba (likely guest access or no users defined for share)."
fi


# Step 7: Backup the original Samba configuration file
print_step "Backing up Samba configuration"
echo "Test: Checking for existing backup $SMB_CONF_BACKUP."
if [ -f "$SMB_CONF_BACKUP" ]; then
    print_info "Original Samba configuration backup already exists: $SMB_CONF_BACKUP."
else
    if [ -f "$SMB_CONF_FILE" ]; then
        print_info "Backing up $SMB_CONF_FILE to $SMB_CONF_BACKUP."
        run_command "cp \"$SMB_CONF_FILE\" \"$SMB_CONF_BACKUP\""
    else
        print_warn "$SMB_CONF_FILE does not exist. Skipping backup (it will be created)."
    fi
fi

# Step 8: Configure the Samba share in smb.conf (idempotently)
print_step "Configuring Samba share: [$SHARE_NAME]"
START_MARKER="# BEGIN SMB SHARE CONFIG: $SHARE_NAME"
END_MARKER="# END SMB SHARE CONFIG: $SHARE_NAME"
TEMP_SMB_CONF=$(sudo mktemp) # Needs sudo to ensure it can be moved/copied to /etc/samba later

# Escape for sed
escaped_start_marker=$(printf '%s\n' "$START_MARKER" | sed 's:[][\\/.^$*]:\\&:g')
escaped_end_marker=$(printf '%s\n' "$END_MARKER" | sed 's:[][\\/.^$*]:\\&:g')

SAMBA_WRITABLE_BOOL="no"
SAMBA_READ_ONLY_BOOL="yes"
if [ "$WRITEABLE" = "true" ]; then
    SAMBA_WRITABLE_BOOL="yes"
    SAMBA_READ_ONLY_BOOL="no"
fi

SAMBA_GUEST_OK_BOOL="no"
if [ "$GUEST_ACCESS" = "true" ]; then
    SAMBA_GUEST_OK_BOOL="yes"
fi

# Prepare the share configuration block
# Using a temporary file for the block content to handle multi-line and variable expansion easily
SHARE_CONFIG_BLOCK_FILE=$(mktemp)
cat > "$SHARE_CONFIG_BLOCK_FILE" <<EOF
[$SHARE_NAME]
    path = $SHARE_PATH_ABS
    browseable = yes
    writable = $SAMBA_WRITABLE_BOOL
    read only = $SAMBA_READ_ONLY_BOOL
    guest ok = $SAMBA_GUEST_OK_BOOL
EOF

if [ -n "$EFFECTIVE_USER_LIST_SAMBA" ]; then
    echo "    valid users = $EFFECTIVE_USER_LIST_SAMBA" >> "$SHARE_CONFIG_BLOCK_FILE"
fi

# Special handling for writable guest-only shares (no valid users specified)
if [ "$GUEST_ACCESS" = "true" ] && [ "$WRITEABLE" = "true" ] && [ -z "$EFFECTIVE_USER_LIST_SAMBA" ]; then
    echo "    force user = nobody" >> "$SHARE_CONFIG_BLOCK_FILE"
    echo "    force group = nogroup" >> "$SHARE_CONFIG_BLOCK_FILE"
    print_info "Configuring 'force user = nobody' and 'force group = nogroup' for writable guest share."
fi
# Common masks for created files/dirs
echo "    create mask = 0664" >> "$SHARE_CONFIG_BLOCK_FILE"
echo "    directory mask = 0775" >> "$SHARE_CONFIG_BLOCK_FILE"


echo "Test: Checking if configuration block for '$SHARE_NAME' already exists in $SMB_CONF_FILE."
if sudo grep -qFx "$START_MARKER" "$SMB_CONF_FILE"; then
    print_info "Existing configuration block found for '$SHARE_NAME'. It will be replaced."
    # Use awk to filter out the old block and write to temp file
    # This is safer than complex in-place sed for multi-line blocks
    sudo awk "/^${escaped_start_marker}$/,/^${escaped_end_marker}$/{next}1" "$SMB_CONF_FILE" > "$TEMP_SMB_CONF"
    sudo cp "$TEMP_SMB_CONF" "$SMB_CONF_FILE" # Replace original with filtered content
else
    print_info "No existing configuration block for '$SHARE_NAME'. Adding new one."
    # If smb.conf doesn't end with a newline, add one for cleaner append
    if [ -n "$(sudo tail -c1 "$SMB_CONF_FILE" 2>/dev/null)" ]; then
      echo | sudo tee -a "$SMB_CONF_FILE" > /dev/null
    fi
fi

# Append the new block
print_info "The following block will be appended/updated in $SMB_CONF_FILE:"
echo -e "${GREEN}${START_MARKER}${NC}"
cat "$SHARE_CONFIG_BLOCK_FILE" | sed 's/^/  /' | sed "1s/^  /${GREEN}/" | sed "\$s/\$/${NC}/" # Indent and color
echo -e "${GREEN}${END_MARKER}${NC}"

{
    echo "" # Ensure a blank line before our block if file wasn't empty
    echo "$START_MARKER"
    cat "$SHARE_CONFIG_BLOCK_FILE"
    echo "$END_MARKER"
} | sudo tee -a "$SMB_CONF_FILE" > /dev/null

rm "$SHARE_CONFIG_BLOCK_FILE"
sudo rm "$TEMP_SMB_CONF"


# Step 9: Test the Samba configuration file for syntax errors
print_step "Validating Samba configuration"
echo "Test: Running testparm -s."
# testparm might output to stderr on success if config is minimal, so redirect to stdout
if sudo testparm -s 2>&1 | grep -q "Loaded services file OK."; then
    print_info "Samba configuration syntax is OK."
    sudo testparm -s # Show the loaded config briefly
else
    print_error "Samba configuration has errors! Please review the output below and $SMB_CONF_FILE."
    sudo testparm -s
    exit 1
fi

# Step 10: Restart Samba services to apply changes
print_step "Restarting Samba services"
run_command "systemctl restart smbd nmbd" || { print_error "Failed to restart Samba services."; exit 1; }
print_info "Samba services restarted."

# Step 11: Allow Samba through the firewall (if UFW or firewalld is active)
print_step "Checking and configuring firewall"
FIREWALL_CONFIGURED=false
# Check for UFW
echo "Test: Checking for UFW firewall."
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
    print_info "UFW firewall is active."
    echo "Test: Checking if UFW allows Samba."
    if sudo ufw status verbose | grep -q "Samba"; then
        print_info "UFW already has a rule for Samba."
    else
        print_warn "UFW does not seem to have a rule for Samba. Attempting to add it."
        run_command "ufw allow Samba" || print_error "Failed to add Samba rule to UFW."
        if sudo ufw status verbose | grep -q "Samba"; then FIREWALL_CONFIGURED=true; fi
    fi
# Check for firewalld
elif command -v firewall-cmd >/dev/null && sudo systemctl is-active --quiet firewalld; then
    print_info "firewalld is active."
    echo "Test: Checking if firewalld allows Samba service (permanently)."
    if sudo firewall-cmd --query-service=samba --permanent 2>/dev/null; then # exit code 0 if enabled
        print_info "firewalld already has samba service enabled permanently."
    else
        print_warn "firewalld does not have samba service enabled permanently. Attempting to add and reload."
        run_command "firewall-cmd --permanent --add-service=samba"
        run_command "firewall-cmd --reload" || print_error "Failed to reload firewalld."
        if sudo firewall-cmd --query-service=samba --permanent 2>/dev/null; then FIREWALL_CONFIGURED=true; fi
    fi
else
    print_info "No active UFW or firewalld detected. Skipping firewall configuration."
    print_warn "If you are using a different firewall, ensure ports TCP 139, 445 and UDP 137, 138 are open."
fi
if [ "$FIREWALL_CONFIGURED" = "true" ]; then print_info "Firewall rule for Samba applied."; fi

# Step 12: Summary and Connection Tips
print_step "Setup Summary and Connection Tips"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}Samba share '[${SHARE_NAME}]' setup complete!${NC}"
echo "--------------------------------------------------"
echo "  Share Name:         [$SHARE_NAME]"
echo "  Local Path:         $SHARE_PATH_ABS"
echo "  Server IP Address:  $SERVER_IP (likely, verify with 'ip a')"
echo "  Writable:           $WRITEABLE"
echo "  Guest Access:       $GUEST_ACCESS"
if [ -n "$EFFECTIVE_USER_LIST_SAMBA" ]; then
    echo "  Authenticated Users: $EFFECTIVE_USER_LIST_SAMBA"
fi
echo "--------------------------------------------------"
echo ""
echo -e "${YELLOW}How to connect:${NC}"
echo -e "  ${GREEN}From Linux:${NC}"
echo "    Using smbclient (to list shares):"
echo "      smbclient -L //$SERVER_IP -U <username>%<password>"
echo "      (e.g., smbclient -L //$SERVER_IP -U $CURRENT_INVOKING_USER)"
echo "    Using smbclient (to connect to the share):"
echo "      smbclient //$SERVER_IP/$SHARE_NAME -U <username>%<password>"
echo "      (e.g., smbclient //$SERVER_IP/$SHARE_NAME -U $CURRENT_INVOKING_USER)"
echo "    Mounting with cifs:"
echo "      sudo mkdir -p /mnt/$SHARE_NAME"
echo "      sudo mount -t cifs //$SERVER_IP/$SHARE_NAME /mnt/$SHARE_NAME -o username=<username>,password=<password>,vers=3.0"
echo "      (For guest: sudo mount -t cifs //$SERVER_IP/$SHARE_NAME /mnt/$SHARE_NAME -o guest,vers=3.0)"
echo ""
echo -e "  ${GREEN}From Windows:${NC}"
echo "    Open File Explorer and type in the address bar:"
echo "      \\\\$SERVER_IP\\$SHARE_NAME"
echo "    You may be prompted for credentials if guest access is not enabled or if you're not a guest."
echo ""
echo -e "  ${GREEN}From macOS:${NC}"
echo "    Open Finder, go to 'Go' > 'Connect to Server...' (Cmd+K)"
echo "    Enter server address: smb://$SERVER_IP/$SHARE_NAME"
echo ""
echo -e "${YELLOW}Troubleshooting Tips:${NC}"
echo "  - Ensure the Linux user(s) specified exist and have Samba passwords set correctly."
echo "  - Double-check filesystem permissions on '$SHARE_PATH_ABS'."
echo "  - Verify Samba service status: 'sudo systemctl status smbd nmbd'."
echo "  - Check Samba logs: '/var/log/samba/log.smbd' and '/var/log/samba/log.<client_hostname>'."
echo -e "  - ${RED}Windows SMB Cache:${NC} Windows aggressively caches SMB connection details. If you change"
echo "    permissions or user credentials on the server, Windows might use old cached info."
echo "    To clear: "
echo "      1. Disconnect any mapped drives to the server."
echo "      2. Open Command Prompt (cmd) as Administrator and run: net use * /delete /y"
echo "      3. Optionally, if using Kerberos (less common for simple shares), run: klist purge"
echo "      4. Try connecting again. A reboot of the Windows client sometimes helps too."
echo ""
print_info "Script finished."

exit 0
