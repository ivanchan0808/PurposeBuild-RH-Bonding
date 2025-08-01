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
PROFILES_PATH="/root/otpc_net_${SERVER}/new_config/"           #The path store all the profiles

						    	            
LOG_PATH="/home/${USER}/otpc_log_${SERVER}/"

if [ ! -d "/home/${USER}" ]; then
    LOG_PATH="/tmp/otpc_log_${SERVER}/"
    echo "${USER} is not exit!"
    echo " LOG PATH change to ${LOG_PATH}!"
    USER=`whoami`
fi  

RECYCLE_BIN="${LOG_PATH}RECYCLE_BIN/$(date +%Y%m%d_%H%M%S)/"

if [ ! -d "$RECYCLE_BIN" ]; then
    echo "Creating log folder - $RECYCLE_BIN"
    mkdir -p $RECYCLE_BIN
fi




LOG_DEBUG_FILE="${LOG_PATH}cleanup.running.log"
echo "========================Start running script $(date)========================" | tee -a $LOG_DEBUG_FILE
#####

move_file_to_recycle_bin(){
    local item="${PROFILES_PATH}$1"
    
    if [[ -f "$item" ]]; then
        echo "File : $item exist. Move to ${RECYCLE_BIN} " | tee -a $LOG_DEBUG_FILE
        mv  $item "${RECYCLE_BIN}"
    fi
}

move_folder_to_recycle_bin(){
    local item="${PROFILES_PATH}$1"

    if [[ $1 == "all" ]]; then
        item="/root/otpc_net_${SERVER}/"
        if [[ -d "$item" ]]; then
            echo "Move ${item} to ${RECYCLE_BIN}" | tee -a $LOG_DEBUG_FILE
            mv $item "${RECYCLE_BIN}/otpc_net_${SERVER}"
        fi
        echo "Move log files to ${RECYCLE_BIN}" | tee -a $LOG_DEBUG_FILE
        mv "${LOG_PATH}"*".log" $RECYCLE_BIN
        mv "${LOG_PATH}"*".txt" $RECYCLE_BIN
        echo "Move leave_copies to ${RECYCLE_BIN}" | tee -a $LOG_DEBUG_FILE
        mv "${LOG_PATH}leave_copy_"* $RECYCLE_BIN
    elif [[ -d "$item" ]]; then
        echo "Folder : $item exist. Move to ${RECYCLE_BIN} " | tee -a $LOG_DEBUG_FILE
        mv  $item "${RECYCLE_BIN}${1}"
    fi
}


    ##### Add on 1-Aug-2025, housekeep
if [[ ! -z $1 ]]; then
    if [[ $1 != "all" ]]; then
        echo "Invalid option! "  tee -a $LOG_DEBUG_FILE
        exit 1
    fi
    if [[ $1 == "all" ]]; then
        move_folder_to_recycle_bin all
    fi
else
    move_file_to_recycle_bin env_last_run_profile
    move_file_to_recycle_bin env_ProfileAA_file
    move_file_to_recycle_bin env_ProfileBB_file
    move_file_to_recycle_bin env_ProfileBA_file
    move_folder_to_recycle_bin ProfileAA
    move_folder_to_recycle_bin ProfileBB
    move_folder_to_recycle_bin ProfileBA
fi