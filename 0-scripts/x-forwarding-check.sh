#!/bin/bash
# Author: Roy Wiseman 2025-05

# --- X11 Forwarding Troubleshooting Guide Script ---

# Define colors using tput for better compatibility
if tput setaf 1 &> /dev/null; then
  RED=$(tput setaf 1)    # Red
  GREEN=$(tput setaf 2)  # Green
  YELLOW=$(tput setaf 3) # Yellow
  BLUE=$(tput setaf 4)   # Blue
  BOLD=$(tput bold)      # Bold
  NC=$(tput sgr0)        # No Color
else
  # Fallback if tput is not available
  RED='\e[0;31m'
  GREEN='\e[0;32m'
  YELLOW='\e[0;33m'
  BLUE='\e[0;34m'
  BOLD='\e[1m'
  NC='\e[0m'
fi

# --- Global Placeholders (Edit if your host/user names are different) ---
host1="host1" # Replace with your remote server's hostname or IP
user1="user1" # Replace with your remote username
# ---------------------------------------------------------------------

printf "${BOLD}${BLUE}--- X11 Forwarding Troubleshooting Guide ---${NC}\n\n\
This script guides you through checking the essential points for SSH X11 forwarding.\n\
You will need to run commands and interpret their output.\n\
Replace '%s' and '%s' below with your actual hostname and username\n\
if they differ from the placeholders.\n\n\
Press Enter after performing each step and reviewing the output.\n\
------------------------------------------------------------------\n" "$host1" "$user1"
read

# --- Step 1: Verify Basic SSH Connectivity ---
printf "${BOLD}${BLUE}Step 1: Verify SSH Connectivity${NC}\n\
---------------------------------\n\
Ensure you can connect to the remote host ('%s') via SSH without issues\n\
(ignoring X forwarding for now).\n\
You already confirmed 'ssh %s@%s' connects without issue, which is good.\n\
If you ever have trouble, check hostnames, IPs, SSH port\n\
(default 22), and firewalls on both your local machine\n\
(outgoing) and %s (incoming port 22).\n\
Status: Basic SSH connection confirmed OK.\n\n\
Action: No action needed if basic connection works.\n" "$host1" "$user1" "$host1" "$host1"
printf "Press Enter to continue...\n" # Keep prompt separate for clarity
read

# --- Step 2: Check SSH Client Configuration (Your Local Machine) ---
printf "${BOLD}${BLUE}Step 2: Check SSH Client Configuration (Your Local Machine)${NC}\n\
-------------------------------------------------------------\n\
Ensure your local SSH client is configured to REQUEST X11 forwarding.\n\
This is usually enabled by default, but explicit settings can override.\n\n\
${BOLD}Expected:${NC} 'ForwardX11 yes' or 'ForwardX11Trusted yes', or no explicit\n\
mention (often defaults to yes). You need at least one of these set to 'yes'.\n\n\
${BOLD}Action:${NC} Check your SSH client config files.\n"
printf "${YELLOW}For Linux/WSL:${NC}\n"
echo "  cat ~/.ssh/config /etc/ssh/ssh_config 2>/dev/null | grep -iE 'ForwardX11|ForwardX11Trusted'"
printf "${YELLOW}For Windows (using OpenSSH client):${NC}\n\
  Check if you have a config file at C:\\Users\\YourUsername\\.ssh\\config\n\
  You can try to display it using:\n"
echo "  type C:\\Users\\YourUsername\\.ssh\\config 2>&1 | findstr /i \"ForwardX11 ForwardX11Trusted\""
printf "  (Replace 'YourUsername' with your actual Windows username)\n\
  If no file exists, defaults apply (often forwarding is enabled).\n\n\
Review the output. If you see 'no' for either, remove or change it to 'yes'.\n"
printf "Press Enter to continue after checking your local config...\n"
read

