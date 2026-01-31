#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Delete logs endpoint

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
LOG_DIR="${LOG_DIR:-/opt/var/log/vpn-routes}"

# Read POST data
read -r POST_DATA

# Parse action and date from JSON
action=$(echo "$POST_DATA" | sed -n 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
date_param=$(echo "$POST_DATA" | sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Validate action
case "$action" in
    delete_date)
        # Validate date format
        if ! echo "$date_param" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            echo '{"success": false, "error": "Invalid date format"}'
            exit 0
        fi

        log_file="$LOG_DIR/vpn-routes.$date_param.log"
        if [ -f "$log_file" ]; then
            rm -f "$log_file"
            echo "{\"success\": true, \"message\": \"Deleted log for $date_param\"}"
        else
            echo '{"success": false, "error": "Log file not found"}'
        fi
        ;;
    delete_all)
        if [ -d "$LOG_DIR" ]; then
            count=$(ls -1 "$LOG_DIR"/vpn-routes.*.log 2>/dev/null | wc -l)
            rm -f "$LOG_DIR"/vpn-routes.*.log
            echo "{\"success\": true, \"message\": \"Deleted $count log files\"}"
        else
            echo '{"success": false, "error": "Log directory not found"}'
        fi
        ;;
    *)
        echo '{"success": false, "error": "Invalid action. Use delete_date or delete_all"}'
        ;;
esac
