#!/bin/sh
#
# WireGuard VPN Server Setup
#
# This script is sourced by the main bootstrap.sh
# It deploys and configures the WireGuard Docker container.
#

SERVICE_NAME="wireguard"

# Source common functions
. "${SCRIPT_DIR}/services/common.sh"

# ==============================================================================
# WIREGUARD SETUP
# ==============================================================================

info "Setting up WireGuard VPN server..."

# Create directory structure
setup_service_dirs "$SERVICE_NAME"

# Deploy compose file
deploy_compose "$SERVICE_NAME"

# Select image tag (latest or edge)
select_image_tag "$SERVICE_NAME" "latest" "edge" "15"

# Deploy fish shell functions
deploy_fish_functions "$SERVICE_NAME"

# Start the service
start_service "$SERVICE_NAME"

# Setup compose file watcher for hot reload
setup_compose_watcher "$SERVICE_NAME"

# ==============================================================================
# POST-SETUP INFORMATION
# ==============================================================================

printf "\n"
info "WireGuard VPN server deployed successfully!"
info ""
info "Configuration location: /srv/wireguard/config/"
info "Compose file location:  /opt/docker/wireguard/compose.yml"
info ""
info "Hot reload: Editing compose.yml will automatically reload the container"
info "  Watcher service: compose-watch-wireguard"
info "  Logs: /var/log/compose-watch-wireguard.log"
info ""
info "Shell functions available:"
info "  wireguard-show           - Show WireGuard status"
info "  wireguard-peer <name>    - Display peer QR code"
info "  wireguard-logs           - Follow WireGuard logs"
info "  wireguard-start          - Start WireGuard"
info "  wireguard-stop           - Stop WireGuard"
info "  wireguard-restart        - Restart WireGuard"
info ""
info "Peer configuration files are in:"
info "  /srv/wireguard/config/peer_<name>/"
info ""

success "WireGuard setup complete"
