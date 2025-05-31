#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to create/manage an NFS share on Debian
# Version 1.0

# Automatically elevate privileges with sudo if not running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Elevation required; rerunning as sudo..." 1>&2 # Print to stderr
    sudo "$0" "$@"; # Rerun the current script with sudo and pass all arguments
    exit 0 # Exit the current script after rerunning with sudo
fi

# --- Configuration ---
APP_NAME="${0##*/}"
EXPORTS_FILE="/etc/exports"
EXPORTS_FILE_BACKUP="/etc/exports.original_script_backup"
# nfs-common provides showmount and other utilities, good to have on server too.
REQUIRED_PKGS="nfs-kernel-server nfs-common"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Global Variables ---
SHARE_PATH=""
CLIENT_SPEC="" # e.g., "192.168.1.0/24", "*", "clienthost.example.com"
WRITEABLE="false"
NO_ROOT_SQUASH="false"
ASYNC_MODE="false" # Default to sync for data safety
ENABLE_SUBTREE_CHECK="false" # Default to no_subtree_check
USER_ADDITIONAL_OPTIONS="" # e.g. "all_squash,anonuid=65534,anongid=65534"
AUTO_YES="false"
CURRENT_INVOKING_USER=""
CURRENT_INVOKING_USER_GROUP=""

# --- Functions --- (Reusing most from the Samba script structure)

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

print_command() {
    echo -e "${GREEN}# sudo $1${NC}"
}

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

run_command_no_confirm() {
    print_command "$1"
    sudo bash -c "$1"
    return $?
}

show_usage() {
    echo "Usage: sudo $APP_NAME -p <path> -c <client_spec> [options]"
    echo ""
    echo "Summary of steps:"
    echo "  1. Update package lists."
    echo "  2. Install NFS server packages ('nfs-kernel-server', 'nfs-common') if not present."
    echo "  3. Ensure NFS services are running and enabled."
    echo "  4. Create the specified directory if it doesn't exist."
    echo "  5. Set basic filesystem permissions on the directory (owner: invoking user, perms: 0755 or 0775)."
    echo "     NOTE: For actual client access, UID/GID matching or advanced NFS options like 'all_squash' are crucial."
    echo "  6. Backup original $EXPORTS_FILE (if not already done by this script)."
    echo "  7. Add or update the export configuration in $EXPORTS_FILE (idempotently using markers)."
    echo "  8. Apply NFS export changes using 'exportfs -ra'."
    echo "  9. Check firewall and add NFS rules if necessary."
    echo " 10. Display summary and connection tips."
    echo ""
    echo "Options:"
    echo "  -p, --path <path>                 : Absolute or relative path to the directory to share (required)."
    echo "  -c, --clients <client_spec>       : Client specification (e.g., \"192.168.1.0/24\", \"*\", \"host.example.com\") (required)."
    echo "  -w, --writeable                   : Allow writing to the share (sets 'rw' option, default is 'ro')."
    echo "      --no-root-squash              : Disable root squashing (maps client root to server root - USE WITH CAUTION)."
    echo "                                      (Default is 'root_squash')."
    echo "      --async                       : Use asynchronous mode (default is 'sync' for data integrity)."
    echo "      --enable-subtree-check        : Enable subtree_check (default is 'no_subtree_check')."
    echo "  -o, --options <additional_opts>   : Comma-separated list of additional NFS options to append"
    echo "                                      (e.g., \"all_squash,anonuid=65534,anongid=65534\")."
    echo "  -y, --yes                         : Automatically answer yes to prompts (use with caution)."
    echo "  -h, --help                        : Show this help message."
    exit 0
}

