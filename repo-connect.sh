#!/bin/bash

# Script to set up SSH key for GitHub and clone the lab-tools repository.

# --- Helper Functions ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_error() { echo -e "\033[31m[ERROR] $1\033[0m"; }
log_step() { echo -e "\n\033[34m--- $1 ---\033[0m"; }

confirm_action() {
    while true; do
        read -r -p "$1 [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"")
                return 1
                ;;
            *)
                log_warn "Invalid input. Please enter 'y' or 'n'."
                ;;
        esac
    done
}

REPO_URL="git@github.com:jasontalley/lab-tools.git"
REPO_NAME="lab-tools"
CLONE_DEST_PARENT="$HOME"
CLONE_DEST="$CLONE_DEST_PARENT/$REPO_NAME"

SSH_KEY_PATH="$HOME/.ssh/lab_tools_github_rsa"
SSH_CONFIG_PATH="$HOME/.ssh/config"
GITHUB_HOST="github.com"

# --- Main Script ---

log_step "1. Checking for Git installation"
if ! command -v git &> /dev/null; then
    log_warn "Git command not found."
    if confirm_action "Do you want this script to attempt to install Git (requires sudo)?"; then
        log_info "Attempting to install Git..."
        if sudo apt update && sudo apt install -y git; then
            log_info "Git installed successfully."
        else
            log_error "Git installation failed. Please install Git manually and re-run the script."
            exit 1
        fi
    else
        log_error "Git is required to proceed. Please install Git and re-run the script."
        exit 1
    fi
else
    log_info "Git is already installed."
fi

log_step "2. SSH Key Setup for GitHub"

# Ensure .ssh directory exists and has correct permissions
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

SSH_KEY_EXISTS=false
if [ -f "$SSH_KEY_PATH" ] && [ -f "${SSH_KEY_PATH}.pub" ]; then
    log_info "SSH key pair ($SSH_KEY_PATH) already exists."
    if confirm_action "Do you want to use this existing key?"; then
        SSH_KEY_EXISTS=true
    else
        if confirm_action "Generate a new key pair (this will overwrite the existing $SSH_KEY_PATH if you proceed)?"; then
            SSH_KEY_EXISTS=false # Proceed to generate
        else
            log_info "Using the existing key pair as requested."
            SSH_KEY_EXISTS=true
        fi
    fi
fi

if ! $SSH_KEY_EXISTS; then
    log_info "Generating a new SSH key pair at $SSH_KEY_PATH..."
    # Remove old keys if they exist and user agreed to overwrite
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$(whoami)@$(hostname)-lab-tools-github"
    if [ $? -ne 0 ]; then
        log_error "SSH key generation failed."
        exit 1
    fi
    log_info "New SSH key pair generated successfully."
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
fi

log_step "3. Configuring SSH Agent and SSH Config"

# Start ssh-agent if not running
eval "$(ssh-agent -s)" > /dev/null

# Add the key to ssh-agent
# First, try to remove any existing instances of this key in the agent to avoid duplicates
ssh-add -d "$SSH_KEY_PATH" &>/dev/null 
if ssh-add "$SSH_KEY_PATH"; then
    log_info "SSH key added to the agent."
else
    log_error "Failed to add SSH key to the agent. You might need to enter the passphrase if you set one."
    # Attempt to add again, allowing for passphrase input
    if ! ssh-add "$SSH_KEY_PATH"; then
        log_error "Still failed to add SSH key. Please check your key and passphrase."
        exit 1
    fi
fi


log_info "Configuring SSH to use this key for $GITHUB_HOST..."
# Create or update SSH config
# Check if entry already exists for this host and identity file
CONFIG_ENTRY_EXISTS=false
if [ -f "$SSH_CONFIG_PATH" ]; then
    if grep -q "Host $GITHUB_HOST" "$SSH_CONFIG_PATH" && grep -q "IdentityFile $SSH_KEY_PATH" "$SSH_CONFIG_PATH"; then
        CONFIG_ENTRY_EXISTS=true
        log_info "SSH config entry for $GITHUB_HOST with $SSH_KEY_PATH already seems to exist."
    fi
fi

if ! $CONFIG_ENTRY_EXISTS; then
    # Backup existing config if it exists
    if [ -f "$SSH_CONFIG_PATH" ]; then
        cp "$SSH_CONFIG_PATH" "${SSH_CONFIG_PATH}.bak_$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing SSH config to ${SSH_CONFIG_PATH}.bak_..."
    fi
    
    # Remove any existing config for this specific Host github.com to avoid duplicates before adding new one
    # This is a bit tricky; for now, we'll just append. A more robust solution would parse and modify.
    # For simplicity, if the user has a complex config, they might need to adjust manually.
    # We will add our specific config, ensuring IdentityFile is correctly set.
    
    # Ensure there's a newline at the end of the file if it exists, before appending
    if [ -f "$SSH_CONFIG_PATH" ] && [ -s "$SSH_CONFIG_PATH" ]; then # if file exists and is not empty
        if [ "$(tail -c1 "$SSH_CONFIG_PATH")" != "" ]; then # if no newline at EOF
             echo "" >> "$SSH_CONFIG_PATH"
        fi
    fi

    # Construct the desired config block
    DESIRED_CONFIG_BLOCK="Host $GITHUB_HOST
  HostName $GITHUB_HOST
  User git
  IdentityFile $SSH_KEY_PATH
  IdentitiesOnly yes"

    # Check if a block for "Host github.com" already exists
    if grep -Fxq "Host $GITHUB_HOST" "$SSH_CONFIG_PATH"; then
        log_warn "An 'Host $GITHUB_HOST' block already exists in $SSH_CONFIG_PATH."
        log_warn "This script will append a new specific entry for $SSH_KEY_PATH."
        log_warn "You may need to manually review and clean up $SSH_CONFIG_PATH if you have multiple configurations for github.com."
        echo -e "
