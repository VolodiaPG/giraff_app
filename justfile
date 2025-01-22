_default: dev

ghcr user: 
    #!/usr/bin/env bash
    set -e
    just _ghcr {{user}} "giraff_app"&
    just _ghcr {{user}} "giraff_speech"&
    wait

_ghcr user image:
    chronic nix run .#{{ image }}.copyTo docker://ghcr.io/{{ user }}/giraff:{{ image }}

dev:
    #!/usr/bin/env bash
    export MIX_ENV=dev
    export SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36
    export NAME="giraff"
    exec mix run --no-halt


docker_function ip FLAME_PARENT="":
    docker run \
        -e SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36 \
        -e PRIVATE_IP={{ip}} \
        -e NAME="dockergiraff" \
        -e RELEASE_COOKIE=nocookie \
        -e PHX_SERVER=false \
        -e INTERNAL_OPENED_PORT=30114 \
        -e OPENED_PORT=30115 \
        -e FLAME_PARENT="{{FLAME_PARENT}}" \
        -e fprocess="function" \
        -p 30115:30114 \
        ghcr.io/volodiapg/giraff:giraff_app

docker_server ip:
    # nix run .#giraff_app.copyToDockerDaemon
    docker run \
        -e SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36 \
        -e PRIVATE_IP={{ip}} \
        -e NAME="giraff" \
        -e RELEASE_COOKIE=nocookie \
        -e INTERNAL_OPENED_PORT=32115 \
        -e OPENED_PORT=32114 \
        -e fprocess="server" \
        --pull=always \
        -p 32115:32114 \
        -p 5000:5000 \
        ghcr.io/volodiapg/giraff:giraff_app


run ip is_nix="mix":
    #!/usr/bin/env bash
    export SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36
    export PRIVATE_IP={{ip}}
    export NAME="giraff"
    export RELEASE_COOKIE=nocookie
    export INTERNAL_OPENED_PORT=5656
    export OPENED_PORT=5656
    export MIX_ENV=prod
    export RELEASE_MODE=name
    export GIRAFF_NODE_ID="4b1a3a31-8130-431a-8a08-8a5be3becc3b"
    export MARKET_URL="{{ip}}:30008"
    if [ "{{is_nix}}" = "nix" ]; then
        BUILDPATH=$(nix build --print-out-paths .#prod)
        $BUILDPATH/bin/server
    else
        mix release --overwrite
        _build/prod/rel/giraff/bin/giraff start
    fi

deps:
    mix deps.get


test:
    curl -f \
        -X POST \
        -F "file=@$PATH_AUDIO/1272-135031-0014.wav"  \
        localhost:5000


test_raw:
    curl -f \
        -X POST \
        -H "Content-Type: audio/wav" \
        --data-binary "@$PATH_AUDIO/1272-135031-0014.wav" \
        localhost:5000
