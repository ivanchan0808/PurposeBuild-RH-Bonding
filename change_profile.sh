#!/bin/bash

##### New add on 24-Jul-2025
VERSION=`awk '{print $6}' /etc/redhat-release`
echo "OS : RHEL ${VERSION}" | tee -a $LOG_DEBUG_FILE
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

LOG_DEBUG_FILE="${LOG_PATH}change_profile.running.log"
echo "========================Start running script $(date)========================" | tee -a $LOG_DEBUG_FILE
#####

PROFILES_PATH=$1						    	#The path store all the profiles
PROFILE_NAME="Profile$2"						#Approach AA BA BB
PROFILE_FOLDER="$PROFILES_PATH""/$PROFILE_NAME"

CONFIG_TYPE=""
CONFIG_PATH=""
DAEMON_TYPE=""
NS_CONFIG_PATH="/etc/sysconfig/network-scripts/"
NM_CONFIG_PATH="/etc/NetworkManager/system-connections/"
LAST_RUN_SUFFIX="_snapshot_$(date +%Y%m%d_%H%M%S)"
RUNNING_PROFILE_FILE="${PROFILES_PATH}env_last_run_profile"
LAST_RUN_FOLDER="${PROFILES_PATH}last_run/"
LAST_RUN_PROFILE=""


#if [ "$2" == "backup" ]; then
#        PROFILE_NAME="ProfileAA"
#fi

echo "IMPORT ENV FILE : ${PROFILE_NAME}" | tee -a $LOG_DEBUG_FILE
source $PROFILES_PATH/env_"$PROFILE_NAME"_file

echo "Imported Active NICs record : ${ACTIVE_NIC_LIST[@]}" | tee -a $LOG_DEBUG_FILE
echo "Imported Standby NICs record : ${STANDBY_NIC_LIST[@]}" | tee -a $LOG_DEBUG_FILE

if [[ -f "${RUNNING_PROFILE_FILE}" ]] ; then
    echo "IMPORT ENV FILE : ${RUNNING_PROFILE_FILE}" | tee -a $LOG_DEBUG_FILE
    source $RUNNING_PROFILE_FILE
fi



reload_service() {
	local service=$1
	
	if [[ $service == "Network" ]]; then
		systemctl restart network  | tee -a $LOG_DEBUG_FILE
	elif [[ $service == "NetworkManager" ]]; then
		nmcli connection reload  | tee -a $LOG_DEBUG_FILE
		systemctl restart NetworkManager  | tee -a $LOG_DEBUG_FILE
	fi
}

##### New added at 23-July for handling RHEL9 behavior-auto create Wired connection when the NICs are connected.
delete_stale_connections() {
    # Get all "Wired connection" names
    nmcli -t -f NAME connection show | grep -E '^Wired connection' | while IFS= read -r conn; do
        echo "Deleting connection: $conn"  | tee -a $LOG_DEBUG_FILE
        nmcli connection delete "$conn"  | tee -a $LOG_DEBUG_FILE
    done

    for nic in "${ACTIVE_NIC_LIST[@]}"; do
        nmcli connection delete $nic  | tee -a $LOG_DEBUG_FILE
    done

    for nic in "${STANDBY_NIC_LIST[@]}"; do
        nmcli connection delete $nic  | tee -a $LOG_DEBUG_FILE
    done
}
#####

check_config() {
    local eth=$1
    if ip address show "$eth" | grep -iq "master bond*" ; then
        echo "CHECK_CONFIG() RETURN=TRUE"  | tee -a $LOG_DEBUG_FILE
        return 0    # true
    else
        echo "CHECK_CONFIG() RETURN=FALSE"  | tee -a $LOG_DEBUG_FILE
        return 1    # false
    fi
}

rename_last_run_folder(){
    local new_name="${1}_${LAST_RUN_SUFFIX}"
    local folder="${LAST_RUN_FOLDER}${1}"
    if [[ -d $folder ]]; then
        echo "Enter rename_last_run_folder()" | tee -a $LOG_DEBUG_FILE
        echo "Rename ${folder} to ${LAST_RUN_FOLDER}${new_name}" | tee -a $LOG_DEBUG_FILE
        mv  $folder "${LAST_RUN_FOLDER}${new_name}"
    fi
}


if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 <Profiles Path> <Profile Name>" | tee -a $LOG_DEBUG_FILE
    exit 1
fi

if (( $(echo "$VERSION >= 9" | bc -l) )); then
    CONFIG_TYPE="NM"
	CONFIG_PATH=$NM_CONFIG_PATH
	DAEMON_TYPE="NetworkManager"
	echo "Service : Network Manager" | tee -a $LOG_DEBUG_FILE
elif (( $(echo "$VERSION >= 8" | bc -l) )); then
	CONFIG_TYPE="NS"
	CONFIG_PATH=$NS_CONFIG_PATH
	DAEMON_TYPE="NetworkManager"
	echo "Service : Network Manager by ifcfg"  | tee -a $LOG_DEBUG_FILE
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
	CONFIG_TYPE="NS"
	CONFIG_PATH=$NS_CONFIG_PATH
	DAEMON_TYPE="Network"
	echo "Service : Networking"  | tee -a $LOG_DEBUG_FILE
else 
	echo "Unable to Identify the OS Version!" | tee -a $LOG_DEBUG_FILE
    exit 1
fi

