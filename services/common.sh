#!/bin/sh
#
# Common functions for Docker service setup scripts
#
# This file is sourced by individual service setup scripts.
# It provides shared utilities for deploying Docker Compose services.
#
# Required variables from parent script:
#   SCRIPT_DIR - Directory containing the bootstrap script
#   CONFIGS_DIR - Directory containing config files
#
# Functions use these helper functions from bootstrap.sh:
#   info(), success(), warn(), error()
#

# Base directories for Docker services
DOCKER_COMPOSE_DIR="/opt/docker"
DOCKER_DATA_DIR="/srv"

# Detect docker compose command (plugin vs standalone)
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    error "Neither 'docker compose' nor 'docker-compose' found"
    DOCKER_COMPOSE="docker-compose"
fi

# ==============================================================================
# SETUP SERVICE DIRECTORIES
# ==============================================================================
# Creates the standard directory structure for a service
#
# Usage: setup_service_dirs <service_name>
#
setup_service_dirs() {
    svc_name="$1"
    
    if [ -z "$svc_name" ]; then
        error "setup_service_dirs: service name required"
        return 1
    fi
    
    info "Creating directories for ${svc_name}..."
    
    # Create compose file directory
    mkdir -p "${DOCKER_COMPOSE_DIR}/${svc_name}"
    
    # Create data directory
    mkdir -p "${DOCKER_DATA_DIR}/${svc_name}"
    
    success "Directories created for ${svc_name}"
}

# ==============================================================================
# DEPLOY COMPOSE FILE
# ==============================================================================
# Copies the compose.yml and .env (if present) to the target directory
#
# Usage: deploy_compose <service_name>
#
deploy_compose() {
    svc_name="$1"
    svc_source="${SCRIPT_DIR}/services/${svc_name}/compose.yml"
    svc_target="${DOCKER_COMPOSE_DIR}/${svc_name}/compose.yml"
    env_source="${SCRIPT_DIR}/services/${svc_name}/.env"
    env_target="${DOCKER_COMPOSE_DIR}/${svc_name}/.env"
    
    if [ -z "$svc_name" ]; then
        error "deploy_compose: service name required"
        return 1
    fi
    
    if [ ! -f "$svc_source" ]; then
        error "deploy_compose: compose.yml not found at ${svc_source}"
        return 1
    fi
    
    info "Deploying compose file for ${svc_name}..."
    cp "$svc_source" "$svc_target"
    chmod 644 "$svc_target"
    
    success "Compose file deployed to ${svc_target}"
    
    # Also deploy .env file if present
    if [ -f "$env_source" ]; then
        info "Deploying .env file for ${svc_name}..."
        cp "$env_source" "$env_target"
        chmod 600 "$env_target"  # More restrictive for secrets
        success ".env file deployed to ${env_target}"
    fi
}

# ==============================================================================
# DEPLOY FISH FUNCTIONS
# ==============================================================================
# Copies service-specific fish functions to user's fish conf.d directory
#
# Usage: deploy_fish_functions <service_name>
#
deploy_fish_functions() {
    svc_name="$1"
    fish_source="${SCRIPT_DIR}/services/${svc_name}/functions.fish"
    
    if [ -z "$svc_name" ]; then
        warn "deploy_fish_functions: service name required"
        return 1
    fi
    
    # Only deploy if functions.fish exists
    if [ ! -f "$fish_source" ]; then
        return 0  # Not an error, just no functions to deploy
    fi
    
    if [ -z "$ACTUAL_USER" ]; then
        warn "deploy_fish_functions: ACTUAL_USER not set, skipping"
        return 0
    fi
    
    # Get user's home directory
    user_home=$(eval echo "~${ACTUAL_USER}")
    fish_confdir="${user_home}/.config/fish/conf.d"
    fish_target="${fish_confdir}/${svc_name}.fish"
    
    info "Deploying fish functions for ${svc_name}..."
    
    # Create conf.d directory if it doesn't exist
    mkdir -p "$fish_confdir"
    
    # Copy functions file
    cp "$fish_source" "$fish_target"
    chmod 644 "$fish_target"
    chown "${ACTUAL_USER}:${ACTUAL_USER}" "$fish_target"
    
    success "Fish functions deployed to ${fish_target}"
}

