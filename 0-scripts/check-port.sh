#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script to check port status and provide network information

# --- Configuration ---
NC_TIMEOUT=2 # Timeout in seconds for nc check

# --- Color Definitions ---
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

# --- Functions ---

# Function to display usage instructions
show_usage() {
  echo -e "${YELLOW}Usage: $0 <PORT_NUMBER>${NC}"
  echo -e "${YELLOW}       $0 -h | --help${NC}"
  echo
  echo -e "${YELLOW}Description:${NC}"
  echo "  This script first provides general information about network ports and firewall status."
  echo "  Then, it checks if a specific port is currently in use (listening) on the local machine"
  echo "  using 'ss', 'netstat', 'lsof', and 'nc'."
  echo
  echo -e "${YELLOW}Information Provided First:${NC}"
  echo "  - General Port Tips: Well-known ranges, TCP/UDP, security best practices."
  echo "  - Firewall Check: Detects ufw/firewalld status, provides iptables commands."
  echo
  echo -e "${YELLOW}Checks Performed Last (for the specified port):${NC}"
  echo "  1. ss: Checks for listening TCP and UDP sockets."
  echo "  2. netstat: Checks for listening TCP and UDP sockets (legacy)."
  echo "  3. lsof: Lists processes using the port (sudo often required)."
  echo "  4. nc: Attempts a quick TCP connection test to localhost."
  echo
  echo -e "${YELLOW}Example:${NC}"
  echo -e "  ${GREEN}$0 80${NC}   # Provides general info, firewall status, then checks port 80"
  echo
}

