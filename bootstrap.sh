#!/bin/sh
#
# Alpine Linux Bootstrap Script for Raspberry Pi 5
#
# This script performs post-installation configuration including:
# - User privilege setup with doas
# - Network and WiFi configuration (via NetworkManager)
# - Essential package installation
#
# Usage: Run as root or via doas
#   doas ./bootstrap.sh
#
# Author: Cristian Cristea
#

set -e  # Exit on any error

# ==============================================================================
# SCRIPT DIRECTORY
# ==============================================================================
# Determine the directory where the script and configs are located
# This must be done early so we can source common utilities

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ==============================================================================
# SOURCE COMMON UTILITIES
# ==============================================================================
# Source common functions (includes root check)

. "${SCRIPT_DIR}/scripts/common.sh"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Load configuration from bootstrap.env file

BOOTSTRAP_ENV_FILE="${SCRIPT_DIR}/bootstrap.env"

if [ ! -f "$BOOTSTRAP_ENV_FILE" ]; then
    echo "Error: Configuration file not found: ${BOOTSTRAP_ENV_FILE}"
    echo "Please copy bootstrap.env.example to bootstrap.env and configure it."
    exit 1
fi

# Source the environment file
. "$BOOTSTRAP_ENV_FILE"

# Lock permissions on the env file (contains secrets)
chmod 600 "$BOOTSTRAP_ENV_FILE"

# Raspberry Pi specific packages (kept in script as they rarely change)
RPI_PACKAGES="
    raspberrypi-bootloader-cutdown
    raspberrypi-utils
    linux-rpi
    linux-firmware-brcm
    cloud-utils-growpart
    e2fsprogs-extra
    fish
"

# ==============================================================================
# COLOUR DEFINITIONS FOR OUTPUT
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Colour

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Print an informational message
info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

# Print a success message
success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

# Print a warning message
warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

# Print an error message and exit
error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
    exit 1
}

# Print a section header
section() {
    printf "\n${GREEN}=== %s ===${NC}\n\n" "$1"
}

# Copy a config file from configs directory
install_config() {
    local src="$1"
    local dest="$2"
    local mode="${3:-644}"
    
    if [ ! -f "${CONFIGS_DIR}/${src}" ]; then
        error "Config file not found: ${CONFIGS_DIR}/${src}"
    fi
    
    mkdir -p "$(dirname "$dest")"
    cp "${CONFIGS_DIR}/${src}" "$dest"
    chmod "$mode" "$dest"
}

# Install a config file to user's home directory
install_user_config() {
    src="$1"
    dest="$2"
    mode="${3:-644}"
    
    if [ -z "$ACTUAL_USER" ]; then
        warn "No target user, skipping user config: $src"
        return 1
    fi
    
    user_home=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    full_dest="${user_home}/${dest}"
    
    if [ ! -f "${CONFIGS_DIR}/${src}" ]; then
        error "Config file not found: ${CONFIGS_DIR}/${src}"
    fi
    
    mkdir -p "$(dirname "$full_dest")"
    cp "${CONFIGS_DIR}/${src}" "$full_dest"
    chmod "$mode" "$full_dest"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$full_dest"
    
    # Also chown parent directories up to .config
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "${user_home}/.config"
}

# ==============================================================================
# SAFETY CHECKS
# ==============================================================================

section "Running Safety Checks"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Please use: doas $0"
fi
success "Running as root"

# Check configs directory exists
if [ ! -d "$CONFIGS_DIR" ]; then
    error "Configs directory not found: $CONFIGS_DIR"
fi
success "Configs directory found: $CONFIGS_DIR"

# Determine the actual user
if [ -n "$TARGET_USER" ]; then
    # Use explicitly configured target user
    ACTUAL_USER="$TARGET_USER"
    info "Using configured target user: $ACTUAL_USER"
elif [ -n "$DOAS_USER" ]; then
    ACTUAL_USER="$DOAS_USER"
    info "Detected target user from doas: $ACTUAL_USER"
