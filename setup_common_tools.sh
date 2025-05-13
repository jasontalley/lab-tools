#!/bin/bash

# Script to perform initial system bootstrap and install common tools.
# Assumes a Debian/Ubuntu-based system.
# This script should be run as root.

# Function to log messages
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# --- Configuration: List of packages to install ---
COMMON_PACKAGES=(
    build-essential
    git
    curl
    wget
    vim
    htop
    net-tools
    jq
    unzip
    zip
    tree
    ncdu
    tmux
    python3-pip
    fail2ban
    unattended-upgrades
)

# --- Script Execution ---

log_message "Starting common tools setup..."

# 1. Check if running as root
if [[ "$EUID" -ne 0 ]]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

# 2. Update package lists
log_message "Updating package lists..."
if ! apt update; then
    log_message "ERROR: Failed to update package lists. Please check your network connection and APT sources."
    exit 1
fi
log_message "Package lists updated successfully."

# 3. Upgrade installed packages
log_message "Upgrading installed packages..."
if ! apt upgrade -y; then
    log_message "WARNING: Failed to upgrade all packages. Some upgrades might have failed or been held back."
    # Continue execution as this might not be critical for tool installation
else
    log_message "Installed packages upgraded successfully."
fi

# 4. Install common packages
log_message "Installing common packages..."
packages_to_install=""
for pkg in "${COMMON_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        packages_to_install+="$pkg "
    else
        log_message "INFO: Package '$pkg' is already installed."
    fi
done

if [[ -n "$packages_to_install" ]]; then
    log_message "Attempting to install: $packages_to_install"
    # Disable DEBIAN_FRONTEND for non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    if ! apt install -y $packages_to_install; then
        log_message "ERROR: Failed to install one or more common packages. Please check the output above."
        # Optionally, list failed packages here
    else
        log_message "Common packages installed successfully."
    fi
else
    log_message "All specified common packages are already installed."
fi

# 5. Configure unattended-upgrades (optional, but good practice)
log_message "Configuring unattended-upgrades..."
if dpkg -s unattended-upgrades &>/dev/null; then
    if dpkg-reconfigure --priority=low unattended-upgrades; then
        log_message "INFO: unattended-upgrades configured."
    else
        log_message "WARNING: Failed to automatically configure unattended-upgrades. You may need to configure it manually via 'dpkg-reconfigure unattended-upgrades'."
    fi
else
    log_message "INFO: unattended-upgrades package not found, skipping configuration."
fi

# 6. Enable and start fail2ban
log_message "Enabling and starting fail2ban..."
if dpkg -s fail2ban &>/dev/null; then
    if systemctl enable fail2ban && systemctl start fail2ban; then
        log_message "INFO: fail2ban enabled and started."
    else
        log_message "WARNING: Failed to enable or start fail2ban. Check its status with 'systemctl status fail2ban'."
    fi
else
    log_message "INFO: fail2ban package not found, skipping service management."
fi


log_message "Common tools setup script completed."
log_message "Review any warnings above. A reboot might be required for some system updates to take full effect."

exit 0 