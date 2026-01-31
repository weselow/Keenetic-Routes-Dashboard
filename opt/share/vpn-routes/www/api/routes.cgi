#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Routes endpoint with pagination

echo "Content-Type: application/json"
echo ""

# Load config for cache path
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi
ROUTES_CACHE="${ROUTES_CACHE:-/opt/etc/vpn-routes/routes.list}"
IPSET_NAME="${IPSET_NAME:-vpn_routes}"

# Parse query string
parse_query() {
    local key="$1"
    local default="$2"
    echo "$QUERY_STRING" | tr '&' '\n' | grep "^${key}=" | cut -d'=' -f2 | head -1 | sed 's/[^0-9a-zA-Z\.\/]//g'
}

# Get parameters
page=$(parse_query "page" "1")
per_page=$(parse_query "per_page" "50")
search=$(parse_query "search" "")

# Validate numbers
[ -z "$page" ] && page=1
[ -z "$per_page" ] && per_page=50
[ "$page" -lt 1 ] 2>/dev/null && page=1
[ "$per_page" -lt 1 ] 2>/dev/null && per_page=50
[ "$per_page" -gt 100 ] 2>/dev/null && per_page=100

# Get routes from ipset (or cache if ipset empty)
if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    routes_data=$(ipset list "$IPSET_NAME" 2>/dev/null | grep "^[0-9]")
elif [ -f "$ROUTES_CACHE" ]; then
    routes_data=$(cat "$ROUTES_CACHE")
else
    routes_data=""
fi

# Apply search filter if provided
if [ -n "$search" ]; then
    routes_data=$(echo "$routes_data" | grep "$search")
fi

# Count total
total=$(echo "$routes_data" | grep -c "." || echo 0)
[ -z "$total" ] && total=0

# Calculate pages
pages=$(( (total + per_page - 1) / per_page ))
[ "$pages" -lt 1 ] && pages=1

# Validate page
[ "$page" -gt "$pages" ] && page=$pages

# Calculate offset
offset=$(( (page - 1) * per_page ))

# Get page of routes
routes_page=$(echo "$routes_data" | tail -n +$((offset + 1)) | head -n "$per_page")

# Build JSON array of routes
routes_json=""
first=1
while IFS= read -r route; do
    [ -z "$route" ] && continue
    if [ $first -eq 1 ]; then
        routes_json="\"$route\""
        first=0
    else
        routes_json="$routes_json, \"$route\""
    fi
done << EOF
$routes_page
EOF

# Output JSON
cat << ENDJSON
{
  "total": $total,
  "page": $page,
  "per_page": $per_page,
  "pages": $pages,
  "routes": [$routes_json]
}
ENDJSON
