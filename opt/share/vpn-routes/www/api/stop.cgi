#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Stop endpoint

echo "Content-Type: application/json"
echo ""

# Only allow POST
if [ "$REQUEST_METHOD" != "POST" ]; then
    echo '{"success": false, "error": "Method not allowed"}'
    exit 0
fi

# Run stop
output=$(/opt/bin/vpn-routes.sh stop 2>&1)
exit_code=$?

# Escape output for JSON
output_escaped=$(echo "$output" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')

if [ $exit_code -eq 0 ]; then
    echo "{\"success\": true, \"output\": \"$output_escaped\"}"
else
    echo "{\"success\": false, \"error\": \"Exit code: $exit_code\", \"output\": \"$output_escaped\"}"
fi