get_absolute_path() {
    local path_to_expand="$1"
    local expanded_path

    if [[ "$path_to_expand" == "~/"* ]]; then
        if [ -n "$SUDO_USER" ]; then
            USER_HOME_DIR=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            expanded_path="$USER_HOME_DIR/${path_to_expand#\~/}"
        else # Fallback, though script checks for sudo later.
            expanded_path="$HOME/${path_to_expand#\~/}"
        fi
    elif [[ "$path_to_expand" == "~"* ]]; then
        print_warn "Path expansion for '~user' is not fully supported. Trying basic expansion."
        local temp_user_path="${path_to_expand#\~}"
        local target_user_lookup="${temp_user_path%%/*}"
        local rest_of_user_path="${temp_user_path#$target_user_lookup}"
        rest_of_user_path="${rest_of_user_path#\/}"

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
    
    # Attempt to resolve, works even if path doesn't exist yet (unlike readlink -f)
    SHARE_PATH_ABS=$(readlink -m "$expanded_path")

    if [ -z "$SHARE_PATH_ABS" ]; then
        print_error "Failed to resolve absolute path for: $path_to_expand"
        exit 1
    fi
    echo "$SHARE_PATH_ABS"
}

# --- Sanity Checks & Argument Parsing ---
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script needs to be run with sudo or as root for most operations."
    echo "Example: sudo $0 -p /path/to/share -c \"*\""
    exit 1
fi

if [ -n "$SUDO_USER" ]; then
  CURRENT_INVOKING_USER="$SUDO_USER"
  CURRENT_INVOKING_USER_GROUP=$(id -gn "$SUDO_USER")
else
  CURRENT_INVOKING_USER="$USER" # e.g. if logged in as root
  CURRENT_INVOKING_USER_GROUP=$(id -gn "$USER")
fi


ARGS=$(getopt -o p:c:wo:yh --long path:,clients:,writeable,no-root-squash,async,enable-subtree-check,options:,yes,help -n "$APP_NAME" -- "$@")
if [ $? -ne 0 ]; then
    show_usage
    exit 1
fi
eval set -- "$ARGS"

while true; do
    case "$1" in
        -p|--path) SHARE_PATH="$2"; shift 2;;
        -c|--clients) CLIENT_SPEC="$2"; shift 2;;
        -w|--writeable) WRITEABLE="true"; shift;;
        --no-root-squash) NO_ROOT_SQUASH="true"; shift;;
        --async) ASYNC_MODE="true"; shift;;
        --enable-subtree-check) ENABLE_SUBTREE_CHECK="true"; shift;;
        -o|--options) USER_ADDITIONAL_OPTIONS="$2"; shift 2;;
        -y|--yes) AUTO_YES="true"; shift;;
        -h|--help) show_usage; exit 0;;
        --) shift; break;;
        *) print_error "Internal error during argument parsing!"; exit 1;;
    esac
done

if [ -z "$SHARE_PATH" ]; then
    print_error "Share path (-p, --path) is required."
    show_usage
    exit 1
fi
if [ -z "$CLIENT_SPEC" ]; then
    print_error "Client specification (-c, --clients) is required."
    show_usage
    exit 1
fi

# --- Main Script Logic ---

echo "Starting NFS Share Setup: $APP_NAME"
echo "-------------------------------------"
if [ "$AUTO_YES" = "true" ]; then
    print_warn "Running in non-interactive mode (-y). Assuming 'yes' to all confirmations."
fi

SHARE_PATH_ABS=$(get_absolute_path "$SHARE_PATH")
print_info "Absolute path to share: $SHARE_PATH_ABS"
print_info "Client specification: $CLIENT_SPEC"


# Step 1: Update package list
print_step "Updating package list"
echo "Test: Checking if package lists need an update (will run update)."
run_command "apt-get update" || { print_error "Failed to update package lists."; exit 1; }

# Step 2: Install NFS server packages
print_step "Installing NFS packages"
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
    print_info "Attempting to install missing NFS packages: $REQUIRED_PKGS"
    run_command "apt-get install -y $REQUIRED_PKGS" || { print_error "Failed to install NFS packages."; exit 1; }
else
    print_info "All required NFS packages are already installed."
fi

