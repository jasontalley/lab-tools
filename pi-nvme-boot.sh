#!/bin/bash

# Script to configure Raspberry Pi 5 to boot from NVMe SSD

# --- Configuration ---
NVME_DEVICE="/dev/nvme0n1"
NVME_BOOT_PART="${NVME_DEVICE}p1"
NVME_ROOT_PART="${NVME_DEVICE}p2"
SD_BOOT_MOUNT_POINT="/boot/firmware" # Common for Ubuntu on Pi
# We'll need to determine the SD card's root device dynamically, or assume /

TMP_NVME_BOOT_MOUNT="/mnt/nvme_boot_temp"
TMP_NVME_ROOT_MOUNT="/mnt/nvme_root_temp"

# --- Helper Functions ---
log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; exit 1; }
confirm_action() {
    read -r -p "$1 [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- Main Script ---

# --- Check if already booting from NVMe ---
log_info "Checking current boot device..."
ROOT_DEVICE_INFO=$(findmnt -n -o SOURCE /)
# In some cases, findmnt might return something like /dev/nvme0n1p2[/@subvolume]
# We only care about the base device part for this check.
ROOT_DEVICE=$(echo "$ROOT_DEVICE_INFO" | sed 's|\[.*||g') # Remove any subvolume paths like [/blah]

if [[ "$ROOT_DEVICE" == /dev/nvme* ]]; then
    log_info "System appears to be ALREADY BOOTING from an NVMe device."
    log_info "Current root device: $ROOT_DEVICE_INFO"
    if confirm_action "This script is primarily for setting up NVMe boot when booted from an SD card. Do you want to exit the script now?"; then
        log_info "Exiting script as requested."
        exit 0
    else
        log_warn "Continuing script execution. Please be aware that you are already booting from NVMe."
        log_warn "Some operations in this script might be redundant or have unintended consequences."
    fi
else
    log_info "Current root device ($ROOT_DEVICE_INFO) does not appear to be an NVMe device. Proceeding with script."
fi
# --- End Check if already booting from NVMe ---

# 1. Sanity Checks
log_info "Performing sanity checks..."
if ! grep -q "Raspberry Pi 5" /proc/cpuinfo; then # A simple check, might need refinement
    log_warn "This script might not be running on a Raspberry Pi 5 model (based on /proc/cpuinfo)."
    # log_error "This script appears to be running on a non-Raspberry Pi 5 model." # Making it a warning for now
fi
if ! command -v rpi-eeprom-config &> /dev/null; then
    log_error "rpi-eeprom-config command not found. Please install it (e.g., sudo apt install rpi-eeprom)."
fi
if [ ! -e "$NVME_DEVICE" ]; then
    log_error "NVMe device $NVME_DEVICE not found. Ensure it's properly connected."
fi
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root. Please use sudo."
fi
for cmd in parted mkfs.ext4 mkfs.vfat rsync blkid umount mount mkdir rmdir sed tee grep; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd command not found. Please install the necessary package (e.g., dosfstools, e2fsprogs, rsync, util-linux, coreutils)."
    fi
done


log_info "Sanity checks passed."

# 2. EEPROM Check & Update
log_info "Checking EEPROM status..."
EEPROM_STATUS_OUTPUT=$(sudo rpi-eeprom-update 2>&1) # Capture stdout and stderr

if echo "$EEPROM_STATUS_OUTPUT" | grep -q "BOOTLOADER: up-to-date"; then
    log_info "EEPROM bootloader is already up-to-date according to 'rpi-eeprom-update'."
    echo "-------------------- EEPROM Status --------------------"
    echo "$EEPROM_STATUS_OUTPUT"
    echo "-------------------------------------------------------"
elif echo "$EEPROM_STATUS_OUTPUT" | grep -q "BOOTLOADER: update available"; then
    log_warn "EEPROM bootloader update is available according to 'rpi-eeprom-update'."
    echo "-------------------- Current EEPROM Status --------------------"
    echo "$EEPROM_STATUS_OUTPUT"
    echo "---------------------------------------------------------------"
    if confirm_action "It is recommended to update the EEPROM firmware. This requires running 'sudo rpi-eeprom-update -a' and then rebooting. Update now?"; then
        log_info "Attempting to apply EEPROM update using 'sudo rpi-eeprom-update -a'..."
        # Run with -a to apply. Capture output.
        APPLY_OUTPUT=$(sudo rpi-eeprom-update -a 2>&1)
        echo "-------------------- Update Apply Output (rpi-eeprom-update -a) --------------------"
        echo "$APPLY_OUTPUT"
        echo "------------------------------------------------------------------------------------"
        
        # Check if the -a command explicitly stated a reboot is required
        if echo "$APPLY_OUTPUT" | grep -qE "REBOOT REQUIRED"; then
            log_warn "EEPROM update has been applied/staged and a REBOOT IS REQUIRED for the changes to take effect."
            log_warn "After rebooting (from the SD card), please re-run this script."
            log_warn "The script will then re-verify the EEPROM status."
            if confirm_action "Reboot now?"; then
                sudo reboot
            fi
            exit 0 
        elif echo "$APPLY_OUTPUT" | grep -q "EEPROM version matching current RPi OS release"; then
            log_info "EEPROM seems to be already up-to-date or the update was applied without needing a reboot (this is uncommon if an update was truly 'available' before -a)."
            # Proceed with the script in this case, as no reboot was explicitly stated as required by the 'rpi-eeprom-update -a' command.
        else
            log_warn "EEPROM update attempt ('rpi-eeprom-update -a') finished. Its output did not clearly indicate a 'REBOOT REQUIRED', nor did it confirm it's 'matching current RPi OS release'."
            log_warn "Please review the output above carefully. If an update was made, a reboot is typically necessary."
            log_warn "If you are unsure, it's safest to reboot."
            if confirm_action "Reboot now to be safe (if you suspect an update occurred)?"; then
                sudo reboot
                exit 0
            fi
        fi
    else
        log_warn "EEPROM update skipped by user. Proceeding with current EEPROM version."
        log_warn "If the current EEPROM is too old, NVMe booting might not be reliable or possible."
    fi
else
    log_warn "Could not definitively determine EEPROM bootloader update status from 'rpi-eeprom-update' (e.g., didn't find 'BOOTLOADER: up-to-date' or 'BOOTLOADER: update available')."
    log_warn "Full output from 'rpi-eeprom-update':"
    echo "$EEPROM_STATUS_OUTPUT"
    if confirm_action "Proceed with an attempt to update EEPROM anyway (this will run 'sudo rpi-eeprom-update -a' and likely require a reboot if changes are made)?"; then
        log_info "Attempting to apply EEPROM update using 'sudo rpi-eeprom-update -a'..."
        APPLY_OUTPUT=$(sudo rpi-eeprom-update -a 2>&1)
        echo "-------------------- Update Apply Output (rpi-eeprom-update -a) --------------------"
        echo "$APPLY_OUTPUT"
        echo "------------------------------------------------------------------------------------"
        if echo "$APPLY_OUTPUT" | grep -qE "REBOOT REQUIRED"; then
            log_warn "EEPROM update has been applied/staged and a REBOOT IS REQUIRED for the changes to take effect."
            log_warn "After rebooting (from the SD card), please re-run this script."
            if confirm_action "Reboot now?"; then
                sudo reboot
            fi
            exit 0
        else
             log_warn "EEPROM update attempt ('rpi-eeprom-update -a') finished. Its output did not clearly indicate a 'REBOOT REQUIRED'. Please review the output."
             log_warn "Proceeding with the script, but ensure your EEPROM is suitable for NVMe boot if no update was confirmed."
        fi
    else
        log_warn "EEPROM update skipped by user."
    fi
fi

# 3. User Choice for NVMe Drive
log_info "Choose how to proceed with the NVMe drive ($NVME_DEVICE):"
PS3="Enter your choice (1 or 2): "
options=("Format NVMe and clone SD card OS" "Attempt to use existing OS on NVMe (NOT IMPLEMENTED YET)")
select opt in "${options[@]}"; do
    case $REPLY in # Use $REPLY for numeric input with select
        1)
            log_info "Proceeding with: ${options[0]}"
            # Path A
            break
            ;;
        2)
            log_error "Option '${options[1]}' is not yet implemented. Exiting."
            # Path B - To be implemented
            exit 1
            ;;
        *) log_info "Invalid option $REPLY. Please enter 1 or 2.";;
    esac
