# Tor obfs4 Bridge Functions

function tor-obfs4-bridge-line
    docker exec --interactive --tty tor-obfs4-bridge get-bridge-line $argv
end

function tor-obfs4-bridge-logs
    docker logs --follow tor-obfs4-bridge $argv
end
