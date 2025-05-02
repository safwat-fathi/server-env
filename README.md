# Ubuntu Node.js Server Setup Script

## Overview

This script automates the initial setup of a secure Ubuntu server environment optimized for hosting Node.js applications (like Next.js, Express APIs, etc.). It installs and configures essential components including a firewall, web server, process manager, Node.js runtime, database, and SSL certificate tools.

**Disclaimer:** This script provides a baseline setup. Production environments require careful security hardening, monitoring, and application-specific configuration beyond what this script provides.

## Prerequisites

* **Ubuntu Server:** A fresh installation of Ubuntu Server LTS (e.g., 20.04, 22.04, 24.04) is recommended.
* **Root/Sudo Access:** You need to run this script with `sudo` privileges.
* **Internet Connection:** Required to download packages.

## What the Script Does

1.  **System Update:** Updates all system packages to their latest versions using `apt update` and `apt upgrade`.
2.  **Dedicated User (Optional):** Prompts to create a new non-root user specifically for running the Node.js application. If skipped, components like NVM/Node/PM2 are installed for the user executing the script (via `sudo`).
3.  **Firewall (UFW):** Installs and configures the Uncomplicated Firewall (`ufw`). It denies incoming traffic by default but allows SSH (port 22), HTTP (port 80), and HTTPS (port 443).
4.  **Fail2ban:** Installs `fail2ban` to provide basic protection against SSH brute-force attacks by monitoring logs and banning suspicious IPs.
5.  **NVM (Node Version Manager):** Installs NVM for the designated application user (`TARGET_USER`).
6.  **Node.js (LTS):** Uses NVM to install the latest Long-Term Support (LTS) version of Node.js and sets it as the default for the `TARGET_USER`.
7.  **PM2 Process Manager:** Installs `pm2` globally via `npm` for the `TARGET_USER`. `pm2` is used to keep Node.js applications alive, manage logs, enable clustering, and handle restarts.
8.  **Nginx Web Server:** Installs and enables Nginx, a high-performance web server commonly used as a reverse proxy for Node.js applications.
9.  **PostgreSQL Database:** Installs the PostgreSQL server and client tools.
10. **Certbot (Let's Encrypt):** Installs `certbot` and its Nginx plugin to facilitate obtaining and renewing free SSL/TLS certificates from Let's Encrypt.

## How to Use

1.  **Save:** Save the script content to a file on your server, for example, `setup_node_server.sh`.
2.  **Make Executable:** Open a terminal on your server and run:
    ```bash
    chmod +x setup_node_server.sh
    ```
3.  **Run:** Execute the script with sudo privileges:
    ```bash
    sudo ./setup_node_server.sh
    ```
4.  **Follow Prompts:** The script will ask for confirmation for steps like creating a dedicated user. Read the output carefully.

## CRITICAL: Post-Installation Steps

This script lays the groundwork, but **manual configuration is required** to get your application running securely:

1.  **Secure SSH:**
    * **Prerequisite:** Ensure you have configured and tested SSH key-based authentication *before* proceeding. You must be able to log in with your key without a password prompt.
    * **Disable Password Authentication (Highly Recommended):**
        * Edit the SSH config file: `sudo nano /etc/ssh/sshd_config`
        * Find the line `PasswordAuthentication yes` (it might be commented out with `#`).
        * Uncomment it (remove `#`) and change `yes` to `no`: `PasswordAuthentication no`
        * Save and close (`Ctrl+X`, `Y`, `Enter`).
        * Restart the SSH service: `sudo systemctl restart sshd`
    * **Change SSH Port (Optional but Recommended):**
        * Choose an unused port number (e.g., `2222`).
        * Edit the SSH config file: `sudo nano /etc/ssh/sshd_config`
        * Find the line `#Port 22`.
        * Uncomment it and change `22` to your chosen port: `Port 2222`
        * Save and close.
        * **Update Firewall FIRST:** Allow the new port through UFW *before* restarting SSH: `sudo ufw allow 2222/tcp` (replace `2222` with your port).
        * *(Optional: Remove the old rule: `sudo ufw delete allow ssh`)*
        * Restart the SSH service: `sudo systemctl restart sshd`
        * You will now need to connect using `-p YOUR_PORT`: `ssh your_user@your_server_ip -p 2222`
    * **Create an SSH Alias (Client-Side Convenience):**
        * On your *local machine* (not the server), edit or create the file `~/.ssh/config`.
        * Add an entry like this, replacing placeholders:
            ```
            Host your_server_alias # e.g., my-node-server
              HostName your_server_ip_or_domain
              User your_username_on_server
              Port 2222 # Use the port you configured (or 22 if unchanged)
              IdentityFile ~/.ssh/your_private_key # Optional: specify key if not default
            ```
        * Save the file. Now you can connect simply by typing: `ssh your_server_alias`

2.  **Secure PostgreSQL:**
    * Set a strong password for the default `postgres` superuser: `sudo -u postgres psql -c "\password postgres"`
    * Create a dedicated database and user for your application with limited privileges. **Do not** use the `postgres` superuser for your application.

3.  **Configure Nginx:**
    * Create an Nginx server block configuration file for your domain in `/etc/nginx/sites-available/your_domain`.
    * Configure it to act as a reverse proxy, forwarding requests to your Node.js application (which you'll likely run on `http://localhost:YOUR_APP_PORT` using PM2). Include necessary headers like `X-Forwarded-For`.
    * Enable the site: `sudo ln -s /etc/nginx/sites-available/your_domain /etc/nginx/sites-enabled/`
    * Test the configuration: `sudo nginx -t`
    * Reload Nginx to apply changes: `sudo systemctl reload nginx`

4.  **Obtain SSL Certificate (Certbot):**
    * Ensure your domain's DNS records point to your server's IP address.
    * Run Certbot with the Nginx plugin: `sudo certbot --nginx -d your_domain.com -d www.your_domain.com` (replace with your actual domain). Follow the prompts. Certbot will automatically update your Nginx configuration for HTTPS.

5.  **Deploy Application:**
    * Copy your Node.js application code to the server (e.g., using `scp` or `git clone`) into a directory owned by the `TARGET_USER` (e.g., `/home/appuser/my_app`).

6.  **Install Dependencies:**
    * Log in as the `TARGET_USER` (`su - appuser` or SSH directly).
    * Navigate (`cd`) to your application directory.
    * Run `npm install` (or `yarn install`) to install project dependencies.

7.  **Start Application with PM2:**
    * While logged in as `TARGET_USER` and in your app directory, start your application using PM2:
        ```bash
        # Example for a typical Node.js app:
        pm2 start your_entry_script.js --name "your-app-name"

        # Example for a Next.js app (using the start script from package.json):
        # Ensure you have run 'npm run build' first
        pm2 start npm --name "your-nextjs-app" -- run start
        ```
    * Check status: `pm2 list` or `pm2 status`
    * View logs: `pm2 logs your-app-name`

8.  **Configure PM2 Startup:**
    * To ensure PM2 restarts your application after a server reboot, run `pm2 startup` while logged in as `TARGET_USER`.
    * This command will output another command that you need to copy and run using `sudo`. This sets up a systemd service for PM2.

9.  **Save PM2 Process List:**
    * After starting all your apps, run `pm2 save` as `TARGET_USER` to save the current process list so it can be resurrected on reboot by the startup script.

By following these post-installation steps, you can create a secure and robust environment for your Node.js application.
