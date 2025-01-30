_default: dev

ghcr: 
    #!/usr/bin/env bash
    set -e
    just _ghcr "prod_giraff_app"&
    just _ghcr "prod_giraff_speech"&
    just _ghcr "prod_giraff_tts"&
    just _ghcr "prod_giraff_sentiment"&
    wait

_ghcr image:
    chronic nix run .#{{ image }}.copyToRegistry

docker: 
    #!/usr/bin/env bash
    set -e
    just _docker "docker_giraff_app"&
    just _docker "docker_giraff_speech"&
    just _docker "docker_giraff_tts"&
    just _docker "docker_giraff_sentiment"&
    wait

_docker image:
    chronic nix run .#{{ image }}.copyToDockerDaemon

dev:
    #!/usr/bin/env bash
    export MIX_ENV=dev
    export SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36
    export NAME="giraff"
    exec mix run --no-halt

run ip is_nix="mix":
    #!/usr/bin/env bash
    export SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36
    export PRIVATE_IP={{ip}}
    export NAME="giraff"
    export RELEASE_COOKIE=nocookie
    export INTERNAL_OPENED_PORT=5656
    export OPENED_PORT=5656
    export RELEASE_MODE=name
    if [ "{{is_nix}}" = "nix" ]; then
        export GIRAFF_NODE_ID="4b1a3a31-8130-431a-8a08-8a5be3becc3b"
        export MARKET_URL="{{ip}}:30008"
        export MIX_ENV=prod
        BUILDPATH=$(nix build --print-out-paths .#prod)
        $BUILDPATH/bin/server
    elif [ "{{is_nix}}" = "docker" ]; then
        export MIX_ENV=docker
        mix release --overwrite
        _build/docker/rel/giraff/bin/giraff start
    else
        export MIX_ENV=prod
        export GIRAFF_NODE_ID="4b1a3a31-8130-431a-8a08-8a5be3becc3b"
        export MARKET_URL="{{ip}}:30008"
        exec mix run --no-halt
    fi


test:
    curl -f \
        -X POST \
        -F "file=@$PATH_AUDIO/8842-304647-0007.wav"  \
        localhost:5000


test_raw:
    curl -f \
        -X POST \
        -H "Content-Type: audio/wav" \
        --data-binary "@$PATH_AUDIO/1272-135031-0014.wav" \
        localhost:5000

test_all:
    #!/usr/bin/env bash
    for file in $PATH_AUDIO/*.wav; do
        echo "Testing $file"
        curl -f \
            -X POST \
            -H "Content-Type: audio/wav" \
            --data-binary "@$file" \
            localhost:5000
    done
