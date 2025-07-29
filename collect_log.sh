#!/bin/bash

VERSION=`awk '{print $6}' /etc/redhat-release`
if (( $(echo "$VERSION >= 8" | bc -l) )); then
    USER="ps_syssupp"
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
    USER="syssupp"
fi

SERVER=`hostname`
LOG_PATH="/home/${USER}/otpc_log_${SERVER}/"
USER_HOME="/home/${USER}/"

if [ ! -d "/home/${USER}" ]; then
    LOG_PATH="/tmp/otpc_log_${SERVER}/"
    echo "${USER} is not exit!"
    echo " LOG PATH change to ${LOG_PATH}!"
    USER=`whoami`
    if [ $USER=="root" ]; then
        USER_HOME=/root/
    fi
fi  

if [ ! -d "$LOG_PATH" ]; then
    echo "Creating log folder - $LOG_PATH"
    mkdir -p $LOG_PATH
fi

if [[ -z "$1" ]]; then
    echo "Usage: $0 <Log File suffix> e.g. $0 $(date +%Y%m%d)_Round1" 
    exit 1
fi

ZIP_DIR="${LOG_PATH%/}_${1}"
ZIP_FILE="${LOG_PATH%/}_${1}.tar.gz"

echo "Rename the Log folder name : ${ZIP_DIR}"
mv $LOG_PATH $ZIP_DIR
echo "ZIP the Log folder : ${ZIP_FILE}"
tar cvzf $ZIP_FILE $ZIP_DIR


chown -R $USER:$USER $ZIP_DIR
chown -R $USER:$USER $ZIP_FILE