# --- Step 3: Check SSH Server Configuration (Remote Host: host1) ---
printf "${BOLD}${BLUE}Step 3: Check SSH Server Configuration on %s${NC}\n\
---------------------------------------------\n\
Ensure the remote SSH server ('sshd') is configured to ALLOW X11 forwarding.\n\
Connect to %s: ${YELLOW}ssh %s@%s${NC}\n\
Once connected to %s, run these commands:\n" "$host1" "$host1" "$user1" "$host1" "$host1"
printf "\n  echo 'Checking sshd_config on %s...'\n" "$host1"
echo "  cat /etc/ssh/sshd_config | grep -iE 'X11Forwarding|X11DisplayOffset|X11UseLocalhost|AllowTcpForwarding'"
printf "\n${BOLD}Expected output includes:${NC}\n\
  X11Forwarding yes\n\
  X11DisplayOffset 10  #(often 10, but 0 is possible)\n\
  X11UseLocalhost yes  #(SSH server listens on localhost interface for X connections)\n\
  AllowTcpForwarding yes #(Crucial! Allows SSH to forward ports)\n\n\
Your previous output showed X11UseLocalhost no. While sometimes needed, 'yes'\n\
is the standard secure configuration when using SSH's built-in authentication.\n\
Let's focus on getting it working first. Ensure AllowTcpForwarding is 'yes'.\n\n\
${BOLD}IMPORTANT:${NC} If you change /etc/ssh/sshd_config, you ${RED}MUST restart${NC} the sshd service!\n\
${BOLD}Action:${NC} Run the appropriate command on %s (using sudo):\n" "$host1"
printf "  ${YELLOW}# For systemd (most modern Linux):${NC}\n"
echo "  sudo systemctl restart sshd"
printf "  ${YELLOW}# Or for SysVinit (older systems):${NC}\n"
echo "  sudo service sshd restart"
printf "\nConfirm X11Forwarding is 'yes' and AllowTcpForwarding is 'yes'. Restart sshd if needed.\n"
printf "Press Enter to continue after checking on %s and restarting sshd...\n" "$host1"
read

# --- Step 4: Verify X Server (Xming on Windows) ---
printf "${BOLD}${BLUE}Step 4: Verify Your X Server (Xming) Configuration and Status${NC}\n\
-------------------------------------------------------------\n\
Ensure Xming is running and correctly set up, especially access control.\n\
Your error 'Authorization required...' with Xming -ac suggests it wasn't effective.\n\
This can happen due to conflicting settings or if '-ac' isn't truly active.\n\n\
${BOLD}Action:${NC} Restart Xming on Windows with the simplest possible config + access disabled.\n\
  - Close Xming if running (check taskbar).\n\
  - Start 'XLaunch'.\n\
  - Select 'Multiple windows'.\n\
  - Display number: 0 (or another number if you prefer).\n\
  - Select 'Start no client'.\n\
  - Under 'Extra Settings', ${BOLD}${YELLOW}ONLY check 'No Access Control'.${NC}\n\
    (The prompt might say 'Disable Server Access Control' in newer versions).\n\
  - Click Finish.\n\
  - Alternatively, run: ${YELLOW}\"C:\\Program Files (x86)\\Xming\\Xming.exe\" :0 -multiwindow -ac${NC}\n\
    (Adjust path if needed)\n\n\
Ensure Xming is running (check taskbar) and note its display number (e.g., 0).\n"
printf "Press Enter after restarting Xming with access control disabled...\n"
read

# --- Step 5: Test X11 Forwarding and Check SSH's Internal Setup ---
printf "${BOLD}${BLUE}Step 5: Test X11 Forwarding with a NEW SSH Session and Check Internal Setup${NC}\n\
--------------------------------------------------------------------------\n\
This is the most critical step. We check if SSH successfully sets up the\n\
environment variables and authentication tunnel on %s.\n\
Disconnect any existing SSH sessions to %s.\n\n\
${BOLD}Action:${NC} Start a ${YELLOW}new${NC} SSH session requesting X forwarding:\n\
  ${YELLOW}ssh -X %s@%s${NC}\n\
  (Try ${YELLOW}ssh -Y %s@%s${NC} as alternative if -X fails. -Y is less secure\n\
   but bypasses some checks and is good for testing.)\n\n\
${BOLD}--- ONCE CONNECTED VIA 'ssh -X' to %s ---${NC}\n\
${BOLD}Action:${NC} Inside the SSH session on %s, run these commands EXACTLY:\n" "$host1" "$host1" "$user1" "$host1" "$user1" "$host1" "$host1" "$host1"
printf "\n  echo 'Checking DISPLAY variable...'\n"
echo "  echo \$DISPLAY"
printf "  ${BOLD}# EXPECTED:${NC} Output like 'localhost:10.0', 'localhost:11.0', '%s:10.0', etc.\n\
  # It ${RED}MUST NOT${NC} be empty, and usually ${RED}NOT${NC} just ':0' or 'localhost:0'.\n" "$host1"
