#!/bin/bash

##### New add on 24-Jul-2025
VERSION=`awk '{print $6}' /etc/redhat-release`
if (( $(echo "$VERSION >= 8" | bc -l) )); then
    USER="ps_syssupp"
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
    USER="syssupp"
fi

SERVER=`hostname`
LOG_PATH="/home/${USER}/otpc_log_${SERVER}/"

if [ ! -d "/home/${USER}" ]; then
    LOG_PATH="/tmp/otpc_log_${SERVER}/"
    echo "${USER} is not exit!"
    echo " LOG PATH change to ${LOG_PATH}!"
    USER=`whoami`
fi  

if [ ! -d "$LOG_PATH" ]; then
    echo "Creating log folder - $LOG_PATH"
    mkdir -p $LOG_PATH
fi

LOG_DEBUG_FILE="${LOG_PATH}set-baseline.running.log"
echo "========================Start running script $(date)========================" | tee -a LOG_DEBUG_FILE
#####

GATEWAY_FILE="${LOG_PATH}/gateway_ips.txt"
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

echo " ================== Start running set-baseline on $(date) ==================" |tee -a $LOG_DEBUG_FILE
echo " Extract ip route gateway........ " |tee -a $LOG_DEBUG_FILE
extract_gateway_ips |tee -a $LOG_DEBUG_FILE

echo "Create ping baseline............. " |tee -a $LOG_DEBUG_FILE
ping_gateways "${LOG_PATH}/original_ping.log" |tee -a $LOG_DEBUG_FILE

echo "Create IP Route baseline............. " |tee -a $LOG_DEBUG_FILE
ip route | tee "${LOG_PATH}/original_route.log" |tee -a $LOG_DEBUG_FILE
echo " ================== Exit script $(date) ==================" |tee -a $LOG_DEBUG_FILE

echo "==============================Exit script $(date)===============================" | tee -a LOG_DEBUG_FILE