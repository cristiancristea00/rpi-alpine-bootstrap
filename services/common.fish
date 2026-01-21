# Common Docker Service Functions

function setup-service-functions
    set --local SERVICE $argv[1]

    function $SERVICE-logs --inherit-variable SERVICE
        docker logs --follow $SERVICE $argv
    end

    function $SERVICE-start --inherit-variable SERVICE
        docker start $SERVICE
    end

    function $SERVICE-stop --inherit-variable SERVICE
        docker stop $SERVICE
    end

    function $SERVICE-restart --inherit-variable SERVICE
        docker restart $SERVICE
    end

    function $SERVICE-down --inherit-variable SERVICE
        doas docker-compose --file /opt/docker/$SERVICE/compose.yml down
    end

    function $SERVICE-up --inherit-variable SERVICE
        doas docker-compose --file /opt/docker/$SERVICE/compose.yml up --detach
    end

    function $SERVICE-recreate --inherit-variable SERVICE
        eval $SERVICE-down
        eval $SERVICE-up
    end
end
