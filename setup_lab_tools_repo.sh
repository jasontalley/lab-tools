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