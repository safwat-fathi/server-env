#!/bin/bash

# Node.js Server Setup Script for Ubuntu LTS
# Installs: UFW, Fail2ban, Nginx, NVM, Node.js (LTS), PM2, PostgreSQL, Certbot

# --- Helper Functions ---

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to ask Yes/No questions (defaults to No)
ask_yes_no() {
  local prompt="$1"
  while true; do
    read -p "$prompt [y/N]: " yn
    case $yn in
      [Yy]*) return 0 ;; # Yes
      [Nn]|"") return 1 ;; # No or Enter
      *) echo "Please answer yes (y) or no (n)." ;;
    esac
  done
}

# --- Sanity Checks ---

# Check if running as root/sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run with root privileges (e.g., using sudo)." >&2
  exit 1
fi

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "Warning: This script is designed for Ubuntu. Running on other distributions may cause issues."
    if ! ask_yes_no "Continue anyway?"; then
        exit 1
    fi
fi

echo "Starting Ubuntu Server Setup for Node.js Applications..."
echo "======================================================"

# --- System Update ---
echo "[1/9] Updating system packages..."
apt update
# Consider non-interactive upgrade to avoid prompts, use with caution
# export DEBIAN_FRONTEND=noninteractive
# apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt upgrade -y # Standard interactive upgrade
echo "System update complete."
echo "-----------------------------------------"

# --- Create Dedicated User (Optional) ---
APP_USER=""
RUN_AS_USER=$(logname) # User who ran sudo
TARGET_USER=$RUN_AS_USER # Default to the user who ran sudo

if ask_yes_no "[2/9] Create a dedicated non-root user to run the application?"; then
    while true; do
        read -p "Enter username for the application user: " APP_USER
        if [[ -z "$APP_USER" ]]; then
            echo "Username cannot be empty."
        elif id "$APP_USER" &>/dev/null; then
            echo "User '$APP_USER' already exists. Please choose a different name."
        else
            break
        fi
    done
    adduser --disabled-password --gecos "" "$APP_USER"
    # Add user to sudo group? Usually not recommended for app user unless needed
    # if ask_yes_no "Add user '$APP_USER' to the 'sudo' group?"; then
    #     usermod -aG sudo "$APP_USER"
    #     echo "User '$APP_USER' added to sudo group."
    # fi
    echo "User '$APP_USER' created."
    TARGET_USER=$APP_USER # NVM and PM2 should be installed for this user
else
    echo "Skipping dedicated user creation. NVM/Node/PM2 will be installed for user '$TARGET_USER'."
fi
echo "Application components will target user: $TARGET_USER"
echo "-----------------------------------------"

# --- Firewall Setup (UFW) ---
echo "[3/9] Configuring Firewall (UFW)..."
if ! command_exists ufw; then
    apt install -y ufw
fi

# Ensure default policies are set (deny incoming, allow outgoing)
ufw default deny incoming
ufw default allow outgoing

# Allow essential ports
ufw allow ssh       # Port 22
ufw allow http      # Port 80
ufw allow https     # Port 443

# Enable UFW (non-interactively)
echo "y" | ufw enable

ufw status verbose
echo "Firewall configured and enabled."
echo "-----------------------------------------"

# --- Install Fail2ban ---
echo "[4/9] Installing Fail2ban for SSH protection..."
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
echo "Fail2ban installed and enabled."
echo "-----------------------------------------"

# --- Install NVM, Node.js (LTS), and PM2 for Target User ---
echo "[5/9] Installing NVM, Node.js (LTS), and PM2 for user '$TARGET_USER'..."

