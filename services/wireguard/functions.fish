# WireGuard VPN Functions

function wireguard-show
    docker exec --interactive --tty wireguard wg show $argv
end

function wireguard-peer
    if test (count $argv) -eq 0
        echo "Usage: wireguard-peer <peer-name>"
        return 1
    end
    docker exec --interactive --tty wireguard /app/show-peer $argv
end

function wireguard-logs
    docker logs --follow wireguard $argv
end