done


# --- PATH A: Format NVMe and Clone SD Card OS ---

# 4. Confirmation before WIPE
if ! confirm_action "WARNING: ALL data on $NVME_DEVICE will be ERASED. Continue with formatting?"; then
    log_info "Operation cancelled by user."
    exit 0
fi

# 5. Unmount any existing NVMe partitions (just in case)
log_info "Attempting to unmount any existing partitions on $NVME_DEVICE..."
sudo umount "${NVME_DEVICE}p*" &>/dev/null # Best effort

# 6. Partition NVMe
log_info "Partitioning $NVME_DEVICE..."
sudo parted -s $NVME_DEVICE mklabel gpt
sudo parted -s $NVME_DEVICE mkpart primary fat32 1MiB 513MiB # 512MiB boot partition
sudo parted -s $NVME_DEVICE set 1 boot on # Set boot flag for ESP
sudo parted -s $NVME_DEVICE mkpart primary ext4 513MiB 100%  # Root partition uses the rest
sudo partprobe $NVME_DEVICE # Inform OS of partition table changes
sleep 3 # Give OS time to recognize new partitions

# Check if partitions were created
if [ ! -b "$NVME_BOOT_PART" ] || [ ! -b "$NVME_ROOT_PART" ]; then
    log_error "Failed to create partitions on $NVME_DEVICE. Check dmesg or parted output."
