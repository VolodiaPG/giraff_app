export FLY_PRIVATE_IP
FLY_PRIVATE_IP=$(node_name --socket="/var/run/tailscale/tailscaled.sock")
echo "My ip: $FLY_PRIVATE_IP"
exec "$@"

