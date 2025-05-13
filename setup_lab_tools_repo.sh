# Loop to allow user to re-add key and test again
while true; do
    if ssh -T "$GITHUB_HOST"; then
        log_info "Successfully authenticated with GitHub!"
        break
    else
        log_warn "---------------------------------------------------------------------"
        log_warn "GitHub SSH Authentication Failed!"
        log_warn "This usually means the public SSH key shown earlier was not correctly"
        log_warn "added to your GitHub account (https://github.com/settings/keys),"
        log_warn "or there was an issue with the SSH agent."
        log_warn "Output of 'ssh -T $GITHUB_HOST' indicated a problem."
        log_warn "---------------------------------------------------------------------"
        
        if confirm_action "Would you like to: \n  1. Re-display the public key (so you can add/verify it on GitHub) \n  2. And then try testing the SSH connection to GitHub again? \nEnter 'y' to retry, or 'n' to exit the script."; then
            log_info "Okay, let's try again."
            log_info "Please ensure the following public SSH key is added to your GitHub account:"
            log_info "Go to https://github.com/settings/keys and click 'New SSH key'."
            echo -e "\033[36m" # Cyan color for key
            cat "${SSH_KEY_PATH}.pub"
            echo -e "\033[0m" # Reset color
            
            log_info "For troubleshooting, current keys in ssh-agent (-L shows public keys):
$(ssh-add -L)"
            log_info "If the key above is not listed or you see many keys, ensure the correct one is active."

            confirm_action "Press Enter when you are ready to retry the SSH connection test to GitHub..."
            # The 'while true' loop will now naturally continue and re-attempt 'ssh -T GITHUB_HOST'
        else
            log_error "GitHub SSH authentication failed. Cannot proceed with cloning the repository."
            log_error "Please manually ensure your SSH key is correctly set up for GitHub and re-run the script later."
            exit 1
        fi
    fi
done 

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

if [ "$SHOULD_GENERATE_KEY" = true ]; then # String comparison, or use (( SHOULD_GENERATE_KEY )) for arithmetic if it were 0/1
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