if [ $# -lt 2 ]; then
    echo "Usage: $0 <host> <VmHostName> <*env vars as key=value, bear in mind the escaping of the value>"
    exit 1
fi

FLAKE=${FLAKE:-"@flake@"}
echo "Using flake $FLAKE"
HOST="$1"
VM_HOSTNAME="$2"
shift
shift

VARS=""
for ARG in "$@"; do
  VARS="$VARS export $ARG;"
done

chronic nix copy --to "ssh://$HOST" $FLAKE

DIR="/tmp/flame"
chronic ssh $HOST -- bash -e <<-__SSH__
  mkdir -p "$DIR"

  echo "$VARS" > "$DIR/vars"
  source $DIR/vars
  nix build --print-out-paths "$FLAKE#prod" > "$DIR/buildpath"
  export FLY_PRIVATE_IP
  FLY_PRIVATE_IP="$VM_HOSTNAME"

  nohup \$(cat "$DIR"/buildpath)/bin/function > "$DIR/log.out" 2>&1 &
__SSH__