# Function to check firewall status
check_firewall_status() {
  echo -e "${YELLOW}--- Firewall Status ---${NC}"
  ACTIVE_FIREWALL="None detected" # ufw, firewalld, or iptables-focused

  # --- UFW Check ---
  UFW_CMD=""
  # Try direct command first (if in PATH and runnable without sudo for basic version/help)
  if command -v ufw >/dev/null 2>&1; then
    # Check if 'ufw status' can be run without sudo or if it explicitly demands sudo
    if ufw status >/dev/null 2>&1; then
      UFW_CMD="ufw" # Can be run without sudo for status
    elif ufw status 2>&1 | grep -qiE "must be root|permission denied"; then
      if command -v sudo >/dev/null && sudo -n true >/dev/null 2>&1; then
        if sudo ufw status >/dev/null 2>&1; then # Check if sudo ufw status works non-interactively
          UFW_CMD="sudo ufw"
          echo -e "${YELLOW}[INFO]${NC} 'ufw' status requires root. Will use 'sudo ufw'."
        else # Sudo ufw status does not work non-interactively, might need password
          UFW_CMD="sudo ufw" # Assume it needs sudo; will prompt if password required by sudoers
          echo -e "${YELLOW}[INFO]${NC} 'ufw' status requires root. Will use 'sudo ufw' (may prompt for password)."
        fi
      else # Needs root, sudo not available or not usable non-interactively
         echo -e "${YELLOW}[INFO]${NC} 'ufw' found, but requires root privileges for status, and 'sudo' is not available or configured for non-interactive use."
      fi
    else # ufw in path, 'ufw status' fails for other reasons or doesn't say "must be root"
      UFW_CMD="ufw" # Try anyway, might be an odd setup
       echo -e "${YELLOW}[WARN]${NC} 'ufw' found, but its behavior with 'ufw status' is unusual. Attempting checks."
    fi
  elif command -v sudo >/dev/null && sudo -n true >/dev/null 2>&1 && sudo ufw --version >/dev/null 2>&1; then
    # ufw not in PATH for user, but 'sudo ufw' works
    UFW_CMD="sudo ufw"
    echo -e "${YELLOW}[INFO]${NC} 'ufw' not in user's PATH, but accessible via 'sudo'. Will use 'sudo ufw'."
  fi

  if [ -n "$UFW_CMD" ]; then
    # Add 2>/dev/null to suppress "Firewall not enabled" messages from grep if ufw is inactive
    UFW_STATUS_OUTPUT=$($UFW_CMD status 2>/dev/null)
    if echo "$UFW_STATUS_OUTPUT" | grep -qw "Status: active"; then
      ACTIVE_FIREWALL="ufw"
      echo -e "${YELLOW}[INFO]${NC} ufw (Uncomplicated Firewall) is ${GREEN}active${NC} (using '$UFW_CMD')."
      # Show verbose status (output comes from ufw, not colorized by this script)
      $UFW_CMD status verbose
      echo -e "${YELLOW}[INFO]${NC} Checking ufw rules for port $PORT..."
      # Check specific port rules
      # The $UFW_CMD status output is already captured in UFW_STATUS_OUTPUT or can be re-run
      # For more reliable rule check, use the numbered status
      RULE_CHECK_OUTPUT=$($UFW_CMD status numbered 2>/dev/null)
      if echo "$RULE_CHECK_OUTPUT" | grep -Eq "\[[ 0-9]+\] $PORT([ /]|$).*ALLOW IN"; then
         echo -e "${YELLOW}[INFO]${NC} Port $PORT appears to be explicitly ${GREEN}ALLOWED IN${NC} by ufw."
      elif echo "$RULE_CHECK_OUTPUT" | grep -Eq "\[[ 0-9]+\] $PORT([ /]|$).*DENY IN"; then
         echo -e "${YELLOW}[INFO]${NC} Port $PORT appears to be explicitly ${GREEN}DENIED IN${NC} by ufw."
      elif echo "$RULE_CHECK_OUTPUT" | grep -Eq "\[[ 0-9]+\] $PORT([ /]|$).*REJECT IN"; then
         echo -e "${YELLOW}[INFO]${NC} Port $PORT appears to be explicitly ${GREEN}REJECTED IN${NC} by ufw."
      else
         # Check default policies if no specific rule found
         DEFAULT_INCOMING=$(echo "$UFW_STATUS_OUTPUT" | grep "Default:" | grep "incoming" | awk '{print $2}')
         echo -e "${YELLOW}[INFO]${NC} No specific ufw rule found for port $PORT."
         echo -e "${YELLOW}[INFO]${NC} Default incoming policy: $DEFAULT_INCOMING."
         if [[ "$DEFAULT_INCOMING" == "allow" ]]; then
            echo -e "${YELLOW}[INFO]${NC} Port $PORT may be allowed due to default policy."
         elif [[ "$DEFAULT_INCOMING" == "deny" || "$DEFAULT_INCOMING" == "reject" ]]; then
             echo -e "${YELLOW}[INFO]${NC} Port $PORT may be blocked due to default policy."
         fi
      fi
    else
      echo -e "${YELLOW}[INFO]${NC} ufw does not appear to be active (checked with '$UFW_CMD')."
      # Optionally display the raw status output for debugging
      # echo -e "Output of '$UFW_CMD status':\n$($UFW_CMD status 2>&1)"
    fi
  else
    echo -e "${YELLOW}[INFO]${NC} ufw command not found or not usable."
  fi
  echo

  # --- firewalld Check ---
  # Check for firewalld (if ufw is not the primary one or not found)
  if [ "$ACTIVE_FIREWALL" != "ufw" ] && command -v firewall-cmd > /dev/null; then
    if systemctl is-active --quiet firewalld; then
      ACTIVE_FIREWALL="firewalld"
      echo -e "${YELLOW}[INFO]${NC} firewalld is ${GREEN}active${NC}."
      echo -e "State: $(firewall-cmd --state)"
      DEFAULT_ZONE=$(firewall-cmd --get-default-zone 2>/dev/null)
      if [ -n "$DEFAULT_ZONE" ]; then
        echo -e "${YELLOW}[INFO]${NC} Default firewalld zone: $DEFAULT_ZONE"
        echo -e "${YELLOW}[INFO]${NC} Checking firewalld rules for port $PORT in zone '$DEFAULT_ZONE'..."
        # Check for TCP
        if firewall-cmd --query-port="$PORT/tcp" --zone="$DEFAULT_ZONE" --quiet; then
          echo -e "${YELLOW}[INFO]${NC} Port $PORT/tcp is ${GREEN}allowed${NC} in firewalld zone: $DEFAULT_ZONE."
        # Check for UDP
        elif firewall-cmd --query-port="$PORT/udp" --zone="$DEFAULT_ZONE" --quiet; then
          echo -e "${YELLOW}[INFO]${NC} Port $PORT/udp is ${GREEN}allowed${NC} in firewalld zone: $DEFAULT_ZONE."
        else
          echo -e "${YELLOW}[INFO]${NC} Port $PORT does not appear to be explicitly allowed (TCP or UDP) in firewalld zone: $DEFAULT_ZONE."
          echo -e "       (Check with: ${GREEN}firewall-cmd --list-all --zone=$DEFAULT_ZONE${NC} or other zones)"
        fi
      else
        echo -e "${YELLOW}[WARN]${NC} Could not determine default firewalld zone."
      fi
    else
      echo -e "${YELLOW}[INFO]${NC} firewalld is installed but not active."
    fi
  elif [ "$ACTIVE_FIREWALL" != "ufw" ]; then # Only say this if ufw wasn't active
    echo -e "${YELLOW}[INFO]${NC} firewalld command not found or firewalld not managed by systemd."
  fi
  echo

  # --- iptables Information ---
  if [ "$ACTIVE_FIREWALL" = "None detected" ]; then # If neither ufw nor firewalld seem to be managing things
    echo -e "${YELLOW}[INFO]${NC} No high-level firewall management tool (ufw, firewalld) detected as active."
    echo -e "       You might be using iptables directly, or no firewall is active."
  fi
  echo -e "${YELLOW}[INFO]${NC} To inspect raw ${GREEN}iptables${NC} rules (these can be complex):"
  echo -e "  ${GREEN}sudo iptables -L -n -v${NC}           # List all IPv4 rules for all chains"
  echo -e "  ${GREEN}sudo ip6tables -L -n -v${NC}          # List all IPv6 rules"
  echo -e "  ${GREEN}sudo iptables -L INPUT -n -v${NC}     # List IPv4 rules for the INPUT chain"
  echo -e "  To check for a specific port (e.g., $PORT) in IPv4 iptables INPUT chain:"
  echo -e "  ${GREEN}sudo iptables -L INPUT -n -v --line-numbers | grep -E '(:${PORT} |dpt:${PORT}( |$))'${NC}"
  echo
}

