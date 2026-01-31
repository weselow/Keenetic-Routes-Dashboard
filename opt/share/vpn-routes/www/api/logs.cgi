#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
# VPN Routes API - Logs endpoint with filtering and pagination

echo "Content-Type: application/json"
echo ""

# Load config
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi
LOG_DIR="${LOG_DIR:-/opt/var/log/vpn-routes}"

# Parse query string helper
get_param() {
    local key="$1"
    local default="$2"
    local value=$(echo "$QUERY_STRING" | tr '&' '\n' | grep "^${key}=" | cut -d'=' -f2 | head -1)
    # URL decode basic characters
    value=$(echo "$value" | sed 's/%20/ /g; s/%2F/\//g; s/%3A/:/g; s/+/ /g')
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get parameters
date_param=$(get_param "date" "$(date '+%Y-%m-%d')")
level_param=$(get_param "level" "all")
search_param=$(get_param "search" "")
page=$(get_param "page" "1")
per_page=$(get_param "per_page" "100")

# Validate numbers
[ "$page" -lt 1 ] 2>/dev/null && page=1
[ "$per_page" -lt 1 ] 2>/dev/null && per_page=100
[ "$per_page" -gt 500 ] 2>/dev/null && per_page=500

# Build log file path
log_file="$LOG_DIR/vpn-routes.$date_param.log"

# Check if file exists
if [ ! -f "$log_file" ]; then
    cat << EOF
{
  "date": "$date_param",
  "total": 0,
  "page": 1,
  "per_page": $per_page,
  "pages": 0,
  "error_count": 0,
  "lines": []
}
EOF
    exit 0
fi

# Read and filter log file
filter_logs() {
    local content=$(cat "$log_file")

    # Filter by level
    if [ "$level_param" != "all" ]; then
        level_upper=$(echo "$level_param" | tr 'a-z' 'A-Z')
        content=$(echo "$content" | grep "\[$level_upper\]")
    fi

    # Filter by search term
    if [ -n "$search_param" ]; then
        content=$(echo "$content" | grep -i "$search_param")
    fi

    echo "$content"
}

filtered_content=$(filter_logs)

# Count total and errors
total=$(printf '%s' "$filtered_content" | grep -c "." 2>/dev/null)
total=${total:-0}
error_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null)
error_count=${error_count:-0}

# Calculate pagination
pages=$(( (total + per_page - 1) / per_page ))
[ "$pages" -lt 1 ] && pages=1
[ "$page" -gt "$pages" ] && page=$pages

# Calculate offset
offset=$(( (page - 1) * per_page ))

# Get page of logs
page_content=$(echo "$filtered_content" | tail -n +$((offset + 1)) | head -n "$per_page")

# Parse log lines and build JSON array
lines_json=""
first=1

while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Parse format: [YYYY-MM-DD HH:MM:SS] [LEVEL] Message
    # Extract time (HH:MM:SS)
    time_val=$(echo "$line" | sed -n 's/^\[[0-9-]* \([0-9:]*\)\].*/\1/p')
    # Extract level
    level_val=$(echo "$line" | sed -n 's/^[^]]*\] \[\([A-Z]*\)\].*/\1/p')
    # Extract message (everything after second ])
    message_val=$(echo "$line" | sed 's/^[^]]*\] \[[A-Z]*\] //')

    # Escape for JSON
    message_escaped=$(echo "$message_val" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')

    # Build JSON object
    if [ $first -eq 1 ]; then
        lines_json="{\"time\": \"$time_val\", \"level\": \"$level_val\", \"message\": \"$message_escaped\"}"
        first=0
    else
        lines_json="$lines_json, {\"time\": \"$time_val\", \"level\": \"$level_val\", \"message\": \"$message_escaped\"}"
    fi
done << EOF
$page_content
EOF

# Output JSON
cat << ENDJSON
{
  "date": "$date_param",
  "total": $total,
  "page": $page,
  "per_page": $per_page,
  "pages": $pages,
  "error_count": $error_count,
  "lines": [$lines_json]
}
ENDJSON
