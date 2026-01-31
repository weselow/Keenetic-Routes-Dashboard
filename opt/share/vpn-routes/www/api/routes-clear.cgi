#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Clear routes endpoint

echo "Content-Type: application/json"
echo ""

# Only allow POST
if [ "$REQUEST_METHOD" != "POST" ]; then
    echo '{"success": false, "error": "Method not allowed"}'
    exit 0
fi

# Load config
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi
IPSET_NAME="${IPSET_NAME:-vpn_routes}"
ROUTES_CACHE="${ROUTES_CACHE:-/opt/etc/vpn-routes/routes.list}"

# Clear ipset
ipset_cleared=0
if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    ipset flush "$IPSET_NAME"
    ipset_cleared=1
fi

# Delete cache file
cache_deleted=0
if [ -f "$ROUTES_CACHE" ]; then
    rm -f "$ROUTES_CACHE"
    cache_deleted=1
fi

echo "{\"success\": true, \"ipset_cleared\": $ipset_cleared, \"cache_deleted\": $cache_deleted}"
