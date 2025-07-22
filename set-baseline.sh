#!/bin/bash
SERVERNAME=`hostname`
LOG_PATH="/tmp/$SERVERNAME"

if [ ! -d "$LOG_PATH" ]; then
    echo "Creating log folder - $LOG_PATH"
    mkdir -p $LOG_PATH
fi

GATEWAY_FILE="$LOG_PATH/gateway_ips.txt"
# Create/clear gateway IP file
> "$GATEWAY_FILE"

# Function: Extract gateway IPs and save to file
extract_gateway_ips() {
    ip route | awk '
        ($1 == "default" && $2 == "via") { print $3 }
        ($2 == "via") { print $3 }
    ' | sort -u > "$GATEWAY_FILE"
}

ping_gateways() {
    echo "=== Ping Test: $(date) ===" >> "$1"
    while read -r ip; do
        if [[ -n "$ip" ]]; then
            echo "Pinging $ip ..." | tee -a "$1"
            ping -c 4 -W 1 "$ip" >> "$1" 2>&1
            echo "---" >> "$1"
        fi
    done < "$GATEWAY_FILE"
}

echo " Extract ip route gateway........ "
extract_gateway_ips

echo "Create ping baseline............. "
ping_gateways "$LOG_PATH/original_ping.log"