elif [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    info "Detected target user from sudo: $ACTUAL_USER"
else
    # If run directly as root, we cannot determine the target user
    warn "Cannot determine target user. Set TARGET_USER in configuration."
    warn "User-specific configuration will be skipped."
    ACTUAL_USER=""
fi

# Verify the target user exists
if [ -n "$ACTUAL_USER" ] && ! id "$ACTUAL_USER" >/dev/null 2>&1; then
    error "Target user '$ACTUAL_USER' does not exist"
fi

# Verify we're on Alpine Linux
if [ ! -f /etc/alpine-release ]; then
    error "This script is designed for Alpine Linux only"
fi
ALPINE_VERSION=$(cat /etc/alpine-release)
success "Detected Alpine Linux version: $ALPINE_VERSION"

# Check network connectivity
info "Checking network connectivity..."
if ! ping -c 1 -W 5 dl-cdn.alpinelinux.org >/dev/null 2>&1; then
    warn "Cannot reach Alpine package servers. Package installation may fail."
    warn "Continuing anyway - network may become available after configuration."
else
    success "Network connectivity verified"
fi

# ==============================================================================
# REPOSITORY CONFIGURATION
# ==============================================================================

section "Configuring Package Repositories"

# Enable community repository if not already enabled
info "Checking package repositories..."
REPOS_FILE="/etc/apk/repositories"

if [ -f "$REPOS_FILE" ]; then
    # Check if community repo is commented out and uncomment it
    if grep -q "^#.*community" "$REPOS_FILE"; then
        info "Enabling community repository..."
        sed -i 's|^#\(.*community\)|\1|' "$REPOS_FILE"
        success "Community repository enabled"
    elif grep -q "community" "$REPOS_FILE"; then
        success "Community repository already enabled"
    else
        # Add community repo based on existing main repo
        MAIN_REPO=$(grep "^http.*main" "$REPOS_FILE" | head -1)
        if [ -n "$MAIN_REPO" ]; then
            COMMUNITY_REPO=$(echo "$MAIN_REPO" | sed 's|/main|/community|')
            echo "$COMMUNITY_REPO" >> "$REPOS_FILE"
            info "Added community repository: $COMMUNITY_REPO"
        fi
        success "Community repository configured"
    fi
else
    warn "Repositories file not found: $REPOS_FILE"
fi

# Display current repositories
info "Active repositories:"
grep -v "^#" "$REPOS_FILE" 2>/dev/null | grep -v "^$" | while read -r repo; do
    info "  - $repo"
done

# ==============================================================================
# DOCKER SERVICES PRE-CHECK
# ==============================================================================
# Check if user wants to set up Docker services before installing packages

INSTALL_DOCKER_PACKAGES=""

if [ -d "${SCRIPT_DIR}/services" ]; then
    # Check if any Docker services are available
    for service_dir in "${SCRIPT_DIR}/services"/*/; do
        if [ -d "$service_dir" ] && [ -f "${service_dir}/setup.sh" ]; then
            INSTALL_DOCKER_PACKAGES="ask"
            break
        fi
    done
    
    if [ "$INSTALL_DOCKER_PACKAGES" = "ask" ]; then
        printf "\n"
        info "Docker services are available for installation."
        printf "${BLUE}[?]${NC} Do you want to set up Docker services? [Y/n] "
        read -r docker_answer
        if [ "$docker_answer" = "n" ] || [ "$docker_answer" = "N" ]; then
            info "Skipping Docker packages."
        else
            INSTALL_DOCKER_PACKAGES="yes"
            info "Docker packages will be installed."
        fi
        printf "\n"
    fi
fi

# Add Docker packages if needed
if [ "$INSTALL_DOCKER_PACKAGES" = "yes" ]; then
    PACKAGES="${PACKAGES} docker docker-cli-compose inotify-tools"
fi

# ==============================================================================
# PACKAGE INSTALLATION (EARLY)
# ==============================================================================
# Install packages early so fish is available for shell configuration.
# Fish shell will be set as the default interactive shell for the user.

section "Installing Packages"

info "Updating package repository..."
apk update
success "Package repository updated"

# Install Raspberry Pi specific packages
info "Installing Raspberry Pi packages..."
for pkg in ${RPI_PACKAGES}; do
    info "  - $pkg"
done
# shellcheck disable=SC2086
apk add --no-cache ${RPI_PACKAGES}
success "Raspberry Pi packages installed"

# Display Raspberry Pi tools help
printf "\n"
info "Raspberry Pi Tools Quick Reference:"
info ""
info "  System Information:"
info "    vcgencmd measure_temp       - Show CPU temperature"
info "    vcgencmd get_throttled      - Check throttling status"
info "    vcgencmd measure_volts      - Show voltage levels"
info "    vcgencmd get_mem arm        - Show ARM memory split"
info "    vcgencmd get_mem gpu        - Show GPU memory split"
info ""
info "  Hardware:"
info "    cat /proc/device-tree/model - Show Raspberry Pi model"
info "    pinctrl                     - GPIO pin control utility"
info "    dtoverlay -l                - List active device tree overlays"
info ""

# Install user packages
info "Installing user packages..."
for pkg in ${PACKAGES}; do
    info "  - $pkg"
done
# shellcheck disable=SC2086
apk add --no-cache ${PACKAGES}
success "User packages installed"

# Display Alpine Linux help
printf "\n"
info "Alpine Linux Quick Reference:"
info ""
info "  Package Management (apk):"
info "    apk update                  - Update package index"
info "    apk upgrade                 - Upgrade all installed packages"
info "    apk add <package>           - Install a package"
info "    apk del <package>           - Remove a package"
info "    apk search <name>           - Search for packages"
info "    apk info                    - List installed packages"
info "    apk info <package>          - Show package details"
info ""
info "  System Updates:"
info "    apk update && apk upgrade   - Full system update"
info "    apk upgrade --available     - Upgrade to latest available versions"
info "    apk fix                     - Repair or reinstall packages"
info ""
info "  Services (OpenRC):"
info "    rc-service <svc> start      - Start a service"
info "    rc-service <svc> stop       - Stop a service"
info "    rc-service <svc> restart    - Restart a service"
info "    rc-service <svc> status     - Check service status"
info "    rc-update add <svc> default - Enable service at boot"
info "    rc-update del <svc> default - Disable service at boot"
info "    rc-status                   - Show all services status"
info ""
info "  System:"
info "    setup-alpine                - Re-run Alpine setup"
info "    cat /etc/alpine-release     - Show Alpine version"
info "    reboot                      - Reboot the system"
info "    poweroff                    - Shutdown the system"
info ""

# Install additional required packages
info "Installing additional system packages..."
apk add --no-cache doas shadow openssh sudo
success "System packages installed"

# Configure sudo for wheel group
info "Configuring sudo for wheel group..."
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/wheel << 'EOF'
# Allow members of wheel group to execute any command
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/wheel
success "sudo configured for wheel group"

# ==============================================================================
# DISK EXPANSION CHECK
# ==============================================================================
# Note: Both growpart and resize2fs support online operations (while mounted).
# This is safe to run on the active root partition.

section "Checking Disk Space"

# Detect root device and partition using /proc/mounts (works on Alpine)
ROOT_PART=$(awk '$2 == "/" {print $1}' /proc/mounts | head -n1)

# Extract disk and partition number
# Device naming formats:
#   SD card:  /dev/mmcblk0p2  -> disk: /dev/mmcblk0,  partition: 2
#   NVMe SSD: /dev/nvme0n1p2  -> disk: /dev/nvme0n1,  partition: 2
#   SATA/USB: /dev/sda2       -> disk: /dev/sda,      partition: 2
if echo "$ROOT_PART" | grep -q "mmcblk\|nvme"; then
    # SD card or NVMe: partition number prefixed with 'p'
    ROOT_DISK=$(echo "$ROOT_PART" | sed 's/p[0-9]*$//')
    PART_NUM=$(echo "$ROOT_PART" | grep -o 'p[0-9]*$' | tr -d 'p')
else
    # SATA/USB disk: partition number directly appended
    ROOT_DISK=$(echo "$ROOT_PART" | sed 's/[0-9]*$//')
    PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')
fi

info "Root partition: $ROOT_PART"
info "Root disk: $ROOT_DISK (partition $PART_NUM)"

if [ -b "$ROOT_DISK" ] && [ -n "$PART_NUM" ]; then
    # Try to expand partition (growpart supports online expansion)
    # It will output NOCHANGE if already at maximum size
    info "Checking if partition can be expanded..."
    
    GROWPART_OUTPUT=$(growpart "$ROOT_DISK" "$PART_NUM" 2>&1) || true
    
    if echo "$GROWPART_OUTPUT" | grep -q "NOCHANGE"; then
        success "Root partition already uses full disk"
    elif echo "$GROWPART_OUTPUT" | grep -q "CHANGED"; then
        success "Partition expanded"
        
        # Resize filesystem online (ext4 supports this)
        info "Resizing filesystem (online)..."
        resize2fs "$ROOT_PART"
        success "Filesystem resized"
        
        # Sync to ensure changes are written
        sync
    else
        warn "Could not expand partition: $GROWPART_OUTPUT"
    fi
else
    warn "Could not detect root disk configuration"
fi

# Show current disk usage
DISK_USAGE=$(df -h / | tail -n1 | awk '{printf "%s used of %s (%s)", $3, $2, $5}')
info "Current disk usage: $DISK_USAGE"

# ==============================================================================
# RASPBERRY PI MODEL DETECTION
# ==============================================================================

section "Detecting Raspberry Pi Model"

RPI_MODEL=""
if [ -f /proc/device-tree/model ]; then
    RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
fi

if echo "$RPI_MODEL" | grep -q "Raspberry Pi 5"; then
    RPI_VERSION="5"
    SSH_PORT="2005"
    success "Detected Raspberry Pi 5"
elif echo "$RPI_MODEL" | grep -q "Raspberry Pi 4"; then
    RPI_VERSION="4"
    SSH_PORT="2004"
    success "Detected Raspberry Pi 4"
else
    RPI_VERSION="5"
    SSH_PORT="2005"
    warn "Could not detect Raspberry Pi model, defaulting to RPi5"
fi

# ==============================================================================
# BOOT CONFIGURATION
# ==============================================================================

section "Installing Boot Configuration"

info "Installing Raspberry Pi boot configuration (usercfg.txt)..."
install_config "boot/usercfg.txt" "/boot/usercfg.txt" 644
success "Boot configuration installed to /boot/usercfg.txt"
warn "Boot configuration changes require a reboot to take effect"

# ==============================================================================
# USER PRIVILEGE CONFIGURATION
# ==============================================================================

section "Configuring User Privileges"

# Add user to wheel group
if [ -n "$ACTUAL_USER" ]; then
    if id -nG "$ACTUAL_USER" | grep -qw wheel; then
        success "User '$ACTUAL_USER' is already in wheel group"
    else
        info "Adding user '$ACTUAL_USER' to wheel group..."
        addgroup "$ACTUAL_USER" wheel
        success "User '$ACTUAL_USER' added to wheel group"
    fi
fi

# Configure doas to allow wheel group members
info "Configuring doas for wheel group..."
install_config "doas.d/wheel.conf" "/etc/doas.d/wheel.conf" 600
success "doas configured: wheel group members can now use doas"

# ==============================================================================
# USER ACCOUNT CONFIGURATION
# ==============================================================================

section "Configuring User Account"

if [ -n "$ACTUAL_USER" ]; then
    # Set user full name (GECOS field)
    if [ -n "$USER_FULL_NAME" ]; then
        info "Setting full name for user '$ACTUAL_USER'..."
        chfn -f "$USER_FULL_NAME" "$ACTUAL_USER"
        success "Full name set to '$USER_FULL_NAME'"
    fi
    
    # Set user password
    info "Setting password for user '$ACTUAL_USER'..."
    echo "$ACTUAL_USER:$USER_PASSWORD" | chpasswd
    success "Password set for user '$ACTUAL_USER'"
    
    # Set user shell to fish (fish is installed as part of RPI_PACKAGES)
    info "Setting shell to fish for user '$ACTUAL_USER'..."
    info "Fish shell provides enhanced features like syntax highlighting, autosuggestions, and tab completions."
    FISH_PATH=$(command -v fish)
    
    if [ -z "$FISH_PATH" ]; then
        error "Fish shell not found. Package installation may have failed."
    fi
    
    # Ensure fish is in /etc/shells
    if ! grep -q "^${FISH_PATH}$" /etc/shells 2>/dev/null; then
        echo "$FISH_PATH" >> /etc/shells
        info "Added fish to /etc/shells"
    fi
    
    chsh -s "$FISH_PATH" "$ACTUAL_USER"
    success "Shell set to fish for user '$ACTUAL_USER'"
    info "The user will use fish shell on next login."
    
    # Set root shell to fish as well
    info "Setting shell to fish for root user..."
    chsh -s "$FISH_PATH" root
    success "Shell set to fish for root user"
    
    # Configure SSH key (with idempotency check)
    info "Configuring SSH key for user '$ACTUAL_USER'..."
    USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    SSH_DIR="${USER_HOME}/.ssh"
    AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
    
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # Only add key if not already present
    if [ -n "$USER_SSH_KEY" ]; then
        if [ -f "$AUTHORIZED_KEYS" ] && grep -qF "$USER_SSH_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
            success "SSH key already configured for user '$ACTUAL_USER'"
        else
            echo "$USER_SSH_KEY" >> "$AUTHORIZED_KEYS"
            chmod 600 "$AUTHORIZED_KEYS"
            chown -R "$ACTUAL_USER:$ACTUAL_USER" "$SSH_DIR"
            success "SSH key configured for user '$ACTUAL_USER'"
        fi
    else
        warn "No SSH key configured"
    fi
else
    warn "No target user set, skipping user account configuration"
fi

# ==============================================================================
# USER APPLICATION CONFIGS
# ==============================================================================

section "Installing User Application Configs"

if [ -n "$ACTUAL_USER" ]; then
    # Fish shell config
    info "Installing fish configuration..."
    install_user_config "fish/config.fish" ".config/fish/config.fish"
    success "Fish config installed"
    
    # Deploy common Docker service functions if Docker services are used
    if [ "$INSTALL_DOCKER_PACKAGES" = "yes" ] && [ -f "${SCRIPT_DIR}/services/common.fish" ]; then
        info "Installing common Docker service functions..."
        user_home=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
        fish_confdir="${user_home}/.config/fish/conf.d"
        mkdir -p "$fish_confdir"
        cp "${SCRIPT_DIR}/services/common.fish" "${fish_confdir}/00-docker-services-common.fish"
        chmod 644 "${fish_confdir}/00-docker-services-common.fish"
        chown "${ACTUAL_USER}:${ACTUAL_USER}" "${fish_confdir}/00-docker-services-common.fish"
        success "Common Docker service functions installed (loads first)"
    fi
    
    # Bat config
    info "Installing bat configuration..."
    install_user_config "bat/config" ".config/bat/config"
    success "Bat config installed"
    
    # Neovim config
    info "Installing neovim configuration..."
    install_user_config "nvim/init.lua" ".config/nvim/init.lua"
    install_user_config "nvim/lua/config/set.lua" ".config/nvim/lua/config/set.lua"
    success "Neovim config installed"
    
    # Create symlinks for root user to share the same configs
    info "Linking configs for root user..."
    user_home=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    mkdir -p /root/.config
    
    # Remove existing root configs and create symlinks
    rm -rf /root/.config/fish
    rm -rf /root/.config/bat
    rm -rf /root/.config/nvim
    
    ln -sf "${user_home}/.config/fish" /root/.config/fish
    ln -sf "${user_home}/.config/bat" /root/.config/bat
    ln -sf "${user_home}/.config/nvim" /root/.config/nvim
    
    success "Root user configs linked to ${ACTUAL_USER}'s configs"
    info "Root and sudo users will have access to all fish functions including Docker service functions"
else
    warn "Skipping user configs - no target user configured"
fi

# ==============================================================================
# SSH SERVER CONFIGURATION
# ==============================================================================

section "Configuring SSH Server"

# Configure SSH using drop-in directory (idempotent)
info "Configuring SSH daemon..."
mkdir -p /etc/ssh/sshd_config.d

# Check if Include directive exists in main config
if ! grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
    # Add Include directive at the beginning of sshd_config
    if [ -f /etc/ssh/sshd_config ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        {
            echo "# Include drop-in configurations"
            echo "Include /etc/ssh/sshd_config.d/*.conf"
            echo ""
            cat /etc/ssh/sshd_config.backup
        } > /etc/ssh/sshd_config
        info "Added Include directive to sshd_config"
    fi
fi

# Generate SSH config dynamically based on configuration
# Default to yes if not set (backward compatibility)
SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"

# Validate SSH_PASSWORD_AUTH value
if [ "$SSH_PASSWORD_AUTH" != "yes" ] && [ "$SSH_PASSWORD_AUTH" != "no" ]; then
    warn "Invalid SSH_PASSWORD_AUTH value '${SSH_PASSWORD_AUTH}', defaulting to 'yes'"
    SSH_PASSWORD_AUTH="yes"
fi

# Warn if disabling password auth without SSH key configured
if [ "$SSH_PASSWORD_AUTH" = "no" ] && [ -z "$USER_SSH_KEY" ]; then
    error "Cannot disable password authentication: USER_SSH_KEY is not configured. Configure your SSH key first!"
fi

# Generate SSH config file
{
    echo "# SSH configuration added by bootstrap script"
    echo "# Uses sshd_config.d drop-in to avoid modifying main config"
    echo "# Raspberry Pi ${RPI_VERSION} configuration"
    echo ""
    echo "Port ${SSH_PORT}"
    if [ "$SSH_PASSWORD_AUTH" = "yes" ]; then
        echo "PasswordAuthentication yes"
    else
        echo "PasswordAuthentication no"
    fi
    echo "PubkeyAuthentication yes"
    echo "PermitRootLogin no"
} > /etc/ssh/sshd_config.d/99-bootstrap.conf

chmod 600 /etc/ssh/sshd_config.d/99-bootstrap.conf

# Build success message
if [ "$SSH_PASSWORD_AUTH" = "yes" ]; then
    AUTH_METHODS="password auth, pubkey auth"
else
    AUTH_METHODS="pubkey auth only (password disabled)"
fi
success "SSH configured (port ${SSH_PORT}, ${AUTH_METHODS}, root login disabled)"

# Enable and start SSH service
info "Enabling SSH service..."
rc-update add sshd default 2>/dev/null || true
success "SSH service enabled at boot"

info "Starting SSH service..."
rc-service sshd restart 2>/dev/null || warn "Could not restart SSH (may require reboot)"
success "SSH server configuration complete"

# ==============================================================================
# MOTD CONFIGURATION
# ==============================================================================

section "Configuring Message of the Day"

info "Setting MOTD for Raspberry Pi ${RPI_VERSION}..."
install_config "motd/rpi${RPI_VERSION}" "/etc/motd" 644
success "MOTD configured"

# ==============================================================================
# DISABLE ROOT PASSWORD
# ==============================================================================

section "Securing Root Account"

info "Locking root account password..."
if passwd -l root 2>&1 | grep -q "already locked"; then
    success "Root account password already locked"
else
    success "Root account locked (login via doas still works)"
fi

# ==============================================================================
# EUDEV SETUP (Required for NetworkManager)
# ==============================================================================

section "Setting Up Device Manager (eudev)"

# eudev is required for NetworkManager to properly manage network devices
# Without it, devices may be listed as "unmanaged"
info "Setting up eudev device manager..."

# Check if eudev is already running
if rc-service udev status >/dev/null 2>&1; then
    success "eudev already running"
else
    # Use setup-devd script if available (preferred method)
    if command -v setup-devd >/dev/null 2>&1; then
        info "Running setup-devd udev..."
        setup-devd udev
        success "eudev device manager configured via setup-devd"
    else
        # Manual installation
        info "Installing eudev manually..."
        apk add --no-cache eudev udev-init-scripts eudev-netifnames
        success "eudev packages installed"
        
        # Disable any existing device manager to avoid conflicts
        rc-update del mdev sysinit 2>/dev/null || true
        rc-service mdev stop 2>/dev/null || true
        
        # Enable eudev services
        info "Enabling eudev services..."
        rc-update add udev sysinit
        rc-update add udev-trigger sysinit
        rc-update add udev-settle sysinit
        rc-update add udev-postmount default
        success "eudev services enabled"
        
        # Start eudev services
        info "Starting eudev services..."
        rc-service udev start
        rc-service udev-trigger start
        rc-service udev-settle start
        rc-service udev-postmount start
        success "eudev services started"
        
        # Reload udev rules
        info "Reloading udev rules..."
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
        success "udev rules reloaded"
    fi
fi

# ==============================================================================
# NETWORKMANAGER INSTALLATION
# ==============================================================================

section "Installing NetworkManager"

# Install NetworkManager and related packages
info "Installing NetworkManager packages..."
apk add --no-cache networkmanager networkmanager-wifi networkmanager-tui networkmanager-cli wpa_supplicant
success "NetworkManager installed"

# Add user to plugdev group for non-root NetworkManager access
if [ -n "$ACTUAL_USER" ]; then
    info "Adding user '$ACTUAL_USER' to plugdev group..."
    addgroup "$ACTUAL_USER" plugdev 2>/dev/null || true
    success "User '$ACTUAL_USER' added to plugdev group"
fi

# Configure NetworkManager
info "Configuring NetworkManager..."
install_config "NetworkManager/NetworkManager.conf" "/etc/NetworkManager/NetworkManager.conf" 644
success "NetworkManager configured"

# Configure wpa_supplicant (disable P2P)
info "Configuring wpa_supplicant..."
mkdir -p /etc/wpa_supplicant
install_config "wpa_supplicant/wpa_supplicant.conf" "/etc/wpa_supplicant/wpa_supplicant.conf" 600
success "wpa_supplicant configured (P2P disabled)"

# Configure network interfaces (minimal - just loopback)
mkdir -p /etc/network
install_config "network/interfaces" "/etc/network/interfaces" 644

# Configure boot services (actual switch happens at end of script)
info "Configuring boot services..."
rc-update add networkmanager default 2>/dev/null || true
rc-update del networking boot 2>/dev/null || true
rc-update del wpa_supplicant boot 2>/dev/null || true
success "NetworkManager will be active on next boot"
warn "Network switch to NetworkManager will happen at end of script"

# Display NetworkManager CLI help
printf "\n"
info "NetworkManager CLI (nmcli) Quick Reference:"
info ""
info "  Connection Status:"
info "    nmcli general status        - Overall NetworkManager status"
info "    nmcli device status         - Show all network devices"
info "    nmcli connection show       - List all connections"
info "    nmcli connection show --active - List active connections"
info ""
info "  WiFi:"
info "    nmcli device wifi list      - Scan and list WiFi networks"
info "    nmcli device wifi connect <SSID> password <pass> - Connect to WiFi"
info "    nmcli connection up <name>  - Activate a saved connection"
info "    nmcli connection down <name> - Deactivate a connection"
info ""
info "  Configuration:"
info "    nmcli connection modify <name> <setting> <value> - Modify connection"
info "    nmcli connection delete <name> - Delete a connection"
info "    nmcli connection reload     - Reload connection files"
info ""
info "  Interactive:"
info "    nmtui                       - Text-based UI for NetworkManager"
info "    nmtui-connect               - Connect to a network"
info "    nmtui-edit                  - Edit connections"
info ""

# ==============================================================================
# NETWORK INTERFACE DETECTION
# ==============================================================================

section "Detecting Network Interfaces"

# Auto-detect ethernet interface if not specified
if [ -z "$ETH_INTERFACE" ]; then
    # Look for common ethernet interface names
    for iface in end0 eth0 enp0s3 enp1s0; do
        if [ -d "/sys/class/net/${iface}" ]; then
            ETH_INTERFACE="$iface"
            break
        fi
    done
fi

if [ -n "$ETH_INTERFACE" ]; then
    info "Ethernet interface: $ETH_INTERFACE"
else
    warn "No ethernet interface detected"
fi

# Auto-detect WiFi interface if not specified
if [ -z "$WIFI_INTERFACE" ]; then
    # Look for common WiFi interface names
    for iface in wlan0 wlp2s0 wlp3s0; do
        if [ -d "/sys/class/net/${iface}" ]; then
            WIFI_INTERFACE="$iface"
            break
        fi
    done
fi

if [ -n "$WIFI_INTERFACE" ]; then
    info "WiFi interface: $WIFI_INTERFACE"
else
    warn "No WiFi interface detected"
fi

# ==============================================================================
# SYSCTL CONFIGURATION
# ==============================================================================

section "Configuring System Network Parameters"

info "Installing sysctl configuration..."
install_config "sysctl/99-config.conf" "/etc/sysctl.d/99-config.conf" 644
success "Base sysctl configuration installed"

# Append interface-specific accept_ra settings
info "Configuring Router Advertisement acceptance for interfaces..."
{
    echo ""
    echo "# Accept Router Advertisements even with forwarding enabled"
    if [ -n "$ETH_INTERFACE" ]; then
        echo "net.ipv6.conf.${ETH_INTERFACE}.accept_ra=2"
    fi
    if [ -n "$WIFI_INTERFACE" ]; then
        echo "net.ipv6.conf.${WIFI_INTERFACE}.accept_ra=2"
    fi
} >> /etc/sysctl.d/99-config.conf

# Apply sysctl configuration
sysctl -p /etc/sysctl.d/99-config.conf >/dev/null 2>&1 || true
success "System network parameters configured and applied"

# ==============================================================================
# ETHERNET CONFIGURATION (NetworkManager)
# ==============================================================================

section "Configuring Ethernet (NetworkManager)"

# Build separate DNS server strings for IPv4 and IPv6
DNS_V4=""
for server in ${DNS_SERVERS_IPV4}; do
    if [ -n "$DNS_V4" ]; then
        DNS_V4="${DNS_V4};${server}"
    else
        DNS_V4="${server}"
    fi
done

DNS_V6=""
for server in ${DNS_SERVERS_IPV6}; do
    if [ -n "$DNS_V6" ]; then
        DNS_V6="${DNS_V6};${server}"
    else
        DNS_V6="${server}"
    fi
done

# Build search domains string - no trailing semicolon
DNS_SEARCH=""
for domain in ${DNS_SEARCH_DOMAINS}; do
    if [ -n "$DNS_SEARCH" ]; then
        DNS_SEARCH="${DNS_SEARCH};${domain}"
    else
        DNS_SEARCH="${domain}"
    fi
done

# Create Ethernet connection profile
if [ -n "$ETH_INTERFACE" ]; then
    info "Creating Ethernet connection profile for: $ETH_INTERFACE"
    mkdir -p /etc/NetworkManager/system-connections

    # Remove any existing connections for this interface to avoid duplicates
    info "Removing existing ethernet connections..."
    rm -f /etc/NetworkManager/system-connections/ethernet.nmconnection
    rm -f "/etc/NetworkManager/system-connections/${ETH_INTERFACE}.nmconnection"
    # Also remove auto-generated connections
    for f in /etc/NetworkManager/system-connections/*.nmconnection; do
        if [ -f "$f" ] && grep -q "type=ethernet" "$f" 2>/dev/null; then
            rm -f "$f"
        fi
    done

    # Build the connection file
    {
        cat << EOF
[connection]
id=Wired Connection
uuid=$(cat /proc/sys/kernel/random/uuid)
type=ethernet
autoconnect=true
interface-name=${ETH_INTERFACE}

[ethernet]

[ipv4]
method=auto
dns-priority=100
EOF
        # Only add DNS settings if configured
        if [ -n "$DNS_V4" ]; then
            echo "dns=${DNS_V4}"
            echo "ignore-auto-dns=true"
        fi
        if [ -n "$DNS_SEARCH" ]; then
            echo "dns-search=${DNS_SEARCH}"
        fi
        
        cat << EOF

[ipv6]
method=auto
dns-priority=50
EOF
        if [ -n "$DNS_V6" ]; then
            echo "dns=${DNS_V6}"
            echo "ignore-auto-dns=true"
        fi
        if [ -n "$DNS_SEARCH" ]; then
            echo "dns-search=${DNS_SEARCH}"
        fi
        echo "addr-gen-mode=default"
    } > /etc/NetworkManager/system-connections/ethernet.nmconnection

    chmod 600 /etc/NetworkManager/system-connections/ethernet.nmconnection
    success "Ethernet connection configured for $ETH_INTERFACE with custom DNS"
else
    warn "Skipping Ethernet configuration - no interface detected"
fi

# ==============================================================================
# WIFI CONFIGURATION (NetworkManager)
# ==============================================================================

section "Configuring WiFi (NetworkManager)"

if [ -n "$WIFI_INTERFACE" ]; then
    info "Creating WiFi connection profile for: ${WIFI_SSID} on ${WIFI_INTERFACE}"
    
    # Connection file path (use SSID as filename, like NetworkManager does)
    WIFI_CONN_FILE="/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"

    # Remove any existing WiFi connections to avoid duplicates
    info "Removing existing WiFi connections..."
    rm -f /etc/NetworkManager/system-connections/wifi.nmconnection
    rm -f "$WIFI_CONN_FILE"

    # Generate minimal connection file (matching NetworkManager's format)
    {
        cat << EOF
[connection]
id=${WIFI_SSID}
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect=true
interface-name=${WIFI_INTERFACE}

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=sae
EOF
        # Write password with printf to preserve special characters (like $)
        printf 'psk=%s\n' "$WIFI_PASSWORD"
        # Custom: show password in nmtui
        echo "psk-flags=0"
        
        cat << EOF

[ipv4]
method=auto
dns-priority=100
EOF
        # Custom: DNS settings
        if [ -n "$DNS_V4" ]; then
            echo "dns=${DNS_V4}"
            echo "ignore-auto-dns=true"
        fi
        if [ -n "$DNS_SEARCH" ]; then
            echo "dns-search=${DNS_SEARCH}"
        fi
        
        cat << EOF

[ipv6]
addr-gen-mode=default
method=auto
dns-priority=50
EOF
        # Custom: DNS settings
        if [ -n "$DNS_V6" ]; then
            echo "dns=${DNS_V6}"
            echo "ignore-auto-dns=true"
        fi
        if [ -n "$DNS_SEARCH" ]; then
            echo "dns-search=${DNS_SEARCH}"
        fi
    } > "$WIFI_CONN_FILE"

    chmod 600 "$WIFI_CONN_FILE"

    # Set WiFi regulatory domain
    info "Setting WiFi regulatory domain to: ${WIFI_COUNTRY}"
    mkdir -p /etc/modprobe.d
    echo "options cfg80211 ieee80211_regdom=${WIFI_COUNTRY}" > /etc/modprobe.d/cfg80211.conf
    success "WiFi regulatory domain configured"

    success "WiFi connection configured for SSID: ${WIFI_SSID} on ${WIFI_INTERFACE}"
else
    warn "Skipping WiFi configuration - no interface detected"
fi

# Display configured DNS
info "DNS configuration (applied to all connections):"
info "  Search domains:"
for domain in ${DNS_SEARCH_DOMAINS}; do
    info "    - ${domain}"
done
info "  IPv6 nameservers (preferred):"
for server in ${DNS_SERVERS_IPV6}; do
    info "    - ${server}"
done
info "  IPv4 nameservers (fallback):"
for server in ${DNS_SERVERS_IPV4}; do
    info "    - ${server}"
done

# Note: NetworkManager will be started at the end of the script to avoid
# disconnecting the current SSH session during configuration

# ==============================================================================
# NTP CONFIGURATION
# ==============================================================================

section "Configuring NTP"

# Install chrony (NTP client/server)
info "Installing chrony..."
apk add --no-cache chrony
success "chrony installed"

# Configure chrony
info "Configuring NTP servers..."

# Backup existing configuration
if [ -f /etc/chrony/chrony.conf ]; then
    cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup
    info "Backed up existing chrony.conf"
fi

# Build chrony config: NTP servers + template
{
    echo "# Chrony configuration generated by bootstrap script"
    echo ""
    echo "# NTP servers"
    for server in ${NTP_SERVERS}; do
        echo "server ${server} iburst"
    done
    echo ""
    cat "${CONFIGS_DIR}/chrony/chrony.conf.template"
} > /etc/chrony/chrony.conf

# Display configured NTP servers
info "NTP servers:"
for server in ${NTP_SERVERS}; do
    info "  - ${server}"
done

success "NTP configured"

# Enable and start chrony service
info "Enabling chrony service..."
rc-update add chronyd default 2>/dev/null || true
success "chrony service enabled at boot"

info "Starting chrony service..."
rc-service chronyd start 2>/dev/null || warn "Could not start chrony (may require reboot)"
success "NTP configuration complete"

# ==============================================================================
# DOCKER CONFIGURATION
# ==============================================================================

if echo "${PACKAGES}" | grep -q "docker"; then
    section "Configuring Docker"
    
    # Add user to docker group
    if [ -n "$ACTUAL_USER" ]; then
        if id -nG "$ACTUAL_USER" | grep -qw docker; then
            success "User '$ACTUAL_USER' is already in docker group"
        else
            info "Adding user '$ACTUAL_USER' to docker group..."
            addgroup "$ACTUAL_USER" docker
            success "User '$ACTUAL_USER' added to docker group"
        fi
    fi
    
    # Enable Docker service at boot
    info "Enabling Docker service..."
    rc-update add docker default 2>/dev/null || true
    success "Docker service enabled at boot"
    
    # Configure Docker daemon
    info "Configuring Docker daemon..."
    install_config "docker/daemon.json" "/etc/docker/daemon.json" 644
    success "Docker daemon configured"
    
    # Start Docker service
    info "Starting Docker service..."
    rc-service docker start 2>/dev/null || warn "Could not start Docker (may require reboot)"
    success "Docker configuration complete"
    
    # Display helpful Docker commands
    printf "\n"
    info "Docker Quick Reference:"
    info ""
    info "  Container Management:"
    info "    docker ps                    - List running containers"
    info "    docker ps -a                 - List all containers (including stopped)"
    info "    docker start <name>          - Start a container"
    info "    docker stop <name>           - Stop a container"
    info "    docker restart <name>        - Restart a container"
    info "    docker logs <name>           - View container logs"
    info "    docker logs -f <name>        - Follow container logs (live)"
    info ""
    info "  Docker Compose:"
    info "    docker-compose up -d         - Start services in background"
    info "    docker-compose down          - Stop and remove services"
    info "    docker-compose pull          - Pull latest images"
    info "    docker-compose logs -f       - Follow logs for all services"
    info ""
    info "  System:"
    info "    docker images                - List downloaded images"
    info "    docker system prune          - Remove unused data"
    info "    docker stats                 - Live resource usage"
    info ""
fi

# ==============================================================================
# DOCKER SERVICES SETUP
# ==============================================================================

SERVICES_DIR="${SCRIPT_DIR}/services"
INSTALLED_SERVICES=""

if [ "$INSTALL_DOCKER_PACKAGES" = "yes" ] && [ -d "$SERVICES_DIR" ]; then
    section "Docker Services Setup"
    
    # Stop any existing compose watchers before modifying Docker services
    # This prevents conflicts during service reconfiguration
    info "Stopping existing compose watchers..."
    for watcher_init in /etc/init.d/compose-watch-*; do
        if [ -f "$watcher_init" ]; then
            watcher_name=$(basename "$watcher_init")
            rc-service "$watcher_name" stop 2>/dev/null || true
        fi
    done
    success "Compose watchers stopped"
    printf "\n"
    
    info "Available Docker services:"
    for service_dir in "${SERVICES_DIR}"/*/; do
        if [ -d "$service_dir" ] && [ -f "${service_dir}/setup.sh" ]; then
            service_name=$(basename "$service_dir")
            info "  - ${service_name}"
        fi
    done
    printf "\n"
    
    for service_dir in "${SERVICES_DIR}"/*/; do
        if [ -d "$service_dir" ] && [ -f "${service_dir}/setup.sh" ]; then
            service_name=$(basename "$service_dir")
            
            printf "${BLUE}[?]${NC} Set up ${BOLD}%s${NC}? [Y/n] " "$service_name"
            read -r answer
            
            if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
                info "Skipping ${service_name}"
            else
                # Source the service setup script
                . "${service_dir}/setup.sh"
                
                # Track installed services for summary
                if [ -z "$INSTALLED_SERVICES" ]; then
                    INSTALLED_SERVICES="$service_name"
                else
                    INSTALLED_SERVICES="${INSTALLED_SERVICES} ${service_name}"
                fi
            fi
        fi
    done
fi

# ==============================================================================
# DOCKER MAINTENANCE CRON JOB
# ==============================================================================

if [ -n "$INSTALLED_SERVICES" ]; then
    section "Docker Maintenance Setup"
    
    info "Creating Docker image update script..."
    
    # Copy the update script from scripts directory
    mkdir -p /usr/local/bin
    cp "${SCRIPT_DIR}/scripts/docker-update-images.sh" /usr/local/bin/docker-update-images
    chmod 755 /usr/local/bin/docker-update-images
    success "Update script created at /usr/local/bin/docker-update-images"
    
    # Create daily cron job using Alpine's periodic system
    info "Setting up daily cron job..."
    mkdir -p /etc/periodic/daily
    
    cat > /etc/periodic/daily/docker-update << 'CRON_EOF'
#!/bin/sh
/usr/local/bin/docker-update-images >> /var/log/docker-update.log 2>&1
CRON_EOF
    
    chmod 755 /etc/periodic/daily/docker-update
    
    # Enable crond service
    rc-update add crond default 2>/dev/null || true
    rc-service crond start 2>/dev/null || true
    
    success "Daily Docker update cron job configured"
    info "  Script: /usr/local/bin/docker-update-images"
    info "  Cron:   /etc/periodic/daily/docker-update"
    info "  Log:    /var/log/docker-update.log"
    info ""
    info "To run manually: docker-update-images"
fi

# ==============================================================================
# DOCKER CLEANUP
# ==============================================================================

if [ -n "$INSTALLED_SERVICES" ]; then
    section "Docker Cleanup"
    
    info "Cleaning up unused Docker resources..."
    
    # Remove stopped containers
    info "Removing stopped containers..."
    docker container prune --force 2>/dev/null || true
    success "Stopped containers removed"
    
    # Remove unused images
    info "Removing unused images..."
    docker image prune --all --force 2>/dev/null || true
    success "Unused images removed"
    
    # Remove unused volumes
    info "Removing unused volumes..."
    docker volume prune --force 2>/dev/null || true
    success "Unused volumes removed"
    
    # Remove unused networks
    info "Removing unused networks..."
    docker network prune --force 2>/dev/null || true
    success "Unused networks removed"
    
    success "Docker cleanup complete"
fi

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

section "Bootstrap Complete"

printf "\n"
printf "The following changes have been made:\n"
printf "\n"
printf "  ${GREEN}✓${NC} Raspberry Pi packages\n"
for pkg in ${RPI_PACKAGES}; do
    printf "    - %s\n" "$pkg"
done
printf "\n"
printf "  ${GREEN}✓${NC} User packages\n"
for pkg in ${PACKAGES}; do
    printf "    - %s\n" "$pkg"
done
printf "\n"
printf "  ${GREEN}✓${NC} Package repositories\n"
printf "    - Community repository enabled/added to /etc/apk/repositories\n"
printf "\n"
printf "  ${GREEN}✓${NC} User privilege configuration\n"
if [ -n "$ACTUAL_USER" ]; then
    printf "    - User '%s' added to wheel group\n" "$ACTUAL_USER"
fi
printf "    - doas configured for wheel group\n"
printf "    - sudo configured for wheel group\n"
printf "\n"
printf "  ${GREEN}✓${NC} User account configuration\n"
if [ -n "$ACTUAL_USER" ]; then
    if [ -n "$USER_FULL_NAME" ]; then
        printf "    - Full name: %s\n" "$USER_FULL_NAME"
    fi
    printf "    - Password set for user '%s'\n" "$ACTUAL_USER"
    printf "    - Shell set to fish\n"
    printf "    - SSH key configured\n"
fi
printf "\n"
if [ -n "$ACTUAL_USER" ]; then
    printf "  ${GREEN}✓${NC} User application configs\n"
    printf "    - fish: ~/.config/fish/config.fish\n"
    printf "    - bat: ~/.config/bat/config\n"
    printf "    - nvim: ~/.config/nvim/\n"
    printf "    - root uses symlinks to %s's configs\n" "$ACTUAL_USER"
    printf "\n"
fi
printf "  ${GREEN}✓${NC} SSH server\n"
printf "    - Port: %s\n" "$SSH_PORT"
if [ "$SSH_PASSWORD_AUTH" = "yes" ]; then
    printf "    - Password authentication enabled\n"
    printf "    - Public key authentication enabled\n"
else
    printf "    - Password authentication disabled\n"
    printf "    - Public key authentication only\n"
fi
printf "    - Root login disabled\n"
printf "    - SSH service enabled at boot\n"
printf "\n"
printf "  ${GREEN}✓${NC} MOTD configured (Raspberry Pi %s)\n" "$RPI_VERSION"
printf "\n"
printf "  ${GREEN}✓${NC} Boot configuration\n"
printf "    - usercfg.txt installed to /boot/usercfg.txt\n"
printf "    - PCIe and cooling settings configured for Pi %s\n" "$RPI_VERSION"
printf "\n"
printf "  ${GREEN}✓${NC} Security\n"
printf "    - Root account password locked\n"
printf "\n"
printf "  ${GREEN}✓${NC} Device manager (eudev)\n"
printf "    - Required for NetworkManager to manage devices\n"
printf "\n"
printf "  ${GREEN}✓${NC} NetworkManager configuration\n"
if [ -n "$ACTUAL_USER" ]; then
    printf "    - User '%s' added to plugdev group\n" "$ACTUAL_USER"
fi
if [ -n "$ETH_INTERFACE" ]; then
    printf "    - Ethernet (%s) configured for DHCP\n" "$ETH_INTERFACE"
fi
if [ -n "$WIFI_INTERFACE" ]; then
    printf "    - WiFi (%s) configured for SSID: %s\n" "$WIFI_INTERFACE" "${WIFI_SSID}"
    printf "    - WiFi regulatory domain: %s\n" "${WIFI_COUNTRY}"
fi
printf "    - wpa_supplicant backend for WiFi\n"
printf "    - wpa_supplicant configured (P2P disabled)\n"
printf "    - DNS managed by NetworkManager (persistent)\n"
printf "    - Search domains:"
for domain in ${DNS_SEARCH_DOMAINS}; do
    printf " %s" "$domain"
done
printf "\n"
printf "    - IPv6 servers (preferred):"
for server in ${DNS_SERVERS_IPV6}; do
    printf " %s" "$server"
done
printf "\n"
printf "    - IPv4 servers (fallback):"
for server in ${DNS_SERVERS_IPV4}; do
    printf " %s" "$server"
done
printf "\n"
printf "\n"
printf "  ${GREEN}✓${NC} NTP configuration\n"
printf "    - Servers:"
for server in ${NTP_SERVERS}; do
    printf " %s" "$server"
done
printf "\n"
printf "    - chrony service enabled at boot\n"
printf "\n"
if echo "${PACKAGES}" | grep -q "docker"; then
    printf "  ${GREEN}✓${NC} Docker\n"
    if [ -n "$ACTUAL_USER" ]; then
        printf "    - User '%s' added to docker group\n" "$ACTUAL_USER"
    fi
    printf "    - Docker service enabled at boot\n"
    printf "    - live-restore enabled\n"
    printf "\n"
fi

if [ -n "$INSTALLED_SERVICES" ]; then
    printf "  ${GREEN}✓${NC} Docker services installed\n"
    for service in $INSTALLED_SERVICES; do
        printf "    - %s\n" "$service"
    done
    printf "    - Compose files: /opt/docker/<service>/\n"
    printf "    - Data: /srv/<service>/\n"
    printf "    - Daily auto-update cron job enabled\n"
    printf "\n"
fi

# ==============================================================================
# NETWORK SERVICE SWITCH
# ==============================================================================

section "Switching to NetworkManager"

printf "${YELLOW}WARNING: The following step will switch from the traditional${NC}\n"
printf "${YELLOW}networking service to NetworkManager. If you are connected${NC}\n"
printf "${YELLOW}via SSH, your connection may drop briefly.${NC}\n"
printf "\n"
printf "Press Enter to continue or Ctrl+C to abort..."
read -r _

info "Stopping traditional networking services..."
rc-service wpa_supplicant stop 2>/dev/null || true
rc-service networking stop 2>/dev/null || true
success "Traditional networking services stopped"

info "Starting NetworkManager..."
rc-service networkmanager start 2>/dev/null || warn "Could not start NetworkManager"

# Wait for NetworkManager to initialise
info "Waiting for NetworkManager to initialise..."
sleep 3

# Trigger connections using nmcli (only if not already connected)
info "Activating network connections..."
if [ -n "$ETH_INTERFACE" ]; then
    if ! nmcli -t -f STATE connection show --active "Wired Connection" 2>/dev/null | grep -q activated; then
        nmcli connection up "Wired Connection" 2>&1 | grep -v "^Error:" || true
    else
        info "Wired Connection already active"
    fi
fi
if [ -n "$WIFI_INTERFACE" ]; then
    if ! nmcli -t -f STATE connection show --active "${WIFI_SSID}" 2>/dev/null | grep -q activated; then
        nmcli connection up "${WIFI_SSID}" 2>&1 | grep -v "^Error:" || true
    else
        info "WiFi already active"
    fi
fi

# Wait for connections to establish
sleep 2

# Show connection status
info "Current network status:"
nmcli device status 2>/dev/null || true
printf "\n"

success "NetworkManager is now active"

# ==============================================================================
# REBOOT PROMPT
# ==============================================================================

printf "${YELLOW}A reboot is recommended to apply all changes.${NC}\n"
printf "\n"
printf "Would you like to reboot now? [y/N] "
read -r response
case "$response" in
    [yY][eE][sS]|[yY])
        info "Rebooting in 5 seconds..."
        sleep 5
        reboot
        ;;
    *)
        info "Reboot skipped. Please remember to reboot manually."
        printf "\n"
        printf "To reboot manually, run: ${BLUE}doas reboot${NC}\n"
        ;;
esac

printf "\n"
success "Bootstrap script finished!"
