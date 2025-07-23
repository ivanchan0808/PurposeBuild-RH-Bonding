#!/bin/bash
PROFILES_PATH=$1							#The path store all the profiles
PROFILE_NAME="Profile$2"						#Approach AA BA BB
PROFILE_FOLDER="$PROFILES_PATH""/$PROFILE_NAME"
VERSION=`awk '{print $6}' /etc/redhat-release`
CONFIG_TYPE=""
CONFIG_PATH=""
DAEMON_TYPE=""
NS_CONFIG_PATH="/etc/sysconfig/network-scripts/"
NM_CONFIG_PATH="/etc/NetworkManager/system-connections/"
BACKUP_FOLDER="$PROFILES_PATH""backup_$(date +%Y%m%d_%H%M%S)"

if [ "$2" == "backup" ]; then
        PROFILE_NAME="ProfileAA"
fi

source $PROFILES_PATH/env_"$PROFILE_NAME"_file

echo "Imported Active NICs record : ${ACTIVE_NIC_LIST[@]}"
echo "Imported Standby NICs record : ${STANDBY_NIC_LIST[@]}"

echo $VERSION

reload_service() {
	local service=$1
	
	if [[ $service == "Network" ]]; then
		systemctl restart network
	elif [[ $service == "NetworkManager" ]]; then
		nmcli connection reload
		systemctl restart NetworkManager
	fi
}

##### New added at 23-July for handling RHEL9 behavior-auto create Wired connection when the NICs are connected.
delete_stale_connections() {
    # Get all "Wired connection" names
    nmcli -t -f NAME connection show | grep -E '^Wired connection' | while IFS= read -r conn; do
        echo "Deleting connection: $conn"
        nmcli connection delete "$conn"
    done

    for nic in "${ACTIVE_NIC_LIST[@]}"; do
        nmcli connection delete $nic
    done

    for nic in "${STANDBY_NIC_LIST[@]}"; do
        nmcli connection delete $nic
    done
}
#####

check_config() {
    local eth=$1
    if ip address show "$eth" | grep -iq "master bond*" ; then
        return 0    # true
    else
        return 1    # false
    fi
}

if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 <Profiles Path> <Profile Name>"
    exit 1
fi

if (( $(echo "$VERSION >= 9" | bc -l) )); then
    	CONFIG_TYPE="NM"
	CONFIG_PATH=$NM_CONFIG_PATH
	DAEMON_TYPE="NetworkManager"

	echo "Service : Network Manager"
elif (( $(echo "$VERSION >= 8" | bc -l) )); then
	CONFIG_TYPE="NS"
	CONFIG_PATH=$NS_CONFIG_PATH
	DAEMON_TYPE="NetworkManager"
    	
	echo "Service : Network Manager by ifcfg"
elif (( $(echo "$VERSION >= 7" | bc -l) )); then
	CONFIG_TYPE="NS"
	CONFIG_PATH=$NS_CONFIG_PATH
	DAEMON_TYPE="Network"
	echo "Service : Networking"
else 
	echo "Unable to Identify the OS Version!"
fi

if [[ $2 == "backup" ]] ; then
	PROFILE_FOLDER=$1"backup"
fi

if [ ! -d "${PROFILES_PATH}/backup/" ] ; then
	echo "Backup $CONFIG_PATH to $PROFILE_PATH..........."
	mv $CONFIG_PATH "${PROFILES_PATH}/backup"
fi

if [ ! -d $PROFILE_FOLDER ] ; then
	echo "The profile folder is not exist! The profile may be applied! "
	exit 1
fi


if [ ! -d $CONFIG_PATH ] ; then
    if [ $CONFIG_TYPE == "NM" ]; then
	    delete_stale_connections
    fi
	mv -b $PROFILE_FOLDER $CONFIG_PATH
	reload_service $DAEMON_TYPE
else 
    if [ $CONFIG_TYPE == "NM" ]; then
	    delete_stale_connections
    fi
	mv $CONFIG_PATH $BACKUP_FOLDER
    mv -b $PROFILE_FOLDER $CONFIG_PATH
    reload_service $DAEMON_TYPE
fi

sleep 5

# Verify the active NICs under bonding
for nic in "${ACTIVE_NIC_LIST[@]}"; do
    if check_config "$nic"; then
        echo "$nic is under the bonding!"
    else
        echo "$nic is NOT a bonding member!"
    fi
done

# Verify the standby NICs under bonding
for nic in "${STANDBY_NIC_LIST[@]}"; do
    if check_config "$nic"; then
        echo "$nic is under the bonding!"
    else
        echo "$nic is NOT a bonding member!"
    fi
done
