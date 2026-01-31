#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Interfaces endpoint

echo "Content-Type: application/json"
echo ""

# Find WireGuard and other VPN interfaces
interfaces_json=""
first=1

# Get nwg* interfaces (WireGuard on Keenetic)
for iface in $(ip link show 2>/dev/null | grep -E "^[0-9]+: (nwg|wg|tun|ppp)" | awk -F': ' '{print $2}' | cut -d'@' -f1); do
    # Skip loopback and system interfaces
    case "$iface" in
        lo|tunl0|sit0|gre0|ip6tnl0) continue ;;
    esac

    # Get IP address
    ip_addr=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
    [ -z "$ip_addr" ] && ip_addr="no ip"

    # Check if up
    is_up="false"
    if ip link show "$iface" 2>/dev/null | grep -q ",UP"; then
        is_up="true"
    fi

    # Get interface type
    iface_type="unknown"
    case "$iface" in
        nwg*|wg*) iface_type="wireguard" ;;
        tun*) iface_type="tun" ;;
        ppp*) iface_type="pppoe" ;;
    esac

    # Build JSON object
    if [ $first -eq 1 ]; then
        interfaces_json="{\"name\": \"$iface\", \"ip\": \"$ip_addr\", \"up\": $is_up, \"type\": \"$iface_type\"}"
        first=0
    else
        interfaces_json="$interfaces_json, {\"name\": \"$iface\", \"ip\": \"$ip_addr\", \"up\": $is_up, \"type\": \"$iface_type\"}"
    fi
done

# Output JSON
cat << EOF
{
  "interfaces": [$interfaces_json]
}
EOF
