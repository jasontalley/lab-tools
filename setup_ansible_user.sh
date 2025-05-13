#!/bin/bash

# Script to create an 'ansible' user with passwordless sudo and import SSH keys from GitHub.
# This script should be run as root or via 'sudo bash'.

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipefail: ensures that a pipeline command returns a failure status if any command in the pipeline fails.
set -o pipefail

GITHUB_USERNAME="jasontalley"

# --- Logging Function ---
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# --- Check if running as root ---
if [[ "$(id -u)" -ne 0 ]]; then
  log_message "ERROR: This script must be run as root or with sudo."
  exit 1
fi

log_message "Starting ansible user setup for GitHub user: $GITHUB_USERNAME"

# --- Install ssh-import-id if not present ---
if ! command -v ssh-import-id &> /dev/null; then
    log_message "INFO: ssh-import-id not found. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get install -y ssh-import-id
    elif command -v yum &> /dev/null; then
        yum install -y ssh-import-id
    elif command -v dnf &> /dev/null; then
        dnf install -y ssh-import-id
    else
        log_message "ERROR: ssh-import-id not found and no known package manager (apt, yum, dnf) available."
        log_message "Please install ssh-import-id manually and re-run the script."
        exit 1
    fi

    if ! command -v ssh-import-id &> /dev/null; then
        log_message "ERROR: Failed to install ssh-import-id."
        exit 1
    fi
    log_message "INFO: ssh-import-id installed successfully."
else
    log_message "INFO: ssh-import-id is already installed."
fi

# --- Create ansible user if not exists ---
ANSIBLE_USER="ansible"
ANSIBLE_SHELL="/bin/bash"
ANSIBLE_HOME="/home/$ANSIBLE_USER"

if id "$ANSIBLE_USER" &>/dev/null; then
    log_message "INFO: User '$ANSIBLE_USER' already exists."
    # Ensure shell is correct
    current_shell=$(getent passwd "$ANSIBLE_USER" | cut -d: -f7)
    if [[ "$current_shell" != "$ANSIBLE_SHELL" ]]; then
        log_message "INFO: Updating shell for $ANSIBLE_USER from $current_shell to $ANSIBLE_SHELL."
        usermod -s "$ANSIBLE_SHELL" "$ANSIBLE_USER"
    fi
else
    log_message "INFO: Creating user '$ANSIBLE_USER' with home directory $ANSIBLE_HOME and shell $ANSIBLE_SHELL."
    useradd -m -s "$ANSIBLE_SHELL" "$ANSIBLE_USER"
    if [[ $? -eq 0 ]]; then
        log_message "INFO: User '$ANSIBLE_USER' created successfully."
    else
        log_message "ERROR: Failed to create user '$ANSIBLE_USER'."
        exit 1
    fi
fi

# Ensure .ssh directory exists with correct permissions for ansible user
if [ ! -d "$ANSIBLE_HOME/.ssh" ]; then
    log_message "INFO: Creating $ANSIBLE_HOME/.ssh directory."
    mkdir -p "$ANSIBLE_HOME/.ssh"
    chown "$ANSIBLE_USER:$(id -gn "$ANSIBLE_USER")" "$ANSIBLE_HOME/.ssh"
    chmod 700 "$ANSIBLE_HOME/.ssh"
else
    # Ensure correct ownership and permissions even if it exists
    current_owner_group=$(stat -c "%U:%G" "$ANSIBLE_HOME/.ssh")
    expected_owner_group="$ANSIBLE_USER:$(id -gn "$ANSIBLE_USER")"
    if [ "$current_owner_group" != "$expected_owner_group" ]; then
        log_message "INFO: Correcting ownership of $ANSIBLE_HOME/.ssh to $expected_owner_group."
        chown "$expected_owner_group" "$ANSIBLE_HOME/.ssh"
    fi
    current_perms=$(stat -c "%a" "$ANSIBLE_HOME/.ssh")
    if [ "$current_perms" != "700" ]; then
        log_message "INFO: Correcting permissions of $ANSIBLE_HOME/.ssh to 700."
        chmod 700 "$ANSIBLE_HOME/.ssh"
    fi
fi


# --- Grant passwordless sudo to ansible user ---
SUDOERS_DIR="/etc/sudoers.d"
SUDOERS_FILE="$SUDOERS_DIR/${ANSIBLE_USER}_nopasswd"
SUDOERS_CONTENT="$ANSIBLE_USER ALL=(ALL) NOPASSWD:ALL"

# Ensure sudoers.d directory exists
if [ ! -d "$SUDOERS_DIR" ]; then
    log_message "INFO: Sudoers directory $SUDOERS_DIR does not exist. Creating..."
    mkdir -p "$SUDOERS_DIR"
    chmod 0750 "$SUDOERS_DIR" # Standard permissions for sudoers.d
fi

if [ -f "$SUDOERS_FILE" ] && grep -Fxq "$SUDOERS_CONTENT" "$SUDOERS_FILE"; then
    log_message "INFO: Passwordless sudo for '$ANSIBLE_USER' already configured in $SUDOERS_FILE."
else
    log_message "INFO: Setting up passwordless sudo for '$ANSIBLE_USER' in $SUDOERS_FILE."
    echo "$SUDOERS_CONTENT" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
    log_message "INFO: Passwordless sudo for '$ANSIBLE_USER' configured."
fi

# --- Import SSH keys from GitHub for ansible user ---
log_message "INFO: Attempting to import SSH keys for '$ANSIBLE_USER' from GitHub user '$GITHUB_USERNAME'."

# The -H flag sets the HOME environment variable to the target user's home directory.
# The -n flag (non-interactive) can be useful with sudo to prevent prompts if not fully NOPASSWD.
# However, since we just set NOPASSWD for ALL, it might not be strictly needed for ssh-import-id.
# ssh-import-id handles its own errors and outputs them.
if sudo -H -u "$ANSIBLE_USER" ssh-import-id "gh:$GITHUB_USERNAME"; then
    log_message "INFO: ssh-import-id command executed for user '$ANSIBLE_USER'."
    if sudo test -f "$ANSIBLE_HOME/.ssh/authorized_keys" && sudo test -s "$ANSIBLE_HOME/.ssh/authorized_keys"; then
        log_message "SUCCESS: SSH keys appear to be imported successfully into $ANSIBLE_HOME/.ssh/authorized_keys."
        log_message "Contents of $ANSIBLE_HOME/.ssh/authorized_keys (first few keys if many):"
        head -n 10 "$ANSIBLE_HOME/.ssh/authorized_keys" | sed 's/^/    /' # Indent for readability
    else
        log_message "WARNING: ssh-import-id ran, but $ANSIBLE_HOME/.ssh/authorized_keys is missing or empty."
        log_message "This could happen if GitHub user '$GITHUB_USERNAME' has no public keys or if there was an issue with ssh-import-id."
    fi
else
    # ssh-import-id returns non-zero on failure (e.g., user not found, no keys, network issue)
    log_message "ERROR: ssh-import-id command failed for user '$ANSIBLE_USER' (GitHub user: '$GITHUB_USERNAME')."
    log_message "Check for specific error messages from ssh-import-id above this message."
    log_message "Common reasons: GitHub user not found, no public keys on GitHub, network issues, or permissions problems in $ANSIBLE_HOME/.ssh."
    # We don't exit 1 here to allow the script to complete, but the primary goal failed.
    # The user might want to see if other steps succeeded. Or, change to exit 1 if this is critical failure.
fi

log_message "Ansible user setup script completed." 