tailscale status --json 2>/dev/null | jq -r '.Peer[] | select(.Tags != null and .Tags == ["tag:server"]) | .HostName'
