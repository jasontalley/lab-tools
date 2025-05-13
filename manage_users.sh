#!/bin/bash

# Script to manage users based on a configuration file or remove users.
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

# --- User Removal Functionality ---
remove_user() {
    local user_to_remove="$1"

    if [[ -z "$user_to_remove" ]]; then
        log_message "ERROR: No username specified for removal."
        echo "Usage: $0 --remove <username>"
        exit 1
    fi

    # Safety check: prevent removal of critical users
    if [[ "$user_to_remove" == "root" || "$user_to_remove" == "daemon" || "$user_to_remove" == "bin" || "$user_to_remove" == "sys" ]]; then
        log_message "ERROR: Removal of critical system user '$user_to_remove' is not allowed."
        exit 1
    fi

    log_message "Attempting to remove user: $user_to_remove"

    if id "$user_to_remove" &>/dev/null; then
        # Remove sudoers file if it exists
        local sudoer_file="$SUDOERS_DIR/${user_to_remove}_sudo_access"
        if [[ -f "$sudoer_file" ]]; then
            log_message "INFO: Removing sudoers file $sudoer_file for user $user_to_remove."
            rm -f "$sudoer_file"
            if [[ $? -ne 0 ]]; then
                log_message "WARNING: Failed to remove sudoers file $sudoer_file."
            fi
        fi

        # Remove user
        log_message "INFO: Removing user account $user_to_remove and their home directory."
        userdel -r "$user_to_remove"
        if [[ $? -eq 0 ]]; then
            log_message "INFO: User $user_to_remove removed successfully."
        else
            log_message "ERROR: Failed to remove user $user_to_remove. They may have running processes or other issues."
            exit 1 # Exit with error if userdel fails
        fi
    else
        log_message "INFO: User $user_to_remove does not exist."
    fi
    exit 0 # Exit successfully after removal attempt
}

# --- Argument Parsing for remove ---
if [[ "$1" == "--remove" ]]; then
    remove_user "$2"
fi

# --- Main user provisioning/management logic (if not removing) ---

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
    # Trim whitespace from all fields
    username=$(echo "$username" | xargs)
    sudo_privileges=$(echo "$sudo_privileges" | xargs)
    passwordless_sudo=$(echo "$passwordless_sudo" | xargs)
    groups_str=$(echo "$groups_str" | xargs)
    shell=$(echo "$shell" | xargs)

    # Skip comments and empty lines (check username again after xargs)
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
            group=$(echo "$group" | xargs) # Trim whitespace for individual group names
            if [[ -z "$group" ]]; then continue; fi

            group_exists=false
            if getent group "$group" >/dev/null; then
                group_exists=true
            else
                log_message "INFO: Group '$group' does not exist. Attempting to create it."
                groupadd "$group"
                if [[ $? -eq 0 ]]; then
                    log_message "INFO: Group '$group' created successfully."
                    group_exists=true
                else
                    log_message "ERROR: Failed to create group '$group'. Cannot add '$username' to it."
                    continue # Skip to the next group for this user
                fi
            fi

            if $group_exists; then
                if ! echo "$current_groups_list" | grep -q "^${group}$"; then
                    log_message "INFO: Adding $username to group $group."
                    usermod -aG "$group" "$username"
                    if [[ $? -ne 0 ]]; then
                        log_message "WARNING: Failed to add $username to group $group."
                    fi
                else
                    log_message "INFO: User $username is already in group $group."
                fi
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