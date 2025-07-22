#!/bin/bash

SERVER=`hostname`
PING_LOG_FILES=("ProfileAA_ping_active-nic.log" "ProfileAA_ping_standby-nic.log" "ProfileBA_ping_active-nic.log" "ProfileBA_ping_standby-nic.log" "ProfileBB_ping_active-nic.log" "ProfileBB_ping_standby-nic.log")
LATENCY_THRESHOLD=3.0

check_latency_block() {
    local ip="$1"
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
        echo "$ip: Unreachable" 
        return
    fi

    local total=${#latency_list[@]}

    # Sanity check: fewer than 4 pings?
    if [[ "$total" -lt 4 ]]; then
        echo "$ip: Insufficient data"
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
        echo "$ip: High latency"
    else
        echo "$ip: Normal"
    fi
}

# Main loop: parse blocks per IP
for logfile in "${PING_LOG_FILES[@]}"; do
	log_path="/tmp/${SERVER}/${logfile}"
	if [ -f "$log_path" ] ; then 
		echo "Checking $log_path .........." | tee -a "/tmp/${SERVER}/${0}.log"
		while read -r line; do
		    if [[ "$line" =~ ^PING[[:space:]]([0-9.]+)[[:space:]] ]]; then
        		ip="${BASH_REMATCH[1]}"
		        check_latency_block "$ip" | tee -a "/tmp/${SERVER}/${0}.log"
		    fi
		done < "$log_path"
	else
		echo "$log_path not exist!"
	fi
done
