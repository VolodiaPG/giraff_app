NIX := "${NIX:-nom}"
NIX_OPTS := "--extra-experimental-features 'nix-command flakes'"
DB := justfile_directory() / ".db" / "thumbs_dev"

_default: run

deploy dest hostname="toto":
    @vm_deploy {{ dest }} {{ hostname }}

remove dest hostname="toto":
    @vm_remove {{ dest }} {{ hostname }}

remove_all dest:
    #!/usr/bin/env bash
    vms=$(just check-ts)
    # cache the script beforehand

    mapfile -t vms_list <<< "$vms"
    echo -n "Removing ${#vms_list[@]} vms from {{ dest }}"
    for vm in $vms; do
      vm_remove {{ dest }} "$vm"
      if [ $? -eq 0 ]; then
        echo -n "."
      else
        echo -n "x"
      fi
    done
    echo ""

check-ts:
    @check_ts

ssh-in vm:
    @ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeychecking=no root@{{ vm }}

dev:
    #!/usr/bin/env bash
    export MIX_ENV=dev
    exec mix run --no-halt

run:
    #!/usr/bin/env bash
    export FLY_IMAGE_REF=thumbs
    export FLY_IMAGE=ghcr.io/volodiapg/thumbs:latest
    export FLY_APP_NAME="thumbs"
    export FLY_HOST=http://localhost-0:12345
    exec mix phx.server

deps:
    mix deps.get

postgres_stop:
    #!/usr/bin/env bash
    (pg_ctl -D "{{ DB }}" stop && sleep 5) || true
    rm -rf "{{ DB }}" || true

setup: postgres_stop
    #!/usr/bin/env bash
    set -e
    # Create a database with the data stored in the current directory
    #createuser postgres
    mkdir -p "{{ DB }}"
    initdb -D "{{ DB }}"
    #  the file will no longer be compressed (if it was previously compressed), and it will revert to its uncompressed state.
    chattr +C "{{ DB }}" || true

    export FLY_PRIVATE_IP4=$(tailscale status --self --json 2> /dev/null | jq -r '.Self.TailscaleIPs[0]')
    export FLY_PRIVATE_I4=${FLY_PRIVATE_IP4%.}
    export FLY_PRIVATE_IP6=$(tailscale status --self --json 2> /dev/null | jq -r '.Self.TailscaleIPs[1]')
    export FLY_PRIVATE_IP6=${FLY_PRIVATE_IP6%.}
    cat <<-EOF >> "{{ DB }}/pg_hba.conf"
    host thumbs_dev postgres $FLY_PRIVATE_IP4/8 md5
    host thumbs_dev postgres $FLY_PRIVATE_IP6/64 md5
    EOF

    cat <<-EOF >> "{{ DB }}/postgresql.conf"
    listen_addresses='*'
    unix_socket_directories='{{ DB }}'
    EOF

    pg_ctl -D "{{ DB }}" -l logfile start

    createdb -h "{{ DB }}" thumbs_dev
    psql -h "{{ DB }}" -d thumbs_dev <<-EOF
    CREATE ROLE postgres WITH PASSWORD 'postgres';
    GRANT ALL PRIVILEGES ON DATABASE thumbs_dev TO postgres;
    ALTER ROLE postgres WITH LOGIN;
    GRANT USAGE ON SCHEMA public TO postgres;
    GRANT CREATE ON SCHEMA public TO postgres;
    EOF
    just _setup

_setup:
    #/usr/bin/env bash
    export MIX_ENV=prod
    #export DATABASE_URL="ecto://postgres:postgres@localhost:5432/thumbs_dev"
    export PHX_SERVER=true
    mix setup

toto ip compile="true":
    #!/usr/bin/env bash
    export PHX_SERVER=true
    export FLY_PRIVATE_IP={{ip}}
    # export FLY_PRIVATE_IP=${FLY_PRIVATE_IP%.}
    export RELEASE_COOKIE=nocookie
    #export ECTO_IPV6="true"
    export REMOTE_DATABASE_URL="ecto://postgres:postgres@$FLY_PRIVATE_IP:5432/thumbs_dev"
    export DATABASE_URL="ecto://postgres:postgres@localhost:5432/thumbs_dev"
    export SECRET_KEY_BASE=DAGr261izL5ZdFFRr7QiGG+c+kB82BrO9r0P1Lyd0BrH345ERo4GycysE3YqZI36
    export PHX_HOST="localhost"
    export MIX_ENV=prod
    export FLY_IMAGE_REF=thumbs
    export FLY_IMAGE=ghcr.io/volodiapg/thumbs:latest
    export FLY_APP_NAME="thumbs"
    export FLY_HOST=http://$PRIVATE_FLY_IP:12345
    export TAILSCALE_AUTHKEY
    TAILSCALE_AUTHKEY=$(cat .tailscale_authkey | head || exit 129)
    # mix release --overwrite
    # _build/prod/rel/thumbs/bin/thumbs start
    BUILDPATH=$(nix build --print-out-paths .#prod)
    $BUILDPATH/bin/giraff start