# Step 3: Ensure NFS services are running and enabled
print_step "Ensuring NFS services are running and enabled"
NFS_SERVICE="nfs-kernel-server" # Main service in Debian
echo "Test: Checking status of $NFS_SERVICE service."
if systemctl is-active --quiet "$NFS_SERVICE"; then
    print_info "$NFS_SERVICE service is active."
else
    print_warn "$NFS_SERVICE service is not active. Attempting to start it."
    run_command "systemctl start $NFS_SERVICE" || print_error "Failed to start $NFS_SERVICE."
fi

echo "Test: Checking if $NFS_SERVICE service is enabled."
if systemctl is-enabled --quiet "$NFS_SERVICE"; then
    print_info "$NFS_SERVICE service is enabled."
else
    print_warn "$NFS_SERVICE service is not enabled. Attempting to enable it."
    run_command "systemctl enable $NFS_SERVICE" || print_error "Failed to enable $NFS_SERVICE."
fi

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
print_info "Setting owner of $SHARE_PATH_ABS to $CURRENT_INVOKING_USER:$CURRENT_INVOKING_USER_GROUP."
run_command "chown \"$CURRENT_INVOKING_USER:$CURRENT_INVOKING_USER_GROUP\" \"$SHARE_PATH_ABS\""

FS_PERMS="0755" # Default: rwxr-xr-x
if [ "$WRITEABLE" = "true" ]; then
    FS_PERMS="0775" # rwxrwxr-x (owner and group can write)
    print_info "Setting permissions for writable access (owner/group) to $FS_PERMS."
else
    print_info "Setting permissions for read-only access to $FS_PERMS."
fi
run_command "chmod $FS_PERMS \"$SHARE_PATH_ABS\""
print_warn "NFS relies on UID/GID matching. Ensure client UIDs/GIDs align with server permissions"
print_warn "on '$SHARE_PATH_ABS' (currently owned by $CURRENT_INVOKING_USER, perms $FS_PERMS)."
print_warn "For broader write access or specific user mapping, consider 'all_squash', 'anonuid', 'anongid' in NFS options (-o)."

# Step 6: Backup the original /etc/exports file
print_step "Backing up NFS exports configuration"
echo "Test: Checking for existing backup $EXPORTS_FILE_BACKUP."
if [ -f "$EXPORTS_FILE_BACKUP" ]; then
    print_info "Original NFS exports backup already exists: $EXPORTS_FILE_BACKUP."
else
    if [ -f "$EXPORTS_FILE" ]; then
        print_info "Backing up $EXPORTS_FILE to $EXPORTS_FILE_BACKUP."
        run_command "cp \"$EXPORTS_FILE\" \"$EXPORTS_FILE_BACKUP\""
    else
        print_warn "$EXPORTS_FILE does not exist. Skipping backup (it may be created)."
    fi
fi

# Step 7: Configure the NFS export in /etc/exports (idempotently)
print_step "Configuring NFS export for: $SHARE_PATH_ABS"

# Build NFS options string
NFS_OPTS_ARRAY=()
if [ "$WRITEABLE" = "true" ]; then NFS_OPTS_ARRAY+=("rw"); else NFS_OPTS_ARRAY+=("ro"); fi
if [ "$ASYNC_MODE" = "true" ]; then NFS_OPTS_ARRAY+=("async"); else NFS_OPTS_ARRAY+=("sync"); fi
if [ "$NO_ROOT_SQUASH" = "true" ]; then NFS_OPTS_ARRAY+=("no_root_squash"); else NFS_OPTS_ARRAY+=("root_squash"); fi
if [ "$ENABLE_SUBTREE_CHECK" = "true" ]; then NFS_OPTS_ARRAY+=("subtree_check"); else NFS_OPTS_ARRAY+=("no_subtree_check"); fi

