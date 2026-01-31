#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Config endpoint (GET/POST)

CONFIG_FILE="/opt/etc/vpn-routes/config.sh"

# Function to output JSON
json_response() {
    echo "Content-Type: application/json"
    echo ""
    echo "$1"
}

# Function to read config value
get_config_value() {
    local key="$1"
    local default="$2"
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${key}=" "$CONFIG_FILE" | cut -d'"' -f2)
        if [ -n "$value" ]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Handle GET request
handle_get() {
    routes_url=$(get_config_value "ROUTES_URL" "")
    vpn_interface=$(get_config_value "VPN_INTERFACE" "nwg1")
    ipset_name=$(get_config_value "IPSET_NAME" "vpn_routes")
    fwmark=$(get_config_value "FWMARK" "0x1")
    route_table=$(get_config_value "ROUTE_TABLE" "100")
    verbose=$(get_config_value "VERBOSE" "1")

    json_response "{
  \"routes_url\": \"$routes_url\",
  \"vpn_interface\": \"$vpn_interface\",
  \"ipset_name\": \"$ipset_name\",
  \"fwmark\": \"$fwmark\",
  \"route_table\": \"$route_table\",
  \"verbose\": \"$verbose\"
}"
}

# Handle POST request
handle_post() {
    # Read POST data
    read -r POST_DATA

    # Parse JSON (simple parsing for known fields)
    new_url=$(echo "$POST_DATA" | sed -n 's/.*"routes_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    new_interface=$(echo "$POST_DATA" | sed -n 's/.*"vpn_interface"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    # Validate
    if [ -z "$new_url" ] && [ -z "$new_interface" ]; then
        json_response '{"success": false, "error": "No valid data provided"}'
        return
    fi

    # Read current config
    if [ ! -f "$CONFIG_FILE" ]; then
        json_response '{"success": false, "error": "Config file not found"}'
        return
    fi

    # Update config file
    if [ -n "$new_url" ]; then
        # Escape special sed characters for replacement: \ & |
        new_url_escaped=$(printf '%s' "$new_url" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/|/\\|/g')
        sed -i "s|^ROUTES_URL=.*|ROUTES_URL=\"$new_url_escaped\"|" "$CONFIG_FILE"
    fi
    if [ -n "$new_interface" ]; then
        sed -i "s|^VPN_INTERFACE=.*|VPN_INTERFACE=\"$new_interface\"|" "$CONFIG_FILE"
    fi

    json_response '{"success": true}'
}

# Route by request method
case "$REQUEST_METHOD" in
    GET)
        handle_get
        ;;
    POST)
        handle_post
        ;;
    *)
        json_response '{"error": "Method not allowed"}'
        ;;
esac
