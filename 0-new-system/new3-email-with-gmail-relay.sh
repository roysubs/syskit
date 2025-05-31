#!/bin/bash
# Author: Roy Wiseman 2025-02

# Install and configure postfix and a gmail SMTP relay

# Define colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Welcome to the Email Server Setup Script with SMTP Relay.${NC}"
echo -e "${YELLOW}This script will set up Postfix with Gmail as your SMTP relay.${NC}"
echo ""

# Update and install necessary packages
echo -e "${GREEN}Step 1: Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

echo -e "${GREEN}Step 2: Installing Postfix and required dependencies...${NC}"
sudo apt install -y postfix mailutils libsasl2-2 libsasl2-modules

# Configure Postfix
echo -e "${GREEN}Step 3: Configuring Postfix for Gmail relay...${NC}"
echo "Setting the relay host and SASL authentication parameters in Postfix configuration."
# sudo postconf -e "relayhost = [smtp.gmail.com]:587"
# sudo postconf -e "smtp_sasl_auth_enable = yes"
# sudo postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
# sudo postconf -e "smtp_sasl_security_options = noanonymous"
# sudo postconf -e "smtp_tls_security_level = encrypt"
# sudo postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

sudo postconf -e "relayhost = [smtp.gmail.com]:587"
sudo postconf -e "smtp_sasl_auth_enable = yes"
sudo postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
sudo postconf -e "smtp_sasl_security_options = noanonymous"
sudo postconf -e "smtp_tls_security_level = encrypt"
sudo postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Explain App Password generation before prompting
echo -e "${YELLOW}IMPORTANT: How to Generate an App Password for Gmail:${NC}"
echo "1. Go to your Google Account Security settings: https://myaccount.google.com/security"
echo "2. Under 'How you sign in to Google', enable '2-Step Verification' if not already enabled."
echo "3. After enabling 2-Step Verification, go to 'App Passwords.'"
echo "   Note that this is still available, but hidden, access it directly at"
echo "   https://security.google.com/settings/security/apppasswords"
echo "4. Select 'Mail' as the app and 'Other' for the device, then name it (e.g., Postfix Server)."
echo "5. Generate the App Password, and copy the 16-character password."
echo "   Note: remove the spaces in the web page to make the password exactly 16 characters."
echo

# Prompt the user for Gmail credentials
echo -e "${YELLOW}Now we need your Gmail address and App Password to configure Postfix.${NC}"
read -p "Enter your Gmail address: " gmail_address
read -p "Enter your App Password: " app_password   # Could use -sp here to hide the password
echo

# Create the SASL password file
echo -e "${GREEN}Step 4: Creating the SASL password file...${NC}"
echo "[smtp.gmail.com]:587 ${gmail_address}:${app_password}" | sudo tee /etc/postfix/sasl_passwd

# Set permissions and apply the SASL password map
echo -e "${GREEN}Step 5: Securing the SASL password file...${NC}"
echo "chmod 600 /etc/postfix/sasl_passwd"
sudo chmod 600 /etc/postfix/sasl_passwd
echo "chmod 600 ensures only the root user can read or write this file, keeping your credentials secure."

echo -e "${GREEN}Step 6: Generating and applying the password hash...${NC}"
echo "Note that this line must be run any time that the SASL configuration changes."
echo "sudo postmap /etc/postfix/sasl_passwd"
sudo postmap /etc/postfix/sasl_passwd

# Restart Postfix
echo -e "${GREEN}Step 7: Restarting Postfix to apply the changes...${NC}"
echo "sudo systemctl restart postfix"
sudo systemctl restart postfix

# Test the setup
echo -e "${GREEN}Step 8: Testing the email relay setup...${NC}"
echo "A test email will be sent to your Gmail address."
echo "Testing Postfix SMTP Relay" | mail -s "Test Email" "$gmail_address"

echo -e "${GREEN}Setup complete!${NC}"

# Display troubleshooting tips
echo -e "${YELLOW}If you encounter issues, check the Postfix logs:${NC}"
echo "   sudo tail -f /var/log/mail.log"
echo "If the App Password is configured correctly, the logs should show a successful delivery like:"
echo "   status=sent (250 2.0.0 OK ...)"
echo "To retest:"
echo "   echo \"Testing Postfix SMTP Relay\" | mail -s \"Test Email\" email@domain.com"
echo
