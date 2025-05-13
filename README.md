Lab Tools
=========

A collection of shell scripts to automate the setup and management of lab hosts, particularly Raspberry Pi devices and similar Linux environments.

Available Scripts
-----------------

### 1. `pi-nvme-boot.sh`

*   **Purpose:** Configures a Raspberry Pi to boot from an NVMe SSD. This involves checking and updating the EEPROM, partitioning and formatting the NVMe drive, copying the OS from the SD card, and updating fstab/cmdline.txt for NVMe boot.
*   **Usage:** `sudo ./pi-nvme-boot.sh`
*   **Notes:** 
    *   Run as root.
    *   Designed for Raspberry Pi 4/CM4 or later models that support NVMe boot.
    *   Ensure your NVMe drive is physically connected before running.
    *   Follow on-screen prompts carefully, especially regarding data on the NVMe drive.

### 2. `repo-connect.sh`

*   **Purpose:** Sets up an SSH key for connecting to GitHub and clones the `lab-tools` repository (`git@github.com:jasontalley/lab-tools.git`). It handles SSH key generation (or using an existing key), configures SSH to use this key for `github.com`, tests the connection, and then clones the repository to `$HOME/lab-tools` by default. This script is typically the first one to run on a new lab host to get access to all other tools.
*   **Usage (on a new machine):**
    1.  Fetch the script from its source (e.g., from a known URL where it is hosted, or manually copy it).
    2.  If fetched via `curl` from a raw GitHub URL, for example:
        `curl -O https://raw.githubusercontent.com/jasontalley/lab-tools/main/repo-connect.sh`
    3.  Make it executable: `chmod +x repo-connect.sh`
    4.  Run the script: `bash ./repo-connect.sh`
*   **Notes:**
    *   Can be run as a non-root user.
    *   The script will prompt for various actions, such as whether to use an existing SSH key or generate a new one, and for installing Git if not found (requires sudo for installation).
    *   Guides the user to add the public SSH key to their GitHub account.
    *   The target clone directory and SSH key path are configurable via variables at the top of the script if a different default behavior is needed.

### 3. `manage_users.sh`

*   **Purpose:** Manages user accounts on the system based on a configuration file (`user_config.txt`). It can create users, set their shells, manage group memberships (including `sudo` access and creating groups if they don't exist), and configure passwordless sudo. It can also remove users.
*   **Configuration File (`user_config.txt` format):** `username:sudo_privileges:passwordless_sudo:groups:shell`
    *   Example: `ansible:yes:yes:docker,adm:/bin/bash`
*   **Usage:**
    *   To apply configuration from `user_config.txt`: `sudo ./manage_users.sh`
    *   To remove a user: `sudo ./manage_users.sh --remove <username>`
*   **Notes:**
    *   Run as root.
    *   User definitions are stored in `user_config.txt` in the same directory as the script.
    *   The script creates/removes user-specific files in `/etc/sudoers.d/` for passwordless sudo.

### 4. `setup_common_tools.sh`

*   **Purpose:** Performs initial system bootstrap on Debian/Ubuntu-based systems. It updates package lists, upgrades installed packages, and installs a predefined list of common development and system administration tools (e.g., `git`, `vim`, `curl`, `htop`, `build-essential`, `fail2ban`, `unattended-upgrades`).
*   **Usage:** `sudo ./setup_common_tools.sh`
*   **Notes:**
    *   Run as root.
    *   The list of packages to install can be customized by editing the `COMMON_PACKAGES` array within the script.
    *   Attempts to configure `unattended-upgrades` and enable/start `fail2ban`.

General Recommendations
-----------------------

*   Always review scripts before running them, especially if using `sudo`.
*   Make scripts executable: `chmod +x <script_name>.sh`
*   Test scripts in a non-production environment first.
