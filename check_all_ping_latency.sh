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
fi

if [ ! -d "$LOG_PATH" ]; then
    echo "Creating log folder - $LOG_PATH"
    mkdir -p $LOG_PATH
fi

LOG_DEBUG_FILE="${LOG_PATH}check_all_ping_latency.running.log"
OUTPUT_FILE="${LOG_PATH}check_all_ping_latency.log"
echo "==============================Exit script $(date)===============================" | tee -a $LOG_DEBUG_FILE
#####

PING_LOG_FILES=("ProfileAA_ping_by_active-nic.log" "ProfileAA_ping_by_standby-nic.log" "ProfileBA_ping_by_active-nic.log" "ProfileBA_ping_by_standby-nic.log" "ProfileBB_ping_by_active-nic.log" "ProfileBB_ping_by_standby-nic.log")
LATENCY_THRESHOLD=3.0

check_latency_block() {
    local ip="$1"
    local profile="$2"
    local b=$3
    local nic="$4"
    local latency_list=()
    local unreachable=0
    local line
    local loss_line=""
    local last3_high_count=0

    while read -r line; do
        # Capture latency value
        if [[ "$line" =~ time=([0-9.]+)\ ms ]]; then
            latency="${BASH_REMATCH[1]}"
            latency_list+=("$latency")
        fi

        # Check if 100% packet loss

        if  [[ "$line" =~ 100%\ packet\ loss ]]; then
            unreachable=1
        fi

        # End of current block
#        if [[ "$line" == "--- $ip ping statistics ---" ]]; then
        if [[ "$line" =~ packets\ transmitted ]]; then
            break
        fi
    done

   #Debug mode
   #echo "Unreachable value: $unreachable"
   #echo "Last line : $line"


    if [[ "$unreachable" -eq 1 ]]; then
        echo "${profile} : Using ${b} - ${nic} to ping $ip: Unreachable"
        return
    fi

    local total=${#latency_list[@]}

    # Sanity check: fewer than 4 pings?
    if [[ "$total" -lt 4 ]]; then
        echo "${profile} : Using ${b} - ${nic} to ping $ip: Insufficient data"
        return
    fi

    # Only allow first ping to be higher than threshold
    for ((i = 1; i < total; i++)); do
        if (( $(echo "${latency_list[$i]} > $LATENCY_THRESHOLD" | bc -l) )); then
            if (( i >= total - 3 )); then
                ((last3_high_count++))
            fi
        fi
    done

    if [[ "$last3_high_count" -eq 3 ]]; then
        #echo "$ip: High latency"               ##### Change on 24-Jul-2025 : Disabled High latency return
        ##### Change on 25-Jul-2025 : Show the Profile and NIC to ping the IP.
        echo "${profile} : Using ${b} - ${nic} to ping $ip: Normal"
    else
        ##### Change on 25-Jul-2025 : Show the Profile and NIC to ping the IP.
        echo "${profile} : Using ${b} - ${nic} to ping $ip: Normal"
    fi
}

extract_bond(){
    local network="${1%.*}"
    local bond=""
#    echo "Extracted Network ${network}" | tee -a "$LOG_DEBUG_FILE"

    bond=$(grep -i "$network".0/ "${LOG_PATH}original_route.log" | awk '
        ($2 == "dev") { print $3 }
        ($2 == "via") { print $5 }
    ' | sort -u)

    echo "$bond"
}

# Main loop: parse blocks per IP
for logfile in "${PING_LOG_FILES[@]}"; do
        log_file="${LOG_PATH}${logfile}"
    ##### Change on 25-Jul-2025 : Show the Profile and NIC to ping the IP.
    if [[ "$logfile" =~ ^([^_]+)_([^_]+)_([^_]+)_([^_]+)\.log$ ]]; then
        running_profile="${BASH_REMATCH[1]}"    # ProfileAA
        running_nic="${BASH_REMATCH[4]}"        # active-nic
    else
        echo "Filename does not match expected format"
        exit 1
    fi
    #####

        if [ -f "$log_file" ] ; then
                echo "Checking $log_file .........." | tee $OUTPUT_FILE | tee -a $LOG_DEBUG_FILE
                while read -r line; do
                    if [[ "$line" =~ ^PING[[:space:]]([0-9.]+)[[:space:]] ]]; then
                        ip="${BASH_REMATCH[1]}"
                ##### Change on 25-Jul-2025 : Show the Profile and NIC to ping the IP.
                running_bond="$(extract_bond $ip)"
                        check_latency_block "$ip" $running_profile $running_bond $running_nic | tee $OUTPUT_FILE |tee -a $LOG_DEBUG_FILE
                    fi
                done < "$log_file"
        else
                echo "$log_file not exist!" | tee $OUTPUT_FILE |tee -a $LOG_DEBUG_FILE
        fi
done

echo "==============================Exit script $(date)===============================" | tee -a $LOG_DEBUG_FILE
