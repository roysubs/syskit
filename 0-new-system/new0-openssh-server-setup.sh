#!/bin/bash
# Author: Roy Wiseman 2025-04

# Combined OpenSSH Server Setup Script
# Installs, configures, and verifies OpenSSH server.
# Supports native Linux and WSL (Windows Subsystem for Linux).
# Aims for transparency by showing commands being run.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration & Colors ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RED="\033[1;31m"
RESET="\033[0m"

SCRIPT_NAME=$(basename "$0")

# --- Helper Functions ---
log_info() {
  echo -e "${BLUE}INFO:${RESET} $1"
}

log_success() {
  echo -e "${GREEN}✅ SUCCESS:${RESET} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠️ WARNING:${RESET} $1"
}

log_error() {
  echo -e "${RED}❌ ERROR:${RESET} $1" >&2
}

# For commands that change state or perform significant actions
run_command() {
  echo -e "${GREEN}🚀 EXECUTING:${RESET} $@"
  "$@"
}

# For displaying commands used in checks or for gathering info
show_check_command() {
  echo -e "${GREEN}🔍 CHECKING WITH:${RESET} $1"
}

show_info_command() {
  echo -e "${GREEN}⚙️ GETTING INFO WITH:${RESET} $1"
}


# Auto-elevate with sudo if not root
if [ "$(id -u)" -ne 0 ]; then
  log_warning "Elevation required; rerunning with sudo..."
  sudo bash "$0" "$@"
  exit $?
fi

# --- System Detection ---
is_wsl() {
  # This check is internal to a helper, direct logging might be too verbose.
  # The script will log "Detected WSL environment" when this is true.
  grep -qiE 'microsoft|wsl' /proc/version
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt";
  elif command -v dnf >/dev/null 2>&1; then echo "dnf";
  elif command -v yum >/dev/null 2>&1; then echo "yum";
  elif command -v pacman >/dev/null 2>&1; then echo "pacman";
  else echo "unknown"; fi
}

# --- SSH Installation ---
prompt_install_ssh() {
  local pm="$1"
  read -r -p "OpenSSH server (sshd) is not installed. Install it now? [Y/n]: " ans
  ans=${ans:-Y} 
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    log_info "Installing OpenSSH server using $pm..."
    case "$pm" in
      apt)
        if [ ! -f /var/cache/apt/pkgcache.bin ] || find /var/cache/apt/pkgcache.bin -mtime +2 -print -quit | grep -q .; then
          run_command apt-get update # Already uses run_command
        else
          log_info "APT cache is recent, skipping update."
        fi
        run_command apt-get install -y openssh-server openssh-client # Already uses run_command
        ;;
      dnf)
        run_command dnf install -y openssh-server openssh-clients # Already uses run_command
        ;;
      yum)
        run_command yum install -y openssh-server openssh-clients # Already uses run_command
        ;;
      pacman)
        run_command pacman -Sy --noconfirm openssh # Already uses run_command
        ;;
      *)
        log_error "Unsupported package manager: $pm. Please install openssh-server manually."
        exit 1
        ;;
    esac
    log_success "OpenSSH server installed."
  else
    log_warning "Aborting: OpenSSH server not installed."
    exit 1
  fi
}

# --- Main Logic ---
log_info "Starting OpenSSH server setup..."

log_info "Checking if OpenSSH server (sshd) is already installed..."
show_check_command "command -v sshd"
if ! command -v sshd >/dev/null 2>&1; then
  log_info "Detecting package manager..." # Context for detect_package_manager call
  PKG_MANAGER=$(detect_package_manager)
  if [ "$PKG_MANAGER" == "unknown" ]; then
    log_error "Could not detect package manager. Please install 'sshd' manually."
    exit 1
  fi
  prompt_install_ssh "$PKG_MANAGER"
else
  log_success "OpenSSH server (sshd) is already installed."
fi

log_info "Setting up OpenSSH server..."

SSH_PORT="22" 