printf "\n  echo 'Checking XAUTHORITY variable...'\n"
echo "  echo \$XAUTHORITY"
printf "  ${BOLD}# EXPECTED:${NC} Output like '/home/%s/.Xauthority' or similar, pointing to a file.\n\
  # It ${RED}MUST NOT${NC} be empty.\n" "$user1"
printf "\n  echo 'Checking xauth cookie...'\n\
  # Use the value from the 'echo \$DISPLAY' command here:\n"
echo "  xauth list \$DISPLAY"
printf "  ${BOLD}# EXPECTED:${NC} Output showing a 'MIT-MAGIC-COOKIE-1' entry for the display number.\n\
  # Example: '%s/unix:10  MIT-MAGIC-COOKIE-1  ###########################'\n\
  # If it says 'using authority file ...' but lists nothing, the cookie wasn't added.\n" "$host1"
printf "\n  echo 'Attempting to run a test X application...'\n"
echo "  xeyes"
printf "  # OR\n"
echo "  xclock"
printf "\nBased on the output of 'echo \$DISPLAY' and 'xauth list \$DISPLAY', choose your\n\
next step based on the scenarios below.\n"
printf "${BOLD}${YELLOW}--- INTERPRET THE OUTPUT (PRESS ANY KEY TO SEE TEST SCENARIOS) ---${NC}\n"
read # Pause here before printing scenarios