if [ -n "$USER_ADDITIONAL_OPTIONS" ]; then
    IFS=',' read -ra ADDTL_OPTS_TMP_ARRAY <<< "$USER_ADDITIONAL_OPTIONS"
    for opt in "${ADDTL_OPTS_TMP_ARRAY[@]}"; do
        # Basic sanitization: remove leading/trailing whitespace
        opt=$(echo "$opt" | xargs)
        if [ -n "$opt" ]; then
            NFS_OPTS_ARRAY+=("$opt")
        fi
    done
fi
OPTIONS_STRING=$(IFS=,; echo "${NFS_OPTS_ARRAY[*]}")

# Marker for identifying script-managed entries related to THIS PATH
# Replace slashes in path for marker to avoid conflict with sed delimiter
MARKER_PATH_ID=$(echo "$SHARE_PATH_ABS" | sed 's/\//_/g')
START_MARKER="# BEGIN NFS EXPORT CONFIG FOR PATH: $MARKER_PATH_ID"
END_MARKER="# END NFS EXPORT CONFIG FOR PATH: $MARKER_PATH_ID"

EXPORT_LINE_CONTENT="$SHARE_PATH_ABS $CLIENT_SPEC($OPTIONS_STRING)"

TEMP_EXPORTS_CONF=$(mktemp)

echo "Test: Checking if configuration block for path '$SHARE_PATH_ABS' already exists in $EXPORTS_FILE."
if sudo grep -qFx "$START_MARKER" "$EXPORTS_FILE"; then
    print_info "Existing configuration block found for path '$SHARE_PATH_ABS'. It will be replaced."
    # Use awk to filter out the old block and write to temp file
    escaped_start_marker=$(printf '%s\n' "$START_MARKER" | sed 's:[][\\/.^$*]:\\&:g')
    escaped_end_marker=$(printf '%s\n' "$END_MARKER" | sed 's:[][\\/.^$*]:\\&:g')
    sudo awk "/^${escaped_start_marker}$/,/^${escaped_end_marker}$/{next}1" "$EXPORTS_FILE" > "$TEMP_EXPORTS_CONF"
    sudo cp "$TEMP_EXPORTS_CONF" "$EXPORTS_FILE"
else
    print_info "No existing configuration block for path '$SHARE_PATH_ABS'."
    # Ensure smb.conf ends with a newline if it doesn't
    if [ -s "$EXPORTS_FILE" ] && [ -n "$(sudo tail -c1 "$EXPORTS_FILE" 2>/dev/null)" ]; then
      echo | sudo tee -a "$EXPORTS_FILE" > /dev/null
    fi
fi

print_info "The following export configuration will be added/updated in $EXPORTS_FILE:"
echo -e "${GREEN}${START_MARKER}${NC}"
echo -e "${GREEN}${EXPORT_LINE_CONTENT}${NC}"
echo -e "${GREEN}${END_MARKER}${NC}"

{
    echo "" # Ensure a blank line before our block if file wasn't empty and no previous block
    echo "$START_MARKER"
    echo "$EXPORT_LINE_CONTENT"
    echo "$END_MARKER"
} | sudo tee -a "$EXPORTS_FILE" > /dev/null

sudo rm "$TEMP_EXPORTS_CONF"

# Step 8: Apply NFS export changes
print_step "Applying NFS export changes"
echo "Test: Running exportfs -ra to apply changes from $EXPORTS_FILE."
# exportfs -ra can sometimes be verbose on stderr even if successful, or show nothing on success
if sudo exportfs -ra; then
    print_info "NFS exports reloaded successfully."
    print_info "Current exports (sudo exportfs -v):"
    sudo exportfs -v
else
    # exportfs -ra often exits 0 even on minor syntax errors in /etc/exports that prevent an export
    # A better check is to see if our specific path is now exported.
    print_warn "exportfs -ra command executed. Checking if the share is actively exported."
    if sudo exportfs -s | grep -q "$SHARE_PATH_ABS.*$CLIENT_SPEC"; then
         print_info "Share $SHARE_PATH_ABS for $CLIENT_SPEC appears to be actively exported."
         print_info "Current exports (sudo exportfs -v):"
         sudo exportfs -v
    else
        print_error "Failed to verify that the share $SHARE_PATH_ABS for $CLIENT_SPEC is actively exported after 'exportfs -ra'."
        print_error "Please check $EXPORTS_FILE for syntax errors and review 'sudo exportfs -v' output."
        # exit 1; # Decided not to exit, but to warn heavily.
    fi
