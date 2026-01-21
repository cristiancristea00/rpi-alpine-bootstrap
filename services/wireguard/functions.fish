# WireGuard VPN Functions

set --local SERVICE wireguard
setup-service-functions $SERVICE

function wireguard-show --inherit-variable SERVICE
    docker exec --interactive --tty $SERVICE wg show $argv
end
