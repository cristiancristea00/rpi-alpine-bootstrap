#!/bin/sh
#
# Tor obfs4 Bridge Setup
#
# This script is sourced by the main bootstrap.sh
# It deploys and configures the Tor obfs4 bridge Docker container.
#

SERVICE_NAME="tor-obfs4-bridge"

# Source common functions
. "${SCRIPT_DIR}/services/common.sh"

# ==============================================================================
# TOR OBFS4 BRIDGE SETUP
# ==============================================================================

info "Setting up Tor obfs4 bridge..."

# Create directory structure
setup_service_dirs "$SERVICE_NAME"

# Deploy compose file and .env
deploy_compose "$SERVICE_NAME"

# Ask user for image tag (latest or nightly) and persist selection
select_image_tag "$SERVICE_NAME" "latest" "nightly"

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
info "Tor obfs4 bridge deployed successfully!"
info ""
info "Data location:         /srv/tor-obfs4-bridge/data/"
info "Compose file location: /opt/docker/tor-obfs4-bridge/compose.yml"
info "Environment file:      /opt/docker/tor-obfs4-bridge/.env"
info ""
info "Hot reload: Editing compose.yml or .env will automatically reload the container"
info "  Watcher service: compose-watch-tor-obfs4-bridge"
info "  Logs: /var/log/compose-watch-tor-obfs4-bridge.log"
info ""
info "Shell functions available:"
info "  tor-obfs4-bridge-line       - Get bridge connection string"
info "  tor-obfs4-bridge-logs       - Follow bridge logs"
info "  tor-obfs4-bridge-start      - Start bridge"
info "  tor-obfs4-bridge-stop       - Stop bridge"
info "  tor-obfs4-bridge-restart    - Restart bridge"
info ""
info "Bridge data is persisted in:"
info "  /srv/tor-obfs4-bridge/data/"
info ""

success "Tor obfs4 bridge setup complete"
