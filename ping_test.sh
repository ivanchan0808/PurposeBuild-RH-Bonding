#!/bin/bash

SERVER=`hostname`
GATEWAY_FILE="/tmp/${SERVER}/gateway_ips.txt"
LOG_PATH="/tmp/${SERVER}/"
PROFILES_PATH=$1
PROFILE_NAME="Profile$2"
VERSION=`awk '{print $6}' /etc/redhat-release`

# Function: Extract gateway IPs and save to file
extract_gateway_ips() {
    ip route | awk '
        ($1 == "default" && $2 == "via") { print $3 }
        ($2 == "via") { print $3 }
    ' | sort -u > "$GATEWAY_FILE"
}

# Function: Ping each IP from file and log output
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

disable_nic() {
    local nic=$1
    nmcli device disconnect $nic
}

enable_nic() {
    local nic=$1
    nmcli device connect $nic
}

if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 <Profiles Path> <Profile Name>"
    exit 1
fi

source $PROFILES_PATH/env_"$PROFILE_NAME"_file

if (( $(echo "$VERSION >= 9" | bc -l) )); then
        CONFIG_TYPE="NM"
        DAEMON_TYPE="NetworkManager"
        echo "Service : Network Manager"
elif (( $(echo "$VERSION >= 8" | bc -l) )); then
        CONFIG_TYPE="NS"
        DAEMON_TYPE="NetworkManager"
        echo "Service : Network Manager by ifcfg"
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
        CONFIG_TYPE="NS"
        DAEMON_TYPE="Network"
        echo "Service : Networking"
else
        echo "Unable to Identify the OS Version!"
	exit 1
fi

echo " Extract ip route gateway........ "
extract_gateway_ips

for nic in "${ACTIVE_NIC_LIST[@]}"; do
        echo "Disconnect Active_NIC ($nic) ........"
	disable_nic $nic
done

echo "Starting Ping Test ............."
ping_gateways "${LOG_PATH}/${PROFILE_NAME}_ping_active-nic.log"

for nic in "${ACTIVE_NIC_LIST[@]}"; do
        echo "Re-connect Active_NIC ($nic) ........"
        enable_nic $nic
done

for nic in "${STANDBY_NIC_LIST[@]}"; do
        echo "Disconnect Active_NIC ($nic) ........"
        disable_nic $nic
done

ping_gateways "${LOG_PATH}/${PROFILE_NAME}_ping_standby-nic.log"

for nic in "${STANDBY_NIC_LIST[@]}"; do
        echo "Re-connect Active_NIC ($nic) ........"
        enable_nic $nic
done

echo "End of Ping Test!"