# Function to provide general port tips
general_port_tips() {
  echo -e "${YELLOW}--- General Port Information & Tips ---${NC}"
  echo -e "${YELLOW}[INFO]${NC} Port Number Ranges:"
  echo "  - Well-known ports (0-1023): Reserved for common services (e.g., 80 HTTP, 443 HTTPS, 22 SSH). Root privileges to bind."
  echo "  - Registered ports (1024-49151): For specific applications by software vendors."
  echo "  - Dynamic/Private ports (49152-65535): For temporary or private services."
  echo
  echo -e "${YELLOW}[INFO]${NC} TCP vs. UDP:"
  echo "  - TCP (Transmission Control Protocol): Connection-oriented, reliable, ordered (e.g., HTTP, FTP, SSH)."
  echo "  - UDP (User Datagram Protocol): Connectionless, faster, less reliable, no guaranteed order (e.g., DNS, DHCP, VoIP)."
  echo
  echo -e "${YELLOW}[INFO]${NC} Security Best Practices:"
  echo "  - Minimize Open Ports: Only open what's necessary."
  echo "  - Use a Firewall: Control traffic with ufw, firewalld, or iptables. Deny by default."
  echo "  - Regular Audits: Periodically review open ports and services."
  echo "  - Software Updates: Patch vulnerabilities in listening services."
  echo
  echo -e "${YELLOW}[TIP]${NC} If a port is 'free' (script output below) but you expect a service:"
  echo -e "  1. Service running? Try: '${GREEN}systemctl status <service_name>${NC}' or '${GREEN}ps aux | grep <process_name>${NC}'"
  echo "  2. Service configuration correct for port and IP (e.g., 0.0.0.0 or :: for all interfaces)?"
  echo -e "  3. Service logs for errors? Try: '${GREEN}journalctl -u <service_name>${NC}' or check /var/log/."
  echo
  echo -e "${YELLOW}[TIP]${NC} If a port is 'in use' (script output below) and you don't know by what:"
  echo -e "  - The '${GREEN}sudo lsof -i :$PORT${NC}' command (run by this script) is effective."
  echo -e "  - '${GREEN}sudo ss -tulnp | grep ':${PORT}\\b'${NC}' or '${GREEN}sudo netstat -tulnp | grep ':${PORT}\\b'${NC}' also show PID/name."
  echo
}

# --- Main Script ---

# Check for help flag or no arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
  show_usage
  exit 0
fi

# Validate if the input is a number
if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 0 ] || [ "$1" -gt 65535 ]; then
  echo -e "${YELLOW}Error: Port must be a number between 0 and 65535.${NC}"
  show_usage
  exit 1
fi

PORT="$1"

# --- Information Sections (Displayed First as per request) ---
general_port_tips "$PORT" # Pass PORT for context in tips
check_firewall_status "$PORT" # Pass PORT for specific firewall rule hints

# --- Port Specific Checks (Displayed Last as per request) ---
echo -e "${YELLOW}--- Checking Specific Port $PORT Status (Listening) ---${NC}"
echo

