#!/bin/bash

# Script to set up SSH key for GitHub and clone the lab-tools repository.

# --- Helper Functions ---
log_info() { echo -e "\033[32m[INFO] $1\033[0m"; }
log_warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
log_error() { echo -e "\033[31m[ERROR] $1\033[0m"; }
log_step() { echo -e "\n\033[34m--- $1 ---\033[0m"; }

confirm_action() {
    # If stdin is not a TTY (e.g. when run via curl|bash), default to 'No' (return 1)
    # This prevents the script from hanging or looping on "Invalid input".
    if ! [ -t 0 ]; then
        # log_warn "Non-interactive mode detected for prompt: '$1'. Defaulting to No."
        return 1 # Default to No
    fi

    # Interactive mode (stdin is a TTY)
    while true; do
        read -r -p "$1 [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0 # Yes
                ;;
            [nN][oO]|[nN]|"") # No or empty string (default for interactive)
                return 1 # No
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

SHOULD_GENERATE_KEY=false # Default: do not generate a new key

if [ -f "$SSH_KEY_PATH" ] && [ -f "${SSH_KEY_PATH}.pub" ]; then
    log_info "SSH key pair ($SSH_KEY_PATH) already exists."
    if confirm_action "Do you want to USE this existing key? (Answering 'n' will prompt to generate a new one)"; then
        log_info "Will use the existing SSH key: $SSH_KEY_PATH."
        SHOULD_GENERATE_KEY=false
    else
        log_warn "You chose NOT to use the existing key: $SSH_KEY_PATH."
        if confirm_action "Do you want to GENERATE a NEW key pair? (This will overwrite the existing file if it has the same name)"; then
            log_info "A new SSH key pair will be generated."
            SHOULD_GENERATE_KEY=true
        else
            log_warn "You chose NOT to generate a new key either. Defaulting to attempt using the existing key: $SSH_KEY_PATH."
            # This path means user said NO to using existing, and NO to generating new.
            # Safest is to try and use what's there, or the script can't proceed with SSH.
            SHOULD_GENERATE_KEY=false 
        fi
    fi
else
    log_info "SSH key pair $SSH_KEY_PATH not found or incomplete. A new key pair needs to be generated."
    SHOULD_GENERATE_KEY=true
fi

if [ "$SHOULD_GENERATE_KEY" = true ]; then # String comparison for boolean flag
    log_info "Proceeding with SSH key generation for: $SSH_KEY_PATH"
    # Remove old keys if they exist, as we are generating a new one.
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    
    # Simplified comment for ssh-keygen to minimize potential parsing issues with complex $(hostname) outputs
    KEY_COMMENT="lab_tools_github_$(whoami)"
    log_info "Generating new 4096-bit RSA SSH key. Press Enter to accept default file location and no passphrase (recommended for automated scripts)."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$KEY_COMMENT"
    if [ $? -ne 0 ]; then
        log_error "SSH key generation failed."
        exit 1
    fi
    log_info "New SSH key pair generated successfully: $SSH_KEY_PATH"
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
else
    log_info "Skipping SSH key generation. Using existing key: $SSH_KEY_PATH"
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
    # If ssh-add failed, it might be because the key has a passphrase and we are non-interactive
    # Or the key file is problematic.
    if ! [ -t 0 ]; then # Non-interactive
        log_error "Failed to add SSH key ($SSH_KEY_PATH) to the agent in non-interactive mode."
        log_error "This key may require a passphrase. Please run this script interactively or ensure the key has no passphrase."
        exit 1
    else # Interactive, so prompt for passphrase
        log_error "Failed to add SSH key ($SSH_KEY_PATH) to the agent. It might require a passphrase."
        if ! ssh-add "$SSH_KEY_PATH"; then # Let ssh-add prompt for passphrase
            log_error "Still failed to add SSH key. Please check your key and passphrase."
            exit 1
        fi
        log_info "SSH key added to the agent (likely after passphrase)."
    fi
fi


log_info "Configuring SSH to use this key for $GITHUB_HOST..."
# Create or update SSH config
# Check if entry already exists for this host and identity file
CONFIG_ENTRY_EXISTS=false
if [ -f "$SSH_CONFIG_PATH" ]; then
    # Check for a block that specifies this Host AND this IdentityFile
    # This is a more specific check to ensure we don't just find any github.com entry
    if awk -v key="$SSH_KEY_PATH" \
        'BEGIN{found_host=0; RS=""} 
         /Host github\.com/ {found_host=1} 
         found_host && /IdentityFile / && $0 ~ "IdentityFile " key {print "found"; exit}' \
        "$SSH_CONFIG_PATH" | grep -q "found"; then
        CONFIG_ENTRY_EXISTS=true
        log_info "SSH config entry for Host $GITHUB_HOST using IdentityFile $SSH_KEY_PATH already seems to exist."
    fi