if is_wsl; then
  log_warning "Detected WSL environment (via /proc/version check)."
  log_info "Systemd is not fully available in WSL. Configuring SSH for manual start."

  SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
  if [ -f "$SSHD_CONFIG_FILE" ]; then
    local wsl_port_check_cmd="grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' '$SSHD_CONFIG_FILE'"
    show_check_command "$wsl_port_check_cmd"
    EXPLICIT_PORT_LINE=$(eval "$wsl_port_check_cmd" || true) # Capture output
    if [ -n "$EXPLICIT_PORT_LINE" ]; then
        SSH_PORT=$(echo "$EXPLICIT_PORT_LINE" | awk '{print $2}')
        log_info "WSL: Explicit port $SSH_PORT found in $SSHD_CONFIG_FILE."
    else
        log_info "WSL: No explicit port found in $SSHD_CONFIG_FILE. Using default $SSH_PORT."
    fi

    local pam_check_cmd_display="grep '^[[:space:]]*UsePAM[[:space:]]\\+yes' '$SSHD_CONFIG_FILE'"
    local pam_check_cmd_exec="grep -q '^[[:space:]]*UsePAM[[:space:]]\\+yes' '$SSHD_CONFIG_FILE'"
    show_check_command "$pam_check_cmd_display" # Show the non-quiet version for clarity
    if eval "$pam_check_cmd_exec"; then # Execute the quiet version for logic
      log_info "Disabling 'UsePAM yes' in $SSHD_CONFIG_FILE for WSL compatibility..."
      run_command sed -i 's/^[[:space:]]*UsePAM[[:space:]]\+yes/UsePAM no/' "$SSHD_CONFIG_FILE"
      log_success "PAM disabled in sshd_config."
    else
      log_info "'UsePAM yes' not found or already disabled in $SSHD_CONFIG_FILE."
    fi
  else
    log_warning "$SSHD_CONFIG_FILE not found. Skipping PAM check and port detection for WSL."
  fi

  if [ ! -d /var/run/sshd ]; then
    log_info "Creating /var/run/sshd directory."
    run_command mkdir -p /var/run/sshd
    run_command chmod 755 /var/run/sshd
  fi
  
  show_check_command "pgrep -x sshd"
  if pgrep -x sshd > /dev/null; then
    log_info "Attempting to stop existing sshd processes..."
    run_command killall sshd || true # Allow failure if no process found
    sleep 1
  fi

  if [ ! -x /usr/sbin/sshd ]; then
    log_error "/usr/sbin/sshd not found or not executable. Cannot start SSH server."
    exit 1
  fi

  log_info "Starting sshd manually on port $SSH_PORT (from config or default)..."
  echo -e "${GREEN}🚀 EXECUTING:${RESET} /usr/sbin/sshd" # Manual log for direct execution
  if /usr/sbin/sshd; then
    log_success "sshd started manually. It should use port $SSH_PORT if configured in $SSHD_CONFIG_FILE."
    log_warning "If you restart WSL, you'll need to run: sudo /usr/sbin/sshd"
  else
    log_error "Failed to start sshd manually."
    exit 1
  fi