fi


# Step 9: Allow NFS through the firewall (if UFW or firewalld is active)
print_step "Checking and configuring firewall for NFS"
FIREWALL_CONFIGURED=false
# Check for UFW
echo "Test: Checking for UFW firewall."
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
    print_info "UFW firewall is active."
    echo "Test: Checking if UFW allows NFS (usually covers necessary ports like 2049, 111)."
    # UFW's "NFS" app profile might not always exist or be complete.
    # A more direct check could be for port 2049.
    if sudo ufw status verbose | grep -qwE "2049.*ALLOW IN|NFS.*ALLOW IN"; then # Check for port or "NFS" app
        print_info "UFW appears to already allow NFS traffic (port 2049 or NFS app profile)."
    else
        print_warn "UFW does not seem to have a rule for NFS. Attempting to add 'NFS' application profile."
        run_command "ufw allow NFS" || print_warn "Failed to add 'NFS' application profile to UFW. Trying specific ports."
        # Fallback to specific ports if "NFS" app profile fails or isn't sufficient
        if ! (sudo ufw status verbose | grep -qwE "2049.*ALLOW IN|NFS.*ALLOW IN"); then
            run_command "ufw allow 2049/tcp"
            run_command "ufw allow 2049/udp"
            run_command "ufw allow 111/tcp" # rpcbind/portmapper
            run_command "ufw allow 111/udp" # rpcbind/portmapper
        fi
        if sudo ufw status verbose | grep -qwE "2049.*ALLOW IN|NFS.*ALLOW IN"; then FIREWALL_CONFIGURED=true; fi
    fi
# Check for firewalld
elif command -v firewall-cmd >/dev/null && sudo systemctl is-active --quiet firewalld; then
    print_info "firewalld is active."
    echo "Test: Checking if firewalld allows nfs, rpc-bind, and mountd services (permanently)."
    # NFSv3 needs rpc-bind and mountd. NFSv4 typically only needs 2049.
    # The 'nfs' service in firewalld should handle this.
    if sudo firewall-cmd --query-service=nfs --permanent 2>/dev/null; then
        print_info "firewalld already has 'nfs' service enabled permanently."
    else
        print_warn "firewalld does not have 'nfs' service enabled permanently. Attempting to add and reload."
        run_command "firewall-cmd --permanent --add-service=nfs"
        run_command "firewall-cmd --reload" || print_error "Failed to reload firewalld."
        if sudo firewall-cmd --query-service=nfs --permanent 2>/dev/null; then FIREWALL_CONFIGURED=true; fi
    fi
else
    print_info "No active UFW or firewalld detected. Skipping firewall configuration."
    print_warn "If you are using a different firewall, ensure ports for NFS (e.g., TCP/UDP 2049, TCP/UDP 111) are open."
fi
if [ "$FIREWALL_CONFIGURED" = "true" ]; then print_info "Firewall rule for NFS applied/verified."; fi