# 1. Check with ss
echo -e "${YELLOW}[INFO]${NC} Checking with 'ss' utility for port $PORT..."
echo -e "Command: ${GREEN}ss -tuln | grep -E ':${PORT}\\b'${NC}"
SS_LISTEN_OUTPUT=$(ss -tuln | grep -E ":${PORT}\b")
if [ -n "$SS_LISTEN_OUTPUT" ]; then
  echo -e "Status: Port $PORT is ${GREEN}IN USE${NC} (listening according to ss)."
  echo "$SS_LISTEN_OUTPUT"
  echo -e "Details with process info (Command: ${GREEN}sudo ss -tulnp | grep ':${PORT}\\b'${NC}):"
  sudo ss -tulnp | grep -E ":${PORT}\b" --color=always
else
  echo -e "Status: Port $PORT is ${GREEN}FREE${NC} (not listening according to ss)."
fi
echo
# Explanation: ss -t(TCP) -u(UDP) -l(listening) -n(numeric) -p(processes)

# 2. Check with netstat (legacy, but good for cross-check)
echo -e "${YELLOW}[INFO]${NC} Checking with 'netstat' utility for port $PORT..."
if command -v netstat > /dev/null; then
  echo -e "Command: ${GREEN}netstat -tuln | grep -E ':${PORT}\\b'${NC}"
  NETSTAT_LISTEN_OUTPUT=$(netstat -tuln | grep -E ":${PORT}\b")
  if [ -n "$NETSTAT_LISTEN_OUTPUT" ]; then
    echo -e "Status: Port $PORT is ${GREEN}IN USE${NC} (listening according to netstat)."
    echo "$NETSTAT_LISTEN_OUTPUT"
    echo -e "Details with process info (Command: ${GREEN}sudo netstat -tulnp | grep ':${PORT}\\b'${NC}):"
    sudo netstat -tulnp | grep -E ":${PORT}\b" --color=always
  else
    echo -e "Status: Port $PORT is ${GREEN}FREE${NC} (not listening according to netstat)."
  fi
else
  echo -e "${YELLOW}[WARN]${NC} 'netstat' command not found. Skipping this check."
fi
echo
# Explanation: netstat -t(TCP) -u(UDP) -l(listening) -n(numeric) -p(processes)

# 3. Check with lsof
echo -e "${YELLOW}[INFO]${NC} Checking with 'lsof' utility for port $PORT (may require sudo for full details)..."
echo -e "Command: ${GREEN}sudo lsof -i :$PORT -P -n${NC}" # -P: inhibits port name conversion, -n: inhibits host name conversion
LSOF_OUTPUT=$(sudo lsof -i ":$PORT" -P -n 2>/dev/null) # Capture stderr to /dev/null
if [ -n "$LSOF_OUTPUT" ]; then
  echo -e "Status: Port $PORT is ${GREEN}IN USE${NC} (according to lsof)."
  echo "Details:"
  echo "$LSOF_OUTPUT" # This output is from lsof directly
else
  # Verify exit status as well, lsof exits 0 if files are listed, 1 otherwise
  sudo lsof -i ":$PORT" -P -n > /dev/null 2>&1
  if [ $? -eq 0 ]; then # Should have been caught by -n "$LSOF_OUTPUT" but as a fallback
    echo -e "Status: Port $PORT is ${GREEN}IN USE${NC} (lsof found it, but no output captured - check permissions or run manually)."
  else
    echo -e "Status: Port $PORT is ${GREEN}FREE${NC} (according to lsof)."
  fi
fi
echo

# 4. Attempt a basic connection test with nc (Netcat) to localhost
echo -e "${YELLOW}[INFO]${NC} Attempting a quick TCP connection test to ${GREEN}localhost:$PORT${NC} with 'nc'..."
if command -v nc > /dev/null; then
  echo -e "Command (TCP): ${GREEN}nc -z -v -w $NC_TIMEOUT localhost $PORT${NC}"
  # For TCP, nc -z returns 0 on success, non-0 on failure. Output often goes to stderr.
  if nc -z -w $NC_TIMEOUT localhost "$PORT" >/dev/null 2>&1; then
    echo -e "Status (TCP Connect): Port $PORT is ${GREEN}OPEN${NC} and accepting TCP connections on localhost."
  else
    echo -e "Status (TCP Connect): Port $PORT is ${GREEN}CLOSED${NC} or not accepting TCP connections on localhost (or nc timeout)."
  fi
else
  echo -e "${YELLOW}[WARN]${NC} 'nc' (Netcat) command not found. Skipping connection test."
fi
echo

exit 0
