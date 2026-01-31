#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - List available log dates

echo "Content-Type: application/json"
echo ""

# Load config
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi
LOG_DIR="${LOG_DIR:-/opt/var/log/vpn-routes}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"

# Check if directory exists
if [ ! -d "$LOG_DIR" ]; then
    cat << EOF
{
  "dates": [],
  "retention_days": $LOG_RETENTION_DAYS
}
EOF
    exit 0
fi

# Build JSON array of dates
dates_json=""
first=1

# List log files sorted by date (newest first)
for log_file in $(ls -1t "$LOG_DIR"/vpn-routes.*.log 2>/dev/null); do
    [ ! -f "$log_file" ] && continue

    # Extract date from filename
    filename=$(basename "$log_file")
    date_val=$(echo "$filename" | sed 's/vpn-routes\.\([0-9-]*\)\.log/\1/')

    # Validate date format
    if ! echo "$date_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        continue
    fi

    # Get file size
    size=$(wc -c < "$log_file" 2>/dev/null)
    size=${size:-0}

    # Count errors
    error_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null)
    error_count=${error_count:-0}

    # Count total lines
    line_count=$(wc -l < "$log_file" 2>/dev/null)
    line_count=${line_count:-0}

    # Build JSON object
    if [ $first -eq 1 ]; then
        dates_json="{\"date\": \"$date_val\", \"size\": $size, \"lines\": $line_count, \"error_count\": $error_count}"
        first=0
    else
        dates_json="$dates_json, {\"date\": \"$date_val\", \"size\": $size, \"lines\": $line_count, \"error_count\": $error_count}"
    fi
done

# Output JSON
cat << EOF
{
  "dates": [$dates_json],
  "retention_days": $LOG_RETENTION_DAYS
}
EOF