# Step 10: Summary and Connection Tips
print_step "NFS Export Setup Summary and Connection Tips"
SERVER_IP=$(hostname -I | awk '{print $1}') # Get primary IP
echo -e "${GREEN}NFS export for path '${SHARE_PATH_ABS}' setup processing complete!${NC}"
echo -e "--------------------------------------------------"
echo -e "  Exported Path:      $SHARE_PATH_ABS"
echo -e "  Server IP Address:  $SERVER_IP (likely, verify with 'ip a')"
echo -e "  Allowed Clients:    $CLIENT_SPEC"
echo -e "  NFS Options:        $OPTIONS_STRING"
echo -e "  Directory Owner:    $CURRENT_INVOKING_USER:$CURRENT_INVOKING_USER_GROUP"
echo -e "  Directory Perms:    $(stat -c "%a (%A)" "$SHARE_PATH_ABS")"
echo -e "--------------------------------------------------"
echo -e ""
echo -e "${YELLOW}How to connect from a client machine:${NC}"
echo -e "  1. ${GREEN}Install NFS client utilities${NC} (if not already installed):"
echo -e "     On Debian/Ubuntu clients: sudo apt-get update && sudo apt-get install nfs-common"
echo -e "     On RHEL/CentOS/Fedora clients: sudo yum install nfs-utils or sudo dnf install nfs-utils"
echo -e ""
echo -e "  2. ${GREEN}Verify server exports${NC} (from client):"
echo -e "     showmount -e $SERVER_IP"
echo -e "     (You should see '$SHARE_PATH_ABS' listed for '$CLIENT_SPEC')"
echo -e ""
echo -e "  3. ${GREEN}Create a mount point${NC} on the client:"
echo -e "     sudo mkdir -p /mnt/nfs_$(basename "$SHARE_PATH_ABS")"
echo -e ""
echo -e "  4. ${GREEN}Mount the NFS share${NC} on the client:"
echo -e "     sudo mount -t nfs $SERVER_IP:\"$SHARE_PATH_ABS\" /mnt/nfs_$(basename "$SHARE_PATH_ABS")"
echo -e "     (For specific NFS versions or options on client, use -o, e.g., -o vers=4.2,rsize=1048576,wsize=1048576)"
echo -e ""
echo -e "  5. ${GREEN}To make it permanent (mount on boot)${NC}, add to /etc/fstab on the client:"
echo -e "     $SERVER_IP:\"$SHARE_PATH_ABS\" /mnt/nfs_$(basename "$SHARE_PATH_ABS") nfs defaults,auto 0 0"
echo -e "     (Adjust 'defaults' with specific options like vers=4.2,rsize,wsize,hard,intr etc. as needed)"
echo -e ""
echo -e "${YELLOW}Important NFS Considerations:${NC}"
echo -e "  - ${RED}UID/GID Matching:${NC} NFS typically maps users based on their User ID (UID) and Group ID (GID)."
echo -e "    For a user on a client to have the expected permissions (especially write access) on the share,"
echo -e "    their UID/GID on the client ${GREEN}MUST MATCH${NC} a UID/GID on the server that has those permissions"
echo -e "    to the actual directory '$SHARE_PATH_ABS'."
echo -e "  - ${RED}Root Squash:${NC} By default ('root_squash', which this script defaults to unless '--no-root-squash' is used),"
echo -e "    if the root user on the client tries to access the share, it's mapped to a non-privileged user"
echo -e "    on the server (usually 'nobody:nogroup'). This is a security feature."
echo -e "    If you used '--no-root-squash', client root has root privileges on the share. ${RED}USE WITH EXTREME CAUTION.${NC}"
echo -e "  - ${RED}all_squash:${NC} If you want all client users to be mapped to a specific anonymous user on the server,"
echo -e "    use '-o all_squash,anonuid=<uid>,anongid=<gid>' and ensure the directory '$SHARE_PATH_ABS'"
echo -e "    is owned by that <uid>:<gid> on the server and has appropriate permissions."
echo -e "  - ${RED}Firewall:${NC} Ensure your firewall on the server allows NFS traffic (ports 2049, 111 for rpcbind)."
echo -e "  - ${RED}Performance:${NC} NFS performance can be tuned with options like 'rsize', 'wsize', 'async' (this script"
echo -e "    defaults to 'sync' for data integrity on writes; 'async' can be faster but slightly riskier on power loss)."
echo -e "  - ${RED}NFS Versions:${NC} Clients might try to negotiate different NFS versions (v3, v4.0, v4.1, v4.2). Ensure compatibility."
echo -e ""
print_info "Script finished."

exit 0
