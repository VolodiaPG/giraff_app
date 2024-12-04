FLY_PRIVATE_IP=$(tailscale "$@" status --self --json 2> /dev/null | jq -r '.Self.TailscaleIPs[0]')
FLY_PRIVATE_IP=${FLY_PRIVATE_IP%.}

if [[ "$FLY_PRIVATE_IP" == "" ]]; then
  echo "FLY_PRIVATE_IP empty, could not determinate it"
  exit 1
fi

if [[ "$1" == "--json" ]]; then
  echo "{\"Ip\": \"$FLY_PRIVATE_IP\"}"
else
  echo "$FLY_PRIVATE_IP"
fi