else
  # Native Linux — use systemctl
  log_info "Detected native Linux environment (not WSL)."
  
  SERVICE_NAME=""
  CANDIDATE_SERVICES_FOR_STATUS=("ssh" "sshd") 
  log_info "Attempting to determine canonical SSH service name..."
  for candidate_base in "${CANDIDATE_SERVICES_FOR_STATUS[@]}"; do
    candidate_service="${candidate_base}.service"
    show_check_command "systemctl status $candidate_service"
    status_output=$(systemctl status "$candidate_service" 2>/dev/null || true) 
    if echo "$status_output" | grep -q "Loaded: loaded"; then
      loaded_line=$(echo "$status_output" | grep "Loaded: loaded")
      service_path=$(echo "$loaded_line" | sed -n 's/.*Loaded: loaded (\([^ ;]*\).*/\1/p')
      if [ -n "$service_path" ]; then
        SERVICE_NAME=$(basename "${service_path%.service}") 
        log_info "Detected SSH service file: $service_path, using service name for management: $SERVICE_NAME"
        break 
      fi
    fi
  done

  if [ -z "$SERVICE_NAME" ]; then
    log_warning "Could not determine canonical SSH service name from 'systemctl status'. Falling back..."
    show_check_command "systemctl list-unit-files | grep -q '^ssh\\.service'"
    if systemctl list-unit-files | grep -q '^ssh\.service'; then
        SERVICE_NAME="ssh"
        log_info "Falling back to 'ssh' based on list-unit-files."
    else
        show_check_command "systemctl list-unit-files | grep -q '^sshd\\.service'"
        if systemctl list-unit-files | grep -q '^sshd\.service'; then
            SERVICE_NAME="sshd"
            log_info "Falling back to 'sshd' based on list-unit-files."
        else
            log_error "Neither ssh.service nor sshd.service found via list-unit-files. SSH control will likely fail."
            SERVICE_NAME="ssh" # Last resort
        fi
    fi
  fi
  
  log_info "Ensuring $SERVICE_NAME service is enabled and started using systemctl..."
  run_command systemctl enable "$SERVICE_NAME" 
  run_command systemctl restart "$SERVICE_NAME"
  log_success "$SERVICE_NAME service enabled and (re)started via systemd."

  log_info "Displaying $SERVICE_NAME service status (last 5 lines):"
  echo -e "${GREEN}🚀 EXECUTING:${RESET} systemctl status \"$SERVICE_NAME\" --no-pager --lines=5" # Manual log for this specific status display
  if ! systemctl status "$SERVICE_NAME" --no-pager --lines=5; then
    log_warning "Could not retrieve status for $SERVICE_NAME. It might have failed to start."
  fi
fi

# --- Verification ---
log_info "Verifying sshd_config settings..."
CONFIG_FILE="/etc/ssh/sshd_config"

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_error "sshd_config not found at $CONFIG_FILE. SSH setup might be incomplete."
else
  port_check_cmd="grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' '$CONFIG_FILE'"
  show_check_command "$port_check_cmd"
  PORT_LINE_MATCH=$(eval "$port_check_cmd" || true) # Capture output

  if [ -n "$PORT_LINE_MATCH" ]; then
    CONFIG_PORT_VALUE=$(echo "$PORT_LINE_MATCH" | awk '{print $2}')
    if [[ "$CONFIG_PORT_VALUE" =~ ^[0-9]+$ ]]; then
        SSH_PORT="$CONFIG_PORT_VALUE"
        PORT_LINE_INFO="$PORT_LINE_MATCH (Effective Port: $SSH_PORT)"
    else
        PORT_LINE_INFO="$PORT_LINE_MATCH (Error parsing port, using default $SSH_PORT)"
    fi
  else
    PORT_LINE_INFO="Port not explicitly set in $CONFIG_FILE (defaults to $SSH_PORT)"
  fi
  log_info "$PORT_LINE_INFO"
fi

log_info "Checking if port $SSH_PORT is listening..."
# For complex piped commands in 'if', show the intent and then execute
listen_check_display="ss -tuln | grep -E '(^|[^0-9]):$SSH_PORT([[:space:]]|$)'"
listen_check_exec="ss -tuln | grep -qE '(^|[^0-9]):$SSH_PORT([[:space:]]|$)'"
show_check_command "$listen_check_display"
if eval "$listen_check_exec"; then
  log_success "Port $SSH_PORT appears to be open and listening."
else
  log_warning "Port $SSH_PORT does NOT appear to be listening based on the check above."
  if ! is_wsl; then
    log_info "Consider: sudo systemctl status $SERVICE_NAME ; sudo journalctl -u $SERVICE_NAME -n 20"
  else
    log_info "Consider running sshd in debug mode: sudo /usr/sbin/sshd -d"
  fi