# ==============================================================================
# IMAGE TAG SELECTION
# ==============================================================================
# Update an env file with a key/value pair (creates file if missing)
#
# Usage: set_env_value <env_file> <key> <value>
#
set_env_value() {
    env_file="$1"
    env_key="$2"
    env_value="$3"

    if [ -z "$env_file" ] || [ -z "$env_key" ]; then
        error "set_env_value: env file and key required"
        return 1
    fi

    env_dir=$(dirname "$env_file")
    mkdir -p "$env_dir"

    tmp_file=$(mktemp)
    if [ -f "$env_file" ]; then
        # Escape special regex characters in the key for safe pattern matching
        escaped_key=$(printf "%s" "$env_key" | sed 's/[.[\*^$()+?{|]/\\&/g')
        awk -v k="$env_key" -v v="$env_value" -v ek="$escaped_key" '
            BEGIN {updated = 0}
            $0 ~ "^" ek "=" {
                if (!updated) {
                    print k "=" v
                    updated = 1
                }
                next
            }
            {print}
            END {
                if (!updated) {
                    print k "=" v
                }
            }
        ' "$env_file" > "$tmp_file"
    else
        printf "%s=%s\n" "$env_key" "$env_value" > "$tmp_file"
    fi

    mv "$tmp_file" "$env_file"
    chmod 600 "$env_file"
}

# Prompt the user for latest vs nightly and persist to .env
#
# Usage: select_image_tag <service_name> <option1> [option2] [...]
# First option is the default
#
select_image_tag() {
    svc_name="$1"
    shift
    env_file="${DOCKER_COMPOSE_DIR}/${svc_name}/.env"

    if [ -z "$svc_name" ]; then
        warn "select_image_tag: service name required"
        return 1
    fi

    if [ $# -eq 0 ]; then
        warn "select_image_tag: at least one tag option required"
        return 1
    fi

    # Store available options
    options="$*"
    default_option="$1"

    # Build prompt message
    prompt_options=$(echo "$options" | sed 's/ /\//g')
    
    while :; do
        printf "Choose image tag for %s (%s) [%s]: " "$svc_name" "$prompt_options" "$default_option"
        read tag_choice
        tag_choice=$(printf "%s" "$tag_choice" | tr '[:upper:]' '[:lower:]')
        
        # Use default if empty
        if [ -z "$tag_choice" ]; then
            tag_choice="$default_option"
            break
        fi

        # Check if input matches any option (with prefix matching)
        matched=0
        for opt in $options; do
            opt_lower=$(printf "%s" "$opt" | tr '[:upper:]' '[:lower:]')
            # Check if tag_choice is a prefix of opt_lower
            case "$opt_lower" in
                "$tag_choice"*)
                    tag_choice="$opt"
                    matched=1
                    break
                    ;;
            esac
        done

        if [ $matched -eq 1 ]; then
            break
        else
            warn "Please choose one of: $options"
        fi
    done

    set_env_value "$env_file" "IMAGE_TAG" "$tag_choice"

    success "Using ${tag_choice} image tag for ${svc_name}"
}

# ==============================================================================
# START SERVICE
# ==============================================================================
# Pulls images and starts the service using Docker Compose
#
# Usage: start_service <service_name>
#
start_service() {
    svc_name="$1"
    svc_compose="${DOCKER_COMPOSE_DIR}/${svc_name}/compose.yml"
    
    if [ -z "$svc_name" ]; then
        error "start_service: service name required"
        return 1
    fi
    
    if [ ! -f "$svc_compose" ]; then
        error "start_service: compose file not found at ${svc_compose}"
        return 1
    fi
    
    # Docker Compose automatically uses .env file in the same directory as compose.yml
    # No need to specify --env-file explicitly
    
    info "Pulling images for ${svc_name}..."
    $DOCKER_COMPOSE --file "$svc_compose" pull
    
    info "Starting ${svc_name}..."
    $DOCKER_COMPOSE --file "$svc_compose" up --detach
    
    success "${svc_name} started"
}

