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

LOG_DEBUG_FILE="${LOG_PATH}ping_test.running.log"
#####

GATEWAY_FILE="${LOG_PATH}gateway_ips.txt"
PROFILES_PATH=$1
PROFILE_NAME="Profile$2"
_ENV_FILE_="${PROFILES_PATH}env_${PROFILE_NAME}_file"

# Function: Extract gateway IPs and save to file
extract_gateway_ips() {
    ip route | awk '
        ($1 == "default" && $2 == "via") { print $3 }
        ($2 == "via") { print $3 }
    ' | sort -u > "$GATEWAY_FILE"
}

# Function: Ping each IP from file and log output
ping_gateways() {
    echo "=== Ping Test: $(date) ==="
    while read -r ip; do
        if [[ -n "$ip" ]]; then
            echo "Pinging $ip ..." 
            ping -c 4 -W 1 "$ip" 
            echo "---" 
        fi
    done < "$GATEWAY_FILE"
}

disable_nic() {
    local nic=$1
    nmcli device disconnect $nic | tee -a $LOG_DEBUG_FILE
}

enable_nic() {
    local nic=$1
    nmcli device connect $nic | tee -a $LOG_DEBUG_FILE
}

if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 <Profiles Path> <Profile Name>"
    exit 1
fi

echo "==============================Start running ping_test $(date)==============================" | tee -a $LOG_DEBUG_FILE

if [ -f $_ENV_FILE_ ]; then
    echo "Import  ${_ENV_FILE_} ....................." | tee -a $LOG_DEBUG_FILE
    source $_ENV_FILE_
else 
    echo "${_ENV_FILE_} import failed....................." | tee -a $LOG_DEBUG_FILE
    echo "Exit script." | tee -a $LOG_DEBUG_FILE
    exit 1
fi

if (( $(echo "$VERSION >= 9" | bc -l) )); then
        CONFIG_TYPE="NM"
        DAEMON_TYPE="NetworkManager"
        echo "Service : Network Manager" | tee -a $LOG_DEBUG_FILE
elif (( $(echo "$VERSION >= 8" | bc -l) )); then
        CONFIG_TYPE="NS"
        DAEMON_TYPE="NetworkManager"
        echo "Service : Network Manager by ifcfg" | tee -a $LOG_DEBUG_FILE
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
        CONFIG_TYPE="NS"
        DAEMON_TYPE="Network"
        echo "Service : Networking" | tee -a $LOG_DEBUG_FILE
else
        echo "Unable to Identify the OS Version!" | tee -a $LOG_DEBUG_FILE
        echo "Exit script." | tee -a $LOG_DEBUG_FILE
	    exit 1
fi

echo " Extract ip route gateway........" | tee -a $LOG_DEBUG_FILE
extract_gateway_ips

for nic in "${ACTIVE_NIC_LIST[@]}"; do
    echo "Disconnect Active NIC ($nic) ........" | tee -a $LOG_DEBUG_FILE
	disable_nic $nic
done

echo "Starting Ping Test $(date)............." | tee -a $LOG_DEBUG_FILE

# Don' change the log file name, it would affect the check_all_ping_latency.sh
ping_gateways |tee "${LOG_PATH}${PROFILE_NAME}_ping_by_standby-nic.log" | tee -a $LOG_DEBUG_FILE

for nic in "${ACTIVE_NIC_LIST[@]}"; do
        echo "Re-connect Active NIC ($nic) ........" | tee -a $LOG_DEBUG_FILE
        enable_nic $nic
done

for nic in "${STANDBY_NIC_LIST[@]}"; do
        echo "Disconnect Standby NIC ($nic) ........" | tee -a $LOG_DEBUG_FILE
        disable_nic $nic
done

# Don' change the log file name, it would affect the check_all_ping_latency.sh
ping_gateways |tee "${LOG_PATH}${PROFILE_NAME}_ping_by_active-nic.log" | tee -a $LOG_DEBUG_FILE

for nic in "${STANDBY_NIC_LIST[@]}"; do
        echo "Re-connect Standby NIC ($nic) ........" | tee -a $LOG_DEBUG_FILE
        enable_nic $nic
done

echo "==============Exit Ping Test! $(date) =========================" | tee -a $LOG_DEBUG_FILE