echo "CONFIG_TYPE : ${CONFIG_TYPE}" | tee -a $LOG_DEBUG_FILE
echo "CONFIG_PATH : ${CONFIG_PATH}" | tee -a $LOG_DEBUG_FILE
echo "DAEMON_TYPE : ${DAEMON_TYPE}" | tee -a $LOG_DEBUG_FILE


#if [[ $2 == "backup" ]] ; then
#	PROFILE_FOLDER=$1"backup"
#    echo "Restore the Backup................." | tee -a $LOG_DEBUG_FILE
#fi

#if [ ! -d "${PROFILES_PATH}/backup/" ] ; then
#	echo "Backup $CONFIG_PATH to $PROFILE_PATH..........." | tee -a $LOG_DEBUG_FILE
#	mv $CONFIG_PATH "${PROFILES_PATH}/backup"
#fi

if [[ ! -d $PROFILE_FOLDER ]] ; then
	echo "The profile folder is not exist! The profile may be applied! "  | tee -a $LOG_DEBUG_FILE
    exit 1
fi

##### Added on 25-Jul-2025, for config comparison
if [[ ! -d "$LAST_RUN_FOLDER" ]] ; then
	echo "Create last_run folder ${LAST_RUN_FOLDER}..........." | tee -a $LOG_DEBUG_FILE
	mkdir -p $LAST_RUN_FOLDER
fi
#####

if [[ ! -d $CONFIG_PATH ]] ; then
    if [[ $CONFIG_TYPE == "NM" ]]; then
	    delete_stale_connections
    fi
    echo "Moving ${PROFILE_FOLDER} setting to ${CONFIG_PATH}"  | tee -a $LOG_DEBUG_FILE
	mv -b $PROFILE_FOLDER $CONFIG_PATH
    reload_service $DAEMON_TYPE
else 
    ##### Added on 25-Jul-2025, for config comparison    
    if [[ -f $RUNNING_PROFILE_FILE ]]; then
        echo "${RUNNING_PROFILE_FILE} is exist! Running profile : ${LAST_RUN_PROFILE}"  | tee -a $LOG_DEBUG_FILE
        if [[ $LAST_RUN_PROFILE == "ProfileAA" || $LAST_RUN_PROFILE == "ProfileBA" || $LAST_RUN_PROFILE == "ProfileBB" ]]; then
            echo "Macth LAST_RUN_PROFILE Profile value! Start rename the Profile under last_run. " | tee -a $LOG_DEBUG_FILE
            rename_last_run_folder $LAST_RUN_PROFILE
            echo "Moving ${CONFIG_PATH} setting to ${LAST_RUN_FOLDER}${LAST_RUN_PROFILE}"  | tee -a $LOG_DEBUG_FILE
            mv $CONFIG_PATH "$LAST_RUN_FOLDER""$LAST_RUN_PROFILE"
        fi
    else
        echo "${RUNNING_PROFILE_FILE} is not exist!"  | tee -a $LOG_DEBUG_FILE
    fi

    if [[ -d "${CONFIG_PATH}" ]] ; then
	    echo "Move $CONFIG_PATH to $LAST_RUN_FOLDER..........." | tee -a $LOG_DEBUG_FILE
	    mv $CONFIG_PATH "${LAST_RUN_FOLDER}/config_snapshot_$(date +%Y%m%d_%H%M%S)"
    fi
#####
    if [[ $CONFIG_TYPE == "NM" ]]; then
	    delete_stale_connections
    fi
    
    echo "Moving ${PROFILE_FOLDER} setting to ${CONFIG_PATH}"  | tee -a $LOG_DEBUG_FILE
    mv -b $PROFILE_FOLDER $CONFIG_PATH
    reload_service $DAEMON_TYPE
fi

echo "Sleep 5 seconds............" | tee -a $LOG_DEBUG_FILE
sleep 5

# Verify the active NICs under bonding
for nic in "${ACTIVE_NIC_LIST[@]}"; do
    if check_config "$nic"; then
        echo "$nic belongs to the bonding!"  | tee -a $LOG_DEBUG_FILE
    else
        echo "[WARMING!!!] $nic NOT belongs to bonding! "  | tee -a $LOG_DEBUG_FILE
    fi
done

# Verify the standby NICs under bonding
for nic in "${STANDBY_NIC_LIST[@]}"; do
    if check_config "$nic"; then
        echo "$nic belongs to the bonding!"  | tee -a $LOG_DEBUG_FILE
    else
        echo "[WARMING!!!] $nic NOT belongs to bonding! "  | tee -a $LOG_DEBUG_FILE
    fi
done

#if [[ $2 == "backup" ]]; then
    ##### Add on 28-Jul-2025, rename the env_last_run_profile
#    echo "Move and rename ${RUNNING_PROFILE_FILE} to ${LAST_RUN_FOLDER}env_last_run_profile_${LAST_RUN_SUFFIX}" | tee -a $LOG_DEBUG_FILE
#    mv $RUNNING_PROFILE_FILE "${LAST_RUN_FOLDER}env_last_run_profile_${LAST_RUN_SUFFIX}"
#else 
    echo "Write ${PROFILE_NAME} to ${RUNNING_PROFILE_FILE}" | tee -a $LOG_DEBUG_FILE
    echo "export LAST_RUN_PROFILE=${PROFILE_NAME}" | tee $RUNNING_PROFILE_FILE | tee -a $LOG_DEBUG_FILE
#fi

echo "==============================Exit script $(date)===============================" | tee -a $LOG_DEBUG_FILE
