if [ $# -lt 1 ]; then
    echo "Usage: $0 <VmHostName>"
    exit 1
fi
VM_HOSTNAME="$1"

tailscale status --json 2>/dev/null | jq -r ".Peer[] | select(.HostName != null and .HostName == \"$VM_HOSTNAME\") | .TailscaleIPs[0]"