# ==============================================================================
# STOP SERVICE
# ==============================================================================
# Stops the service using Docker Compose
#
# Usage: stop_service <service_name>
#
stop_service() {
    svc_name="$1"
    svc_compose="${DOCKER_COMPOSE_DIR}/${svc_name}/compose.yml"
    
    if [ -z "$svc_name" ]; then
        error "stop_service: service name required"
        return 1
    fi
    
    if [ ! -f "$svc_compose" ]; then
        warn "stop_service: compose file not found, skipping"
        return 0
    fi
    
    # Docker Compose automatically uses .env file in the same directory as compose.yml
    # No need to specify --env-file explicitly
    
    info "Stopping ${svc_name}..."
    $DOCKER_COMPOSE --file "$svc_compose" down
    
    success "${svc_name} stopped"
}

# ==============================================================================
# CHECK SERVICE STATUS
# ==============================================================================
# Checks if the service containers are running
#
# Usage: check_service <service_name>
#
check_service() {
    svc_name="$1"
    svc_compose="${DOCKER_COMPOSE_DIR}/${svc_name}/compose.yml"
    
    if [ ! -f "$svc_compose" ]; then
        return 1
    fi
    
    $DOCKER_COMPOSE --file "$svc_compose" ps --quiet 2>/dev/null | grep -q .
}

# ==============================================================================
# SETUP COMPOSE WATCHER
# ==============================================================================
# Creates an OpenRC service that watches compose.yml and .env, reloads on changes
#
# Usage: setup_compose_watcher <service_name>
#
setup_compose_watcher() {
    svc_name="$1"
    svc_compose="${DOCKER_COMPOSE_DIR}/${svc_name}/compose.yml"
    svc_env="${DOCKER_COMPOSE_DIR}/${svc_name}/.env"
    watcher_name="compose-watch-${svc_name}"
    watcher_script="/usr/local/bin/${watcher_name}"
    watcher_template="${SCRIPT_DIR}/scripts/compose-watcher.sh.template"
    openrc_template="${SCRIPT_DIR}/scripts/compose-watcher-openrc.template"
    
    if [ -z "$svc_name" ]; then
        error "setup_compose_watcher: service name required"
        return 1
    fi
    
    info "Setting up compose file watcher for ${svc_name}..."
    
    # Create the watcher script from template
    mkdir -p /usr/local/bin
    sed -e "s|{{SERVICE_NAME}}|${svc_name}|g" \
        -e "s|{{COMPOSE_FILE}}|${svc_compose}|g" \
        -e "s|{{ENV_FILE}}|${svc_env}|g" \
        -e "s|{{COMPOSE_CMD}}|${DOCKER_COMPOSE}|g" \
        -e "s|{{WATCHER_NAME}}|${watcher_name}|g" \
        "${watcher_template}" > "${watcher_script}"
    
    chmod 755 "${watcher_script}"
    
    # Create the OpenRC init script from template
    sed -e "s|{{SERVICE_NAME}}|${svc_name}|g" \
        -e "s|{{WATCHER_NAME}}|${watcher_name}|g" \
        -e "s|{{WATCHER_SCRIPT}}|${watcher_script}|g" \
        "${openrc_template}" > "/etc/init.d/${watcher_name}"
    
    chmod 755 "/etc/init.d/${watcher_name}"
    
    # Enable and start the watcher
    rc-update add "${watcher_name}" default 2>/dev/null || true
    rc-service "${watcher_name}" start 2>/dev/null || warn "Could not start watcher (may need reboot)"
    
    success "Compose watcher enabled for ${svc_name}"
}