fi
log_info "Partitions $NVME_BOOT_PART and $NVME_ROOT_PART created."

# 7. Format Partitions
log_info "Formatting NVMe partitions..."
if ! sudo mkfs.vfat -F 32 -n system-boot $NVME_BOOT_PART; then
    log_error "Failed to format $NVME_BOOT_PART as vfat."
fi
if ! sudo mkfs.ext4 -F -L rootfs $NVME_ROOT_PART; then
    log_error "Failed to format $NVME_ROOT_PART as ext4."
fi
log_info "NVMe partitions formatted."

# 8. Create Mount Points & Mount NVMe Partitions
log_info "Creating temporary mount points..."
sudo mkdir -p $TMP_NVME_BOOT_MOUNT $TMP_NVME_ROOT_MOUNT

log_info "Mounting NVMe partitions..."
if ! sudo mount $NVME_ROOT_PART $TMP_NVME_ROOT_MOUNT; then
    log_error "Failed to mount $NVME_ROOT_PART at $TMP_NVME_ROOT_MOUNT."
fi

# Ensure the target mount point for the boot partition exists within the mounted root
sudo mkdir -p "$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT" 
if ! sudo mount $NVME_BOOT_PART "$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT"; then
    log_warn "Attempting to clean up $TMP_NVME_ROOT_MOUNT due to boot mount failure."
    sudo umount $TMP_NVME_ROOT_MOUNT &>/dev/null
    log_error "Failed to mount $NVME_BOOT_PART at $TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT."
fi
log_info "NVMe partitions mounted."

