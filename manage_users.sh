#!/bin/bash

# Script to manage users based on a configuration file.
# This script should be run as root.

USER_CONFIG_FILE="user_config.txt"
SUDOERS_DIR="/etc/sudoers.d"

# Function to log messages
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
  log_message "ERROR: This script must be run as root."
  exit 1
fi

# Check if configuration file exists
if [[ ! -f "$USER_CONFIG_FILE" ]]; then
    log_message "ERROR: Configuration file '$USER_CONFIG_FILE' not found."
    exit 1
fi

# Ensure sudoers.d directory exists (it should, but good practice)
if [[ ! -d "$SUDOERS_DIR" ]]; then
    log_message "INFO: Creating sudoers directory at $SUDOERS_DIR."
    mkdir -p "$SUDOERS_DIR"
    chmod 0750 "$SUDOERS_DIR"
fi

log_message "Starting user management process..."

# Read the configuration file line by line
# Format: username:sudo_privileges:passwordless_sudo:groups:shell
# Example: ansible:yes:yes::/bin/bash
#          testuser:no:no:docker,dev:/bin/zsh

OLD_IFS="$IFS"
IFS=':'
while read -r username sudo_privileges passwordless_sudo groups_str shell || [[ -n "$username" ]]; do
    # Skip comments and empty lines
    if [[ "$username" =~ ^#.*$ || -z "$username" ]]; then
        continue
    fi

    log_message "Processing user: $username"

    # Set default shell if not specified
    if [[ -z "$shell" ]]; then
        shell="/bin/bash"
        log_message "INFO: Shell not specified for $username, defaulting to $shell."
    fi

    # Check if user exists
    if id "$username" &>/dev/null; then
        log_message "INFO: User $username already exists. Checking configuration..."
        # Update shell if different
        current_shell=$(getent passwd "$username" | cut -d: -f7)
        if [[ "$current_shell" != "$shell" ]]; then
            log_message "INFO: Updating shell for $username from $current_shell to $shell."
            usermod -s "$shell" "$username"
            if [[ $? -ne 0 ]]; then
                log_message "WARNING: Failed to update shell for $username."
            fi
        fi
    else
        log_message "INFO: User $username does not exist. Creating..."
        useradd -m -s "$shell" "$username"
        if [[ $? -eq 0 ]]; then
            log_message "INFO: User $username created successfully with shell $shell and home directory."
        else
            log_message "ERROR: Failed to create user $username."
            continue # Skip to next user if creation fails
        fi
    fi

    # Manage groups
    # First, handle sudo group based on sudo_privileges
    if [[ "$sudo_privileges" == "yes" ]]; then
        if ! groups "$username" | grep -q 'sudo'; then # or wheel, depending on distro
            log_message "INFO: Adding $username to sudo group."
            usermod -aG sudo "$username" # Use 'wheel' on RHEL-based systems
            if [[ $? -ne 0 ]]; then
                log_message "WARNING: Failed to add $username to sudo group."
            fi
        else
            log_message "INFO: User $username is already in the sudo group."
        fi
    else # Explicitly ensure user is NOT in sudo group if config says no
        if groups "$username" | grep -q 'sudo'; then
            log_message "INFO: Removing $username from sudo group as per configuration."
            gpasswd -d "$username" sudo
             if [[ $? -ne 0 ]]; then
                log_message "WARNING: Failed to remove $username from sudo group."
            fi
        fi
    fi

    # Add to other specified groups
    if [[ -n "$groups_str" ]]; then
        current_groups_list=$(id -Gn "$username" | tr ' ' '\n')
        # Save and change IFS for group processing
        temp_ifs="$IFS"
        IFS=','
        for group in $groups_str; do
            if ! echo "$current_groups_list" | grep -q "^${group}$"; then
                log_message "INFO: Adding $username to group $group."
                usermod -aG "$group" "$username"
                if [[ $? -ne 0 ]]; then
                    log_message "WARNING: Failed to add $username to group $group."
                fi
            else
                log_message "INFO: User $username is already in group $group."
            fi
        done
        IFS="$temp_ifs" # Restore IFS
    fi


    # Manage passwordless sudo
    sudoer_file="$SUDOERS_DIR/${username}_sudo_access"
    if [[ "$sudo_privileges" == "yes" && "$passwordless_sudo" == "yes" ]]; then
        log_message "INFO: Setting up passwordless sudo for $username."
        echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudoer_file"
        chmod 0440 "$sudoer_file"
        if [[ $? -ne 0 ]]; then
            log_message "WARNING: Failed to set up passwordless sudo for $username. Check permissions on $sudoer_file."
        fi
    else
        # If user is not configured for passwordless sudo, remove the specific file
        if [[ -f "$sudoer_file" ]]; then
            log_message "INFO: Removing passwordless sudo configuration for $username from $sudoer_file."
            rm -f "$sudoer_file"
            if [[ $? -ne 0 ]]; then
                log_message "WARNING: Failed to remove $sudoer_file."
            fi
        fi
    fi

done < "$USER_CONFIG_FILE"
IFS="$OLD_IFS" # Restore original IFS

log_message "User management process completed."
echo "To grant actual login access, passwords must be set for new users (e.g., sudo passwd username) or SSH keys configured." 