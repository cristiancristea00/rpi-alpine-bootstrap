# Alpine Linux Bootstrap for Raspberry Pi

Personal bootstrap script for configuring Alpine Linux on Raspberry Pi 4/5.

## Features

- User privilege configuration with doas/sudo
- Fish shell as the default interactive shell
- Network and WiFi configuration via NetworkManager
- Essential package installation
- SSH hardening with key-based authentication
- Docker services with hot-reload watchers
- Daily automatic Docker image updates

## Prerequisites

- Raspberry Pi 4 or 5 with Alpine Linux installed
- Root access
- Network connectivity for package installation
- A text editor available (usually `vi` is pre-installed)
- **Recommended:** Assign a static IP address to your Raspberry Pi on your router for easier SSH access after network configuration

## Quick Start

### 1. Copy Configuration Files

Copy the example configuration files and customise them:

```sh
# Main bootstrap configuration
cp bootstrap.env.example bootstrap.env
vi bootstrap.env
```

For any Docker services you want to set up:

```sh
# WireGuard VPN
cp services/wireguard/.env.example services/wireguard/.env
vi services/wireguard/.env

# Tor obfs4 Bridge
cp services/tor-obfs4-bridge/.env.example services/tor-obfs4-bridge/.env
vi services/tor-obfs4-bridge/.env

# Tor Snowflake Proxy
cp services/tor-snowflake-proxy/.env.example services/tor-snowflake-proxy/.env
vi services/tor-snowflake-proxy/.env
```

### 2. Configure Your Settings

Edit `bootstrap.env` with your:

- Username and password
- SSH public key
- WiFi credentials
- DNS servers
- Packages to install

### 3. Run the Bootstrap Script

```sh
doas ./bootstrap.sh
```

The script will:

1. Configure user privileges
2. Install packages (including fish shell)
3. Set fish as the default shell for the user
4. Set up networking
5. Configure SSH
6. Optionally set up Docker services
7. Switch to NetworkManager

**Note:** The system uses fish shell as the default interactive shell. After the bootstrap completes and you log in, you'll be using fish with its enhanced features like syntax highlighting, autosuggestions, and tab completions.

## Docker Services

### WireGuard VPN

A WireGuard VPN server.

**Shell functions:**

- `wireguard-show`        - Display WireGuard status
- `wireguard-peer <name>` - Show peer QR code
- `wireguard-logs`        - Follow container logs
- `wireguard-start`       - Start WireGuard
- `wireguard-stop`        - Stop WireGuard
- `wireguard-restart`     - Restart WireGuard

### Tor obfs4 Bridge

A Tor bridge with obfs4 pluggable transport to help users bypass censorship.

**Shell functions:**

- `tor-obfs4-bridge-line`    - Get bridge connection string
- `tor-obfs4-bridge-logs`    - Follow container logs
- `tor-obfs4-bridge-start`   - Start bridge
- `tor-obfs4-bridge-stop`    - Stop bridge
- `tor-obfs4-bridge-restart` - Restart bridge

### Tor Snowflake Proxy

A Snowflake proxy to help Tor users connect through WebRTC.

**Shell functions:**

- `tor-snowflake-proxy-logs`    - Follow container logs
- `tor-snowflake-proxy-start`   - Start Snowflake proxy
- `tor-snowflake-proxy-stop`    - Stop Snowflake proxy
- `tor-snowflake-proxy-restart` - Restart Snowflake proxy

## Hot Reload

Docker services are monitored for configuration changes. When you edit a service's `compose.yml` or `.env` file, the container is automatically restarted.

Watcher logs are available at:

```sh
/var/log/compose-watch-<service-name>.log
```

## Automatic Updates

If Docker services are installed, a daily cron job updates container images and prunes unused ones.

- Script: `/usr/local/bin/docker-update-images`
- Log: `/var/log/docker-update.log`

Run manually:

```sh
docker-update-images
```

## Service Locations

| Type              | Path                                |
| ----------------- | ----------------------------------- |
| Compose files     | `/opt/docker/<service>/compose.yml` |
| Environment files | `/opt/docker/<service>/.env`        |
| Service data      | `/srv/<service>/`                   |

## Security Notes

- `bootstrap.env` contains sensitive data and is automatically set to mode 600
- Service `.env` files are set to mode 600 when deployed
- SSH password authentication can be disabled via `SSH_PASSWORD_AUTH="no"` in `bootstrap.env` (requires SSH key to be configured)
- All `.env` files are excluded from version control via `.gitignore`