# 9. Copy System Files (rsync)
log_info "Copying root filesystem from SD card to NVMe (this may take a while)..."
# Exclude pseudo-filesystems, the NVMe temp mounts, and other things not to copy.
# Added /var/log/* to reduce copied data for faster testing if needed, can be removed.
# Also ensure the destination mount point itself isn't a source for recursion if it was under /mnt
if ! sudo rsync -axHAWX --numeric-ids --info=progress2 --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","$SD_BOOT_MOUNT_POINT/*","/lost+found","/var/log/*"} / "$TMP_NVME_ROOT_MOUNT/"; then
    log_error "Rsync of root filesystem failed."
fi

log_info "Copying boot files from $SD_BOOT_MOUNT_POINT to $TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT..."
# We need to be careful here. If $SD_BOOT_MOUNT_POINT is already a mount point for the SD card's boot partition,
# we copy its *contents*. The trailing slash on source is important for rsync.
if ! sudo rsync -axHAWX --numeric-ids --info=progress2 "$SD_BOOT_MOUNT_POINT/" "$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT/"; then
    log_error "Rsync of boot files failed."
fi
log_info "System files copied."

# 10. Update fstab on NVMe
log_info "Updating fstab on NVMe..."
NVME_BOOT_PARTUUID=$(sudo blkid -s PARTUUID -o value $NVME_BOOT_PART)
NVME_ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value $NVME_ROOT_PART)

if [ -z "$NVME_BOOT_PARTUUID" ] || [ -z "$NVME_ROOT_PARTUUID" ]; then
    log_error "Could not retrieve PARTUUIDs for NVMe partitions. Cannot update fstab."
fi

FSTAB_FILE="$TMP_NVME_ROOT_MOUNT/etc/fstab"
# Backup original fstab on NVMe
sudo cp $FSTAB_FILE "${FSTAB_FILE}.bak"
log_info "Backed up NVMe fstab to ${FSTAB_FILE}.bak"

# Comment out existing / and /boot/firmware lines from original SD fstab that might be problematic
# This targets lines starting with common identifiers (PARTUUID, UUID, LABEL, /dev/mmcblk0p) followed by / or /boot/firmware
# It prepends a # only if the line doesn't already start with #
sudo sed -i -E '/^#/! s~^(PARTUUID=[^[:space:]]+|UUID=[^[:space:]]+|LABEL=[^[:space:]]+|/dev/mmcblk0p[0-9]+)([[:space:]]+/boot/firmware)~#&~' $FSTAB_FILE
sudo sed -i -E '/^#/! s~^(PARTUUID=[^[:space:]]+|UUID=[^[:space:]]+|LABEL=[^[:space:]]+|/dev/mmcblk0p[0-9]+)([[:space:]]+/)~#&~' $FSTAB_FILE


# Add new entries. Ensure no duplicate empty lines if fstab was empty.
# Add a header for our entries
echo -e "\n# Entries for NVMe Boot (added by script)" | sudo tee -a $FSTAB_FILE > /dev/null
echo "PARTUUID=$NVME_ROOT_PARTUUID  /               ext4    defaults,noatime 0 1" | sudo tee -a $FSTAB_FILE > /dev/null
echo "PARTUUID=$NVME_BOOT_PARTUUID $SD_BOOT_MOUNT_POINT vfat    defaults         0 2" | sudo tee -a $FSTAB_FILE > /dev/null

log_info "fstab updated on NVMe. Contents:"
cat $FSTAB_FILE

# 11. Update cmdline.txt on NVMe
log_info "Updating cmdline.txt on NVMe..."
CMDLINE_FILE="$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT/cmdline.txt"
if [ ! -f "$CMDLINE_FILE" ]; then
    # Attempt to locate cmdline.txt if not in the primary spot, e.g. for non-Ubuntu Pi OS
    ALT_CMDLINE_FILE="$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT/firmware/cmdline.txt" # Some RPi OS might nest it
    if [ -f "$ALT_CMDLINE_FILE" ]; then
        CMDLINE_FILE="$ALT_CMDLINE_FILE"
        log_info "Found cmdline.txt at alternative path: $CMDLINE_FILE"
    else
        log_error "cmdline.txt not found at $TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT/cmdline.txt or typical alternative locations!"
    fi
fi

sudo cp "$CMDLINE_FILE" "${CMDLINE_FILE}.bak"
log_info "Backed up NVMe cmdline.txt to ${CMDLINE_FILE}.bak"

# Replace root=... with root=PARTUUID=<nvme_root_partuuid>
# This regex tries to capture various forms of root= (PARTUUID, UUID, LABEL, /dev/...)
# It will replace the first occurrence of root= followed by non-space characters.
# Ensures that if multiple root= entries exist (which is bad), only the first is changed.
# A more robust approach might be to remove all root= arguments and then add the new one.
CURRENT_CMDLINE_CONTENT=$(cat "$CMDLINE_FILE")
NEW_CMDLINE_CONTENT=$(echo "$CURRENT_CMDLINE_CONTENT" | sed "s|root=[^ ]*|root=PARTUUID=$NVME_ROOT_PARTUUID|1")
echo "$NEW_CMDLINE_CONTENT" | sudo tee "$CMDLINE_FILE" > /dev/null


# Ensure rootwait is there (it usually is)
if ! grep -q "rootwait" "$CMDLINE_FILE"; then
    sudo sed -i -E 's~($)~ rootwait~' "$CMDLINE_FILE" # Add to end if not present
    log_info "Added 'rootwait' to cmdline.txt"
fi

log_info "cmdline.txt updated on NVMe. Contents:"
cat "$CMDLINE_FILE"


# 12. Configure Boot Order in EEPROM
log_info "Configuring EEPROM boot order for NVMe first..."
CURRENT_EEPROM_CONFIG_FILE="/tmp/current_eeprom.conf"
sudo rpi-eeprom-config > "$CURRENT_EEPROM_CONFIG_FILE"

# Desired: NVMe, SD, USB, REPEAT -> 0xf416 (6=NVME, 1=SD, 4=USB)
# Let's make it configurable or safer
TARGET_BOOT_ORDER="0xf416" # NVMe, SD, USB, REPEAT
NEW_BOOT_ORDER_LINE="BOOT_ORDER=$TARGET_BOOT_ORDER"

MODIFIED_EEPROM_CONFIG_FILE="/tmp/modified_eeprom.conf"
if grep -q "^BOOT_ORDER=" "$CURRENT_EEPROM_CONFIG_FILE"; then
    sed "s/^BOOT_ORDER=.*/$NEW_BOOT_ORDER_LINE/" "$CURRENT_EEPROM_CONFIG_FILE" > "$MODIFIED_EEPROM_CONFIG_FILE"
