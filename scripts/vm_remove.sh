if [ $# -lt 2 ]; then
  echo "Usage: $0 <host> <VmHostName>"
    exit 1
fi
HOST="$1"
VM_HOSTNAME="$2"
exec ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeychecking=no root@"$HOST" "systemctl stop 'microvm@$VM_HOSTNAME.service'; rm -rf '/var/lib/microvms/$VM_HOSTNAME'; rm -rf '/var/lib/flame/$VM_HOSTNAME'" 2>/dev/null
