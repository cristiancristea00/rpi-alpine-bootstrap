# Tor obfs4 Bridge Functions

set --local SERVICE tor-obfs4-bridge
setup-service-functions $SERVICE

function tor-obfs4-bridge-line --inherit-variable SERVICE
    docker exec --interactive --tty $SERVICE get-bridge-line $argv
end