else
    cp "$CURRENT_EEPROM_CONFIG_FILE" "$MODIFIED_EEPROM_CONFIG_FILE"
    echo "" >> "$MODIFIED_EEPROM_CONFIG_FILE" # Ensure newline if BOOT_ORDER is missing and file doesn't end with one
    echo "$NEW_BOOT_ORDER_LINE" >> "$MODIFIED_EEPROM_CONFIG_FILE"
fi

# Apply the new configuration
log_info "Applying new EEPROM configuration..."
if sudo rpi-eeprom-config --apply "$MODIFIED_EEPROM_CONFIG_FILE"; then
    log_info "EEPROM configuration applied. A reboot is usually needed for this to take full effect if BOOT_ORDER changed."
    # Verify by reading it back
    sleep 1
    VERIFY_BOOT_ORDER=$(sudo rpi-eeprom-config | grep "^BOOT_ORDER=")
    if [[ "$VERIFY_BOOT_ORDER" == "$NEW_BOOT_ORDER_LINE" ]]; then
        log_info "EEPROM BOOT_ORDER successfully updated to $TARGET_BOOT_ORDER."
    else
        log_warn "EEPROM BOOT_ORDER update may not have reflected immediately or an issue occurred. Expected '$NEW_BOOT_ORDER_LINE', got '$VERIFY_BOOT_ORDER'"
        log_warn "This could be due to pending EEPROM updates from an earlier step requiring a reboot first."
    fi
else
    log_warn "Failed to apply EEPROM configuration using --apply. Original config was:"
    cat "$CURRENT_EEPROM_CONFIG_FILE"
    log_warn "You may need to set BOOT_ORDER manually, e.g., using: sudo rpi-eeprom-config --edit"
    log_warn "Set BOOT_ORDER to $TARGET_BOOT_ORDER (or similar, prioritizing NVMe '6')."
fi
rm "$CURRENT_EEPROM_CONFIG_FILE" "$MODIFIED_EEPROM_CONFIG_FILE"


# 13. Unmount NVMe Partitions
log_info "Unmounting NVMe partitions..."
sync # Ensure all writes are flushed
if ! sudo umount "$TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT"; then
    log_warn "Could not unmount NVMe boot partition. Manual unmount might be needed: $TMP_NVME_ROOT_MOUNT$SD_BOOT_MOUNT_POINT"
fi
if ! sudo umount $TMP_NVME_ROOT_MOUNT; then
    log_warn "Could not unmount NVMe root partition. Manual unmount might be needed: $TMP_NVME_ROOT_MOUNT"
fi
sudo rmdir $TMP_NVME_BOOT_MOUNT $TMP_NVME_ROOT_MOUNT &>/dev/null # Clean up mount point dirs

# 14. Final Instructions
log_info "--- NVMe Setup Process (Path A) Completed ---"
log_info "The system has been copied to $NVME_DEVICE."
log_info "The EEPROM boot order has been set to prioritize NVMe ($TARGET_BOOT_ORDER)."
log_info "It is now recommended to:"
log_info "1. Shut down the Raspberry Pi (e.g., sudo shutdown now)."
log_info "2. REMOVE THE SD CARD."
log_info "3. Power on the Raspberry Pi."
log_info "It should now boot from the NVMe SSD."
log_info "If it fails to boot, re-insert the SD card (NVMe can remain attached), boot from SD, and check logs/config (especially fstab and cmdline.txt on NVMe)."
log_info "Backup copies of the original fstab and cmdline.txt were made with a .bak extension on the NVMe drive."

if confirm_action "Shutdown now?"; then
    sudo shutdown now
fi

exit 0