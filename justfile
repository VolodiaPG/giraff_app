_default: dev

ghcr:
    #!/usr/bin/env bash
    set -e
    just _ghcr "prod_giraff_app"&
    just _ghcr "prod_giraff_speech"&
    just _ghcr "prod_giraff_tts"&
    just _ghcr "prod_giraff_sentiment"&
    just _ghcr "prod_giraff_vosk_speech"&
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
    just _docker "docker_giraff_vosk_speech"&
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
        export MIX_ENV=docker
        export OTEL_EXPORTER_OTLP_ENDPOINT_FUNCTION="http://{{ip}}:4317"
        BUILDPATH=$(nix build --print-out-paths .#docker)
        $BUILDPATH/bin/server
    elif [ "{{is_nix}}" = "docker" ]; then
        export MIX_ENV=docker
        export OTEL_EXPORTER_OTLP_ENDPOINT_FUNCTION="http://{{ip}}:4317"
        mix release --overwrite
        # sudo systemd-run --scope  _build/docker/rel/giraff/bin/giraff start

        _build/docker/rel/giraff/bin/giraff start
    else
        export MIX_ENV=prod
        export GIRAFF_NODE_ID="4b1a3a31-8130-431a-8a08-8a5be3becc3b"
        export MARKET_URL="{{ip}}:30008"
        export OTEL_EXPORTER_OTLP_ENDPOINT_FUNCTION="http://{{ip}}:4317"
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

test_all $requests="2":
    #!/usr/bin/env bash
    count=0
    for file in $PATH_AUDIO/*.wav; do
        if [ $count -ge $requests ]; then
            break
        fi
        echo "Testing $file"
        curl -f \
            -X POST \
            -H "Content-Type: audio/wav" \
            --data-binary "@$file" \
            localhost:5000&
        count=$((count + 1))
    done
    if [ $count -lt $requests ]; then
      exec just test_all $((requests - count))
    fi
    wait

test_vosk:
    python3 priv/python/speech_vosk.py $PATH_AUDIO/8842-304647-0007.wav

jaeger:
    docker run --rm --name jaeger \
       -e COLLECTOR_OTLP_ENABLED=true \
       -p 5775:5775/udp \
       -p 6831:6831/udp \
       -p 6832:6832/udp \
       -p 5778:5778 \
       -p 16686:16686 \
       -p 14268:14268 \
       -p 4317:4317 \
       -p 4318:4318 \
       jaegertracing/all-in-one:1.67.0