# Use sudo to run commands as the target user
sudo -i -u "$TARGET_USER" bash << EOF
echo "Running NVM installation as user $(whoami)..."
# Install NVM
if [ ! -d "\$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    echo "NVM installed."
else
    echo "NVM already installed."
fi

# Source NVM in this subshell to make it available immediately
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

# Install Node.js LTS
echo "Installing latest Node.js LTS version..."
if command -v nvm &> /dev/null; then
    nvm install --lts
    # Set default alias
    NODE_LTS_VERSION=\$(nvm list --lts --no-colors | awk 'NR==1{print \$1}') # Get the actual LTS version string
    if [ -n "\$NODE_LTS_VERSION" ]; then
      nvm alias default "\$NODE_LTS_VERSION"
      echo "Node.js LTS (\$(node -v)) installed and set as default."
    else
      echo "Could not determine installed LTS version to set default alias."
    fi
else
    echo "Error: NVM command not found in subshell. Cannot install Node.js."
    exit 1 # Exit the subshell if NVM failed
fi

# Install PM2 globally using the installed Node/NPM
echo "Installing PM2 globally..."
if command -v npm &> /dev/null; then
    npm install pm2 -g
    echo "PM2 installed globally (\$(pm2 -v))."

    # Setup pm2 startup script (optional but recommended)
    # This requires root privileges *within* the subshell, which is tricky.
    # Better to instruct the user to run this manually after the script.
    # echo "Attempting to setup PM2 startup script (may require manual intervention)..."
    # pm2 startup || echo "PM2 startup command failed. Run 'sudo env PATH=\$PATH:/home/$TARGET_USER/.nvm/versions/node/\$(nvm current)/bin pm2 startup systemd -u $TARGET_USER --hp /home/$TARGET_USER' manually after this script."

else
    echo "Error: NPM command not found. Cannot install PM2."
    exit 1 # Exit the subshell if NPM failed
fi
EOF

# Check if the subshell exited successfully
if [ $? -ne 0 ]; then
    echo "Error occurred during NVM/Node/PM2 installation for user '$TARGET_USER'. Please check logs."
    # Decide whether to exit or continue
    # exit 1
else
    echo "NVM, Node.js (LTS), and PM2 installation completed for user '$TARGET_USER'."
    echo "IMPORTANT: User '$TARGET_USER' may need to log out and log back in for NVM to be available in their regular sessions."
    echo "IMPORTANT: To enable PM2 to restart applications on server reboot, run the command suggested by 'pm2 startup' as root."
    echo "           (You can generate the command by logging in as '$TARGET_USER' and running 'pm2 startup')"
fi
echo "-----------------------------------------"

# --- Install Nginx ---
echo "[6/9] Installing Nginx web server..."
if ! command_exists nginx; then
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "Nginx installed and enabled."
else
    echo "Nginx already installed."
    systemctl enable nginx # Ensure it's enabled
    systemctl restart nginx # Restart to apply any potential pending changes
fi
# Basic check if Nginx is running
systemctl is-active --quiet nginx && echo "Nginx is active." || echo "Warning: Nginx service is not active."
echo "-----------------------------------------"

# --- Install PostgreSQL ---
echo "[7/9] Installing PostgreSQL database server..."
if ! command_exists psql; then
    apt install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
    echo "PostgreSQL installed and enabled."
else
    echo "PostgreSQL already installed."
    systemctl enable postgresql # Ensure it's enabled
    systemctl restart postgresql
fi
# Basic check if PostgreSQL is running
systemctl is-active --quiet postgresql && echo "PostgreSQL is active." || echo "Warning: PostgreSQL service is not active."
echo "IMPORTANT: PostgreSQL is installed, but you MUST secure it:"
echo "  - Set a password for the default 'postgres' user: sudo -u postgres psql -c \"\\password postgres\""
echo "  - Create dedicated database users/databases for your applications."
echo "-----------------------------------------"

# --- Install Certbot (Let's Encrypt) ---
echo "[8/9] Installing Certbot for Let's Encrypt SSL certificates..."
if ! command_exists certbot; then
    # Add repository if needed (often required on older Ubuntu versions, but included in newer ones)
    # apt install -y software-properties-common
    # add-apt-repository ppa:certbot/certbot -y
    # apt update
    apt install -y certbot python3-certbot-nginx
    echo "Certbot and Nginx plugin installed."
else
    echo "Certbot already installed."
    # Ensure nginx plugin is installed
    if ! dpkg -l | grep -q python3-certbot-nginx; then
       echo "Installing Certbot Nginx plugin..."
       apt install -y python3-certbot-nginx
    else
       echo "Certbot Nginx plugin already installed."
    fi
fi
echo "IMPORTANT: To obtain an SSL certificate, configure your Nginx server block for your domain, ensure DNS points to this server, then run:"
echo "  sudo certbot --nginx -d your_domain.com -d www.your_domain.com"
echo "-----------------------------------------"

# --- Final Instructions ---
echo "[9/9] Server setup script finished."
echo "================================="
echo "Summary & Next Steps:"
echo " - System Updated."
if [ -n "$APP_USER" ]; then
    echo " - Dedicated user '$APP_USER' created."
fi
echo " - Firewall (UFW) enabled (SSH, HTTP, HTTPS allowed)."
echo " - Fail2ban installed for SSH protection."
echo " - NVM, Node.js LTS, and PM2 installed for user '$TARGET_USER'."
echo " - Nginx web server installed."
echo " - PostgreSQL database server installed."
echo " - Certbot (Let's Encrypt) installed."
echo ""
echo "Critical Next Steps:"
echo " 1. Secure SSH: Use key-based authentication, disable password login, potentially change SSH port."
echo " 2. Secure PostgreSQL: Set passwords, create application users/databases (see PostgreSQL section above)."
echo " 3. Configure Nginx: Create server block(s) in /etc/nginx/sites-available/ for your domain(s), proxying requests to your Node.js app (e.g., running on http://localhost:3000)."
echo "    - Example proxy pass: location / { proxy_pass http://localhost:YOUR_APP_PORT; ... }"
echo "    - Remember to enable the site: sudo ln -s /etc/nginx/sites-available/your_config /etc/nginx/sites-enabled/"
echo "    - Test config: sudo nginx -t"
echo "    - Reload Nginx: sudo systemctl reload nginx"
echo " 4. Obtain SSL Certificate: Once Nginx is configured and DNS is set, run 'sudo certbot --nginx' (see Certbot section above)."
echo " 5. Deploy Your App: Copy your application files to the server (e.g., under /home/$TARGET_USER/app)."
echo " 6. Install App Dependencies: Log in as '$TARGET_USER', navigate to your app directory, and run 'npm install'."
echo " 7. Start App with PM2: Log in as '$TARGET_USER', navigate to your app directory, and run 'pm2 start your_app_entry_point.js --name your-app-name'."
echo " 8. Setup PM2 Startup: Log in as '$TARGET_USER', run 'pm2 startup', then execute the command it outputs using 'sudo'."
echo " 9. Save PM2 Process List: Run 'pm2 save' as '$TARGET_USER'."
echo ""
echo "Setup Complete. Please perform the necessary manual configurations."

exit 0