# --- Troubleshooting Scenarios ---
printf "${BOLD}${BLUE}--- Troubleshooting Scenarios ---${NC}\n\
Review the scenario that matches your output from Step 5.\n\
-------------------------------\n\n\
${BOLD}Scenario A:${NC} 'echo \$DISPLAY' is EMPTY or is just ':0' or 'localhost:0'\n\
---------------------------------------------------------------------\n\
  Problem: SSH X11 forwarding variables (\$DISPLAY, \$XAUTHORITY) are\n\
  ${RED}NOT${NC} being set up by SSH on the server side.\n\
  ${BOLD}Your specific output (empty \$DISPLAY, empty \$XAUTHORITY, xauth error)\n\
  falls into this scenario.${NC}\n\n\
  ${BOLD}Potential Causes & Fixes:${NC}\n\
    1.  ${BOLD}Client config:${NC} 'ForwardX11 no' is implicitly or explicitly set\n\
        (recheck ${BOLD}Step 2${NC}). ${YELLOW}Fix: Ensure ForwardX11 or ForwardX11Trusted is yes.${NC}\n\
    2.  ${BOLD}Server config:${NC} 'X11Forwarding no' or 'AllowTcpForwarding no' in\n\
        ${YELLOW}/etc/ssh/sshd_config${NC} (recheck ${BOLD}Step 3${NC}).\n\
        ${YELLOW}Fix: Ensure X11Forwarding yes and AllowTcpForwarding yes. Restart sshd.${NC}\n\
    3.  ${BOLD}SSH Server NOT RESTARTED:${NC} Changes to ${YELLOW}sshd_config${NC} require a restart\n\
        (recheck ${BOLD}Step 3${NC}). ${YELLOW}Fix: Restart sshd service on %s.${NC}\n\
    4.  ${BOLD}SSH version or installation issue.${NC} (Less common)\n\
    5.  ${BOLD}Terminal/Shell issue on client${NC} preventing SSH from setting variables\n\
        (unlikely for \$DISPLAY/XAUTHORITY but possible for complex setups).\n\n\
  Manual 'export DISPLAY' attempts failed because SSH didn't set up the\n\
  necessary tunnel and authentication cookie.\n\n\
${BOLD}Scenario B:${NC} 'echo \$DISPLAY' is set correctly,\n\
            AND 'xauth list \$DISPLAY' shows a cookie\n\
---------------------------------------------------------------------------------------------\n\
  Problem: SSH successfully set up the tunnel and authentication, but the X\n\
  application cannot connect back to Xming or Xming access is failing.\n\
  Your error 'Authorization required, but no authorization protocol specified'\n\
  in this scenario is confusing, especially with Xming -ac.\n\
  It strongly suggests the connection is either BLOCKED or Xming isn't\n\
  behaving as expected.\n\n\
  ${BOLD}Most Likely Cause: FIREWALL${NC} blocking connection from %s BACK TO\n\
  your Windows machine on the X11 forwarding port.\n\
    - Connection: xeyes on %s --> SSH tunnel --> Your Windows machine\n\
      (usually ports 6010, 6011, etc., depending on \$DISPLAY).\n\
    ${BOLD}Action: Check Firewalls:${NC}\n\
    1.  ${BOLD}Windows Firewall:${NC} Ensure it allows ${RED}INCOMING TCP connections${NC}\n\
        for Xming.exe or specifically on ports 6010+.\n\
        ${YELLOW}Fix: Add an inbound rule for Xming.exe or ports 6010-6020 (a common range).${NC}\n\
    2.  ${BOLD}%s Firewall:${NC} Ensure it allows ${RED}OUTGOING TCP connections${NC}\n\
        on ports 6010+ back to your Windows machine's IP.\n\
        ${YELLOW}Fix: Check egress rules; less common issue unless firewall is very strict.${NC}\n\n\
  ${BOLD}Other Potential Causes:${NC}\n\
    3.  ${BOLD}Xming Issue:${NC} Xming isn't correctly listening or applying -ac.\n\
        ${YELLOW}Fix: Ensure only one Xming instance is running. Re-do Step 4 carefully. Try a different Display number (e.g., :1), then 'ssh -X %s@%s' (DISPLAY should be :11.0), then test xeyes.${NC}\n\
    4.  ${BOLD}Networking:${NC} %s cannot route network traffic back to your Windows IP.\n\
        (Less common in typical home/office networks)\n\n\
${BOLD}Scenario C:${NC} 'echo \$DISPLAY' is set correctly,\n\
            BUT 'xauth list \$DISPLAY' is empty or gives an error\n\
---------------------------------------------------------------------\n\
  Problem: SSH requested forwarding, set \$DISPLAY, but failed to generate/\n\
  register the authentication cookie correctly in the \$XAUTHORITY file.\n\
  ${BOLD}The error 'xauth: file ... does not exist' you saw could potentially\n\
  point to this if \$DISPLAY had been set (which it wasn't in your case).${NC}\n\n\
  ${BOLD}Potential Causes & Fixes:${NC}\n\
    1.  ${BOLD}Permissions issues on \$XAUTHORITY file:${NC} SSH needs to create/write\n\
        this file (usually /home/%s/.Xauthority).\n\
        ${YELLOW}Fix: Check directory permissions: 'ls -ld /home/%s'. Check file ownership/permissions if it exists: 'ls -l \$XAUTHORITY'. Should be owned by %s, e.g., -rw------- (600). Create the file manually if needed: 'touch ~/.Xauthority && chmod 600 ~/.Xauthority'.${NC}\n\
    2.  ${BOLD}Disk space:${NC} Not enough space in home directory to create .Xauthority.\n\
        ${YELLOW}Fix: Check space: 'df -h ~'. Clean up space if needed.${NC}\n\
    3.  ${BOLD}SELinux or AppArmor:${NC} These security modules can block sshd\n\
        writing to user home directories or running xauth.\n\
        ${YELLOW}Fix: Check status: 'sestatus' (SELinux) or 'aa-status' (AppArmor). If active/enforcing, temporarily set to permissive ('sudo setenforce 0' for SELinux) as a diagnostic. Consult system logs (e.g., /var/log/audit/audit.log for SELinux) for 'denied' messages.${NC}\n\
    4.  ${BOLD}xauth command issues:${NC} Corrupted or missing xauth binary on %s.\n\
        ${YELLOW}Fix: Reinstall xauth: 'sudo apt update && sudo apt install xauth'.${NC}\n\
    5.  ${BOLD}Bypass for Testing:${NC} If you suspect an xauth issue, you can test with\n\
        'ssh -Y %s@%s'. This is less secure (trusted forwarding) as it bypasses\n\
        the cookie mechanism, but if it works, it confirms the issue is with\n\
        xauth setup, not connectivity or the basic tunnel.\n" "$host1" "$user1" "$user1" "$user1" "$user1" "$host1" "$user1" "$host1"

printf "\n--------------------------------------------------------------------------\n\
${BOLD}${BLUE}--- Troubleshooting Guide Complete ---${NC}\n\
Review the suggested fixes for the scenario that matched your output.\n\
Based on your specific output, ${BOLD}${YELLOW}Scenario A is the match.${NC}\n\
Focus on verifying SSH client and server configurations related to\n\
ForwardX11 and AllowTcpForwarding, and ensuring sshd was restarted.\n\
If those seem correct, re-check Xming configuration (Step 4).\n\
Good luck!\n"

# The script finishes after printing instructions. User performs steps interactively.