fi

log_info "Testing connectivity with netcat to localhost:$SSH_PORT..."
show_check_command "command -v nc"
if command -v nc >/dev/null 2>&1; then
  nc_cmd="nc -zv 127.0.0.1 $SSH_PORT"
  show_check_command "$nc_cmd"
  if nc -zv 127.0.0.1 "$SSH_PORT" &>/dev/null; then # Output of nc is suppressed here for script logic
    log_success "Port $SSH_PORT is reachable via netcat on localhost."
  else
    log_warning "Port $SSH_PORT not reachable via nc on localhost (127.0.0.1)."
  fi
else
  log_warning "netcat (nc) not found. Skipping localhost connectivity test."
fi

# --- Summary ---
USER_TO_CONNECT=$( [ -n "$SUDO_USER" ] && echo "$SUDO_USER" || whoami ) # Internal, no command to show
IP_ADDRESS=""

log_info "Attempting to determine IP address..."
ip_cmd_hostname_i="hostname -I | awk '{print \$1}'" # awk's $1 needs escape for echo
show_info_command "$ip_cmd_hostname_i"
if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
fi

if [ -z "$IP_ADDRESS" ]; then
    log_info "Fallback: Attempting to determine IP address using 'ip' command..."
    ip_cmd_ip_addr="ip -4 addr show scope global | grep -oP 'inet \\K[\\d.]+' | head -n 1" # \K needs double escape for echo
    show_info_command "$ip_cmd_ip_addr"
    if command -v ip >/dev/null 2>&1; then
        IP_ADDRESS=$(ip -4 addr show scope global | grep -oP 'inet \K[\d.]+' | head -n 1 || true) # Ensure no exit on grep fail
    fi
fi

if [ -z "$IP_ADDRESS" ]; then
    log_warning "Could not automatically determine IP address."
    IP_ADDRESS="<your_ip_address>"
fi


echo ""
log_success "OpenSSH server setup process complete."
if [ "$SSH_PORT" != "22" ]; then
  echo -e "${BLUE}➡️  Access this system with:${RESET} ssh -p $SSH_PORT $USER_TO_CONNECT@$IP_ADDRESS"
else
  echo -e "${BLUE}➡️  Access this system with:${RESET} ssh $USER_TO_CONNECT@$IP_ADDRESS"
fi

if is_wsl; then
  log_warning "Remember: In WSL, sshd was started manually. It will NOT persist across WSL restarts."
  log_warning "To start it again after a WSL restart, run: sudo /usr/sbin/sshd"
fi

echo ""
log_info "📋 FINAL NOTES & FIREWALL (if applicable):"
echo ""
echo -e "${YELLOW}💡 UFW (Debian/Ubuntu-based):${RESET}"
echo "   To allow SSH (port $SSH_PORT): sudo ufw allow $SSH_PORT/tcp"
echo "   Then enable UFW (if not already): sudo ufw enable"
echo "   Check status: sudo ufw status"
echo ""
echo -e "${YELLOW}💡 firewalld (Fedora/CentOS/RHEL-based):${RESET}"
echo "   If using standard SSH service (port 22) and it's not $SSH_PORT: sudo firewall-cmd --permanent --remove-service=ssh"
echo "   To allow SSH on port $SSH_PORT: sudo firewall-cmd --permanent --add-port=$SSH_PORT/tcp"
echo "   (Or if $SSH_PORT is 22 and you want to use the service definition: sudo firewall-cmd --permanent --add-service=ssh)"
echo "   Reload firewall: sudo firewall-cmd --reload"
echo "   Check active rules: sudo firewall-cmd --list-all"
echo ""
echo -e "${YELLOW}💡 iptables (Manual configuration):${RESET}"
echo "   To allow incoming SSH on port $SSH_PORT: sudo iptables -A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"
echo "   To allow outgoing established SSH: sudo iptables -A OUTPUT -p tcp --sport $SSH_PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT"
echo ""
log_info "Setup script finished."
