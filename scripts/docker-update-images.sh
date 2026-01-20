#!/bin/sh
# Docker Image Auto-Update Script
# Runs daily to update all Docker compose services and prune unused images

# ==============================================================================
# SCRIPT DIRECTORY
# ==============================================================================
# Determine the directory where the script is located

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ==============================================================================
# SOURCE COMMON UTILITIES
# ==============================================================================
# Source common functions (includes root check)

. "${SCRIPT_DIR}/common.sh"

LOG_TAG="docker-update"
COMPOSE_DIR="/opt/docker"

# Detect docker compose command
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

log() {
    logger -t "$LOG_TAG" "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')]: $1"
}

log "Starting Docker image update..."

# Update each service
for compose_file in "${COMPOSE_DIR}"/*/compose.yml; do
    if [ -f "$compose_file" ]; then
        service_dir=$(dirname "$compose_file")
        service_name=$(basename "$service_dir")
        
        log "Updating ${service_name}..."
        
        # Pull latest images
        if $COMPOSE_CMD --file "$compose_file" pull 2>&1; then
            # Recreate containers with new images
            $COMPOSE_CMD --file "$compose_file" up --detach --force-recreate 2>&1
            log "${service_name} updated successfully"
        else
            log "Failed to pull images for ${service_name}"
        fi
    fi
done

# Prune unused images
log "Pruning unused Docker images..."
docker image prune --all --force 2>&1
docker system prune --force 2>&1

log "Docker image update complete"
