#!/bin/sh
#
# Tor Snowflake Proxy Setup
#
# This script is sourced by the main bootstrap.sh
# It deploys and configures the Tor Snowflake proxy Docker container.
#

SERVICE_NAME="tor-snowflake-proxy"

# Source common functions
. "${SCRIPT_DIR}/services/common.sh"

# ==============================================================================
# TOR SNOWFLAKE PROXY SETUP
# ==============================================================================

info "Setting up Tor Snowflake proxy..."

# Create directory structure
setup_service_dirs "$SERVICE_NAME"

# Deploy compose file and .env
deploy_compose "$SERVICE_NAME"

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
info "Tor Snowflake proxy deployed successfully!"
info ""
info "Data location:         /srv/tor-snowflake-proxy/"
info "Compose file location: /opt/docker/tor-snowflake-proxy/compose.yml"
info "Environment file:      /opt/docker/tor-snowflake-proxy/.env"
info ""
info "Hot reload: Editing compose.yml or .env will automatically reload the container"
info "  Watcher service: compose-watch-tor-snowflake-proxy"
info "  Logs: /var/log/compose-watch-tor-snowflake-proxy.log"
info ""
info "Shell functions available:"
info "  tor-snowflake-proxy-logs - Follow Snowflake proxy logs"
info ""
info "To view proxy stats and connection info:"
info "  docker logs tor-snowflake-proxy"
info ""
info "The Snowflake proxy uses host networking and ephemeral ports 30000-50000"
info "for maximum connectivity with Tor clients."
info ""

success "Tor Snowflake proxy setup complete"
