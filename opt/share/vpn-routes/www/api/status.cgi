#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Status endpoint

echo "Content-Type: application/json"
echo ""

# Load config
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Default values
VPN_INTERFACE="${VPN_INTERFACE:-nwg1}"
IPSET_NAME="${IPSET_NAME:-vpn_routes}"
FWMARK="${FWMARK:-0x1}"
ROUTE_TABLE="${ROUTE_TABLE:-100}"
ROUTES_CACHE="${ROUTES_CACHE:-/opt/etc/vpn-routes/routes.list}"

# Check interface status
interface_up="false"
interface_ip=""
if ip link show "$VPN_INTERFACE" 2>/dev/null | grep -q "UP"; then
    interface_up="true"
fi
interface_ip=$(ip addr show "$VPN_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)

# Count ipset entries
ipset_count=0
if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    ipset_count=$(ipset list "$IPSET_NAME" 2>/dev/null | grep -c "^[0-9]" || echo 0)
fi

# Count routes in cache
routes_count=0
if [ -f "$ROUTES_CACHE" ]; then
    routes_count=$(wc -l < "$ROUTES_CACHE" 2>/dev/null | tr -d ' ')
fi

# Get last update time
last_update=""
if [ -f "$ROUTES_CACHE" ]; then
    last_update=$(stat -c %y "$ROUTES_CACHE" 2>/dev/null | cut -d. -f1)
    if [ -z "$last_update" ]; then
        last_update=$(date -r "$ROUTES_CACHE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    fi
fi

# Check iptables rules
iptables_prerouting="false"
iptables_output="false"
if iptables -t mangle -L PREROUTING -n 2>/dev/null | grep -q "$IPSET_NAME"; then
    iptables_prerouting="true"
fi
if iptables -t mangle -L OUTPUT -n 2>/dev/null | grep -q "$IPSET_NAME"; then
    iptables_output="true"
fi

# Check ip rule
ip_rule="false"
if ip rule show 2>/dev/null | grep -q "fwmark $FWMARK"; then
    ip_rule="true"
fi

# Determine overall status
status="stopped"
if [ "$ipset_count" -gt 0 ] && [ "$iptables_prerouting" = "true" ] && [ "$ip_rule" = "true" ]; then
    status="active"
fi

# Output JSON
cat << EOF
{
  "status": "$status",
  "interface": "$VPN_INTERFACE",
  "interface_ip": "$interface_ip",
  "interface_up": $interface_up,
  "ipset_count": $ipset_count,
  "routes_count": $routes_count,
  "last_update": "$last_update",
  "iptables_prerouting": $iptables_prerouting,
  "iptables_output": $iptables_output,
  "ip_rule": $ip_rule
}
EOF