fi

if ! $CONFIG_ENTRY_EXISTS; then
    # Backup existing config if it exists
    if [ -f "$SSH_CONFIG_PATH" ]; then
        cp "$SSH_CONFIG_PATH" "${SSH_CONFIG_PATH}.bak_$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing SSH config to ${SSH_CONFIG_PATH}.bak_..."
    fi
    
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

    # Add our specific config block
    echo -e "\n# Added/Updated by lab-tools setup script for $SSH_KEY_PATH $(date)" >> "$SSH_CONFIG_PATH"
    echo -e "$DESIRED_CONFIG_BLOCK" >> "$SSH_CONFIG_PATH"
    
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

if ! [ -t 0 ]; then
    log_warn "Running in non-interactive mode. Will not prompt for GitHub key confirmation."
    log_warn "Ensure the key is added to GitHub before this script attempts to connect."
    log_warn "Pausing for 15 seconds to allow time to add the key to GitHub if needed..."
    sleep 15
else
    confirm_action "Press Enter to continue after you've added the key to GitHub (or if it was already added)..."
fi

log_info "Attempting to connect to GitHub via SSH (ssh -T $GITHUB_HOST)..."
log_info "If prompted 'Are you sure you want to continue connecting (yes/no/[fingerprint])?', please type 'yes' if in interactive mode."

# Loop to allow user to re-add key and test again
RETRY_COUNT=0
MAX_RETRIES=2 # Allow a couple of retries if interactive

while true; do
    # In non-interactive mode, ssh might prompt for host key verification. 
    # We can try to automate this with StrictHostKeyChecking=no or pre-adding github.com to known_hosts.
    # For now, we assume if non-interactive, this should ideally pass or fail without hanging.
    SSH_COMMAND="ssh -o ConnectTimeout=10"
    if ! [ -t 0 ]; then
        # Try to automatically accept new host keys if non-interactive.
        # Note: This has security implications if you don't trust the network.
        # However, for a fresh setup script, it might be acceptable for github.com.
        # A more secure way is to pre-populate known_hosts.
        SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
    fi

    if $SSH_COMMAND -T "$GITHUB_HOST"; then
        log_info "Successfully authenticated with GitHub!"
        break
    else
        log_warn "---------------------------------------------------------------------"
        log_warn "GitHub SSH Authentication Failed!"
        log_warn "This usually means the public SSH key shown earlier was not correctly"
        log_warn "added to your GitHub account (https://github.com/settings/keys),"
        log_warn "or there was an issue with the SSH agent or host key verification."
        log_warn "---------------------------------------------------------------------"
        
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if ! [ -t 0 ] || [ $RETRY_COUNT -gt $MAX_RETRIES ]; then # Non-interactive or max retries reached
            log_error "GitHub SSH authentication failed. Cannot proceed with cloning the repository."
            if ! [ -t 0 ]; then
                log_error "Running in non-interactive mode. Ensure SSH key is on GitHub and host key is accepted/known."
            else
                log_error "Max retries reached. Please manually ensure your SSH key is correctly set up."
            fi
            exit 1
        fi

        if confirm_action "Would you like to: \n  1. Re-display the public key (so you can add/verify it on GitHub) \n  2. And then try testing the SSH connection to GitHub again? (Attempt ${RETRY_COUNT}/${MAX_RETRIES}) \nEnter 'y' to retry, or 'n' to exit the script."; then
            log_info "Okay, let's try again."
            log_info "Public key:"
            echo -e "\033[36m"
            cat "${SSH_KEY_PATH}.pub"
            echo -e "\033[0m"
            log_info "For troubleshooting, current keys in ssh-agent (-L shows public keys):\n$(ssh-add -L 2>/dev/null || echo 'ssh-agent not running or no keys added')"
            confirm_action "Press Enter when you are ready to retry the SSH connection test to GitHub..."
        else
            log_error "GitHub SSH authentication failed. Cannot proceed with cloning the repository."
            log_error "Please manually ensure your SSH key is correctly set up for GitHub and re-run the script later."
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