# Added by lab-tools setup script for $SSH_KEY_PATH" >> "$SSH_CONFIG_PATH"
        echo -e "$DESIRED_CONFIG_BLOCK" >> "$SSH_CONFIG_PATH"
    else
        echo -e "
# Added by lab-tools setup script" >> "$SSH_CONFIG_PATH"
        echo -e "$DESIRED_CONFIG_BLOCK" >> "$SSH_CONFIG_PATH"
    fi
    chmod 600 "$SSH_CONFIG_PATH"
    log_info "SSH config updated/created at $SSH_CONFIG_PATH to use $SSH_KEY_PATH for $GITHUB_HOST."
else
    log_info "Skipping SSH config modification as a suitable entry appears to exist."
fi

log_step "4. Testing GitHub SSH Connection"
log_info "Please add the following public SSH key to your GitHub account if you haven't already:"
log_info "Go to https://github.com/settings/keys and click 'New SSH key'."
echo -e "\033[36m" # Cyan color for key
cat "${SSH_KEY_PATH}.pub"
echo -e "\033[0m" # Reset color
confirm_action "Press Enter to continue after you've added the key to GitHub (or if it was already added)..."

log_info "Attempting to connect to GitHub via SSH (ssh -T $GITHUB_HOST)..."
log_info "If prompted 'Are you sure you want to continue connecting (yes/no/[fingerprint])?', please type 'yes'."

# Loop to allow user to re-add key and test again
while true; do
    if ssh -T "$GITHUB_HOST"; then
        log_info "Successfully authenticated with GitHub!"
        break
    else
        log_warn "Failed to authenticate with GitHub using the SSH key."
        log_warn "Please ensure:"
        log_warn "1. The public key displayed above is correctly added to your GitHub account (https://github.com/settings/keys)."
        log_warn "2. You accepted the host fingerprint if prompted."
        log_warn "3. The ssh-agent has the correct key (check 'ssh-add -l')."
        if confirm_action "Do you want to re-display the public key and try testing the connection again?"; then
            log_info "Public key:"
            echo -e "\033[36m"
            cat "${SSH_KEY_PATH}.pub"
            echo -e "\033[0m"
            confirm_action "Press Enter to try testing the connection again..."
            continue
        else
            log_error "Cannot proceed with cloning without successful GitHub SSH authentication."
            exit 1
        fi
    fi
done

log_step "5. Cloning Repository: $REPO_URL"
if [ -d "$CLONE_DEST" ]; then
    log_warn "Destination directory $CLONE_DEST already exists."
    if confirm_action "Do you want to attempt to pull the latest changes in $CLONE_DEST?"; then
        log_info "Attempting to pull latest changes in $CLONE_DEST..."
        cd "$CLONE_DEST" || { log_error "Could not cd to $CLONE_DEST"; exit 1; }
        if git pull; then
            log_info "Repository updated successfully."
        else
            log_warn "Failed to pull latest changes. The directory might have local modifications or other issues."
            log_warn "You may need to resolve this manually or choose to re-clone."
            if confirm_action "Do you want to remove the existing directory and re-clone?"; then
                 cd "$CLONE_DEST_PARENT" || { log_error "Could not cd to $CLONE_DEST_PARENT"; exit 1; }
                 log_info "Removing existing directory $CLONE_DEST..."
                 rm -rf "$CLONE_DEST"
                 # Proceed to clone below
            else
                log_info "Skipping repository operation."
                exit 0
            fi
        fi
        cd "$CLONE_DEST_PARENT" || { log_error "Could not cd to $CLONE_DEST_PARENT"; exit 1; } # Go back to parent
    elif confirm_action "Do you want to remove the existing directory $CLONE_DEST and re-clone?"; then
        log_info "Removing existing directory $CLONE_DEST..."
        rm -rf "$CLONE_DEST"
        # Proceed to clone below
    else
        log_info "Skipping repository operation as directory exists and user chose not to modify."
        exit 0
    fi
fi

# If directory doesn't exist or was removed, clone it
if [ ! -d "$CLONE_DEST" ]; then
    log_info "Cloning $REPO_URL into $CLONE_DEST..."
    if git clone "$REPO_URL" "$CLONE_DEST"; then
        log_info "Repository cloned successfully to $CLONE_DEST."
    else
        log_error "Failed to clone repository $REPO_URL."
        exit 1
    fi
fi

log_step "Setup Complete!"
log_info "The lab-tools repository should now be available at $CLONE_DEST."
log_info "The SSH key used for this is $SSH_KEY_PATH."

exit 0 