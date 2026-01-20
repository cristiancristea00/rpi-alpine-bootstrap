# Tor Snowflake Proxy Functions

function tor-snowflake-proxy-logs
    docker logs --follow tor-snowflake-proxy $argv
end

function tor-snowflake-proxy-start
    docker start tor-snowflake-proxy
end

function tor-snowflake-proxy-stop
    docker stop tor-snowflake-proxy
end

function tor-snowflake-proxy-restart
    docker restart tor-snowflake-proxy
end