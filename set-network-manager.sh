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

LOG_DEBUG_FILE="${LOG_PATH}set-network-manager.running.log"
echo "========================Start running script $(date)========================" | tee -a $LOG_DEBUG_FILE
#####

NM_CONFIG_PATH="/etc/NetworkManager/system-connections/"
NM_NEW_CONFIG_PATH="/root/otpc_net_${SERVER}/new_config/"

# OFFLINE MODE VARS
NM_CONFIG_PREFIX=$1

# COMMON VARS
NM_SOURCE="ProfileAA/"
NM_CONFIG1="ProfileBA/"
NM_CONFIG2="ProfileBB/"

NM_BOND_LIST=()
NM_BOND_NIC=()
NM_SRC_ACTIVE_NIC=""
NM_SRC_STANDBY_NIC=""
NM_CONFIG_ACTIVE_NIC=""
NM_CONFIG_STANDBY_NIC=""
MODE=""                                                 # New add on 22-Jul-2025 for online/offline mode
UP_NIC_LIST=""                                          # New add on 22-Jul-2025 for check_nic_status of offline mode
LAST_RUN_FOLDER="${NM_NEW_CONFIG_PATH}last_run/"        # New add on 25-Jul-2025 for new generated profile comparison
DIFF_FILE="${LOG_PATH}diff.log"

# Global var for create env_profile_file Only
declare -a NM_SRC_STANDBY_NIC_LIST
declare -a NM_SRC_ACTIVE_NIC_LIST
declare -a NM_CONFIG_ACTIVE_NIC_LIST
declare -a NM_CONFIG_STANDBY_NIC_LIST
declare -a NEW_ASSIGNED_NICS                            # New add on 1-Aug-2025


get_bond_list() {
    local config_path="$1"
    local bond_array=()

    while read -r filepath; do
        file=$(echo "$filepath" | sed 's|.*/||')                # remove path
        bond_name=${file%.nmconnection}                         # remove prefix
        bond_array+=("$bond_name")
    done < <(grep -il "type=bond" "$config_path"/bond*.nmconnection 2> /dev/null)

# Optional: return array as space-separated string
    echo "${bond_array[@]}"
}

#get_bond_nic_list() {
    #local config_path="$1"
    #local ethernet_array=()
    #local bond=$2

    #while read -r filepath; do
    #    file=$(echo "$filepath" | sed 's|.*/||')                # remove path
    #    ethernet_name=${file%.nmconnection}                     # remove file extension name
    #    ethernet_array+=("$ethernet_name")
    ##### Change on 24-Jul-2025, using controller=$bond instead of master=$bond
    #done < <(grep -il "type=ethernet" "$config_path"/*.nmconnection | xargs grep -il controller=$bond 2> /dev/null)  
    #####
    #echo "${ethernet_array[@]}"

#}

get_bond_nic_list() {
    local bond="$1"
    local -n result_array=$2  # Use nameref to return array

    result_array=()

    if [[ $MODE == "online" ]]; then
        if [[ -f "/proc/net/bonding/${bond}" ]]; then
            mapfile -t result_array < <(grep "^Slave Interface:" "/proc/net/bonding/${bond}" | awk -F': ' '{print $2}')
        fi
    elif [[ $MODE == "offline" ]]; then
        if [[ -f "$UP_NIC_LIST" ]]; then
            mapfile -t result_array < <(grep "master ${bond}" "$UP_NIC_LIST" | awk -F': ' '{print $2}' | awk '{print $1}' | sort -u)
        fi
    fi
}

get_active_nic_from_bond() {
    local bond_config_file="$1"
    local nic="$2"
    local active_nic="none"
    
        if grep -il "primary=$nic" "$bond_config_file" 2> /dev/null ; then	
	    active_nic="$nic"
        fi

    echo "$active_nic"
}

##### New add on 22-July-2025,
# if nic in used return true.
check_nic_status()
{
    local nic=$1
    local anic=""

    if [[ $MODE == "online" ]]; then
        ######Add on 1-Aug-2025
        for anic in "${NEW_ASSIGNED_NICS[@]}" ; do
        {
            if [[ $anic == $nic ]]; then 
                echo "CHECK_NIC_STATUS() MODE=ONLINE RETURN : TRUE (${nic} New Assigned)"| tee -a $LOG_DEBUG_FILE
                return 0
            fi
        } done
        #####
        if ip address show $nic | grep -iq "master bond*" ; then
            echo "CHECK_NIC_STATUS() MODE=ONLINE RETURN : TRUE (${nic} Occupied)" | tee -a $LOG_DEBUG_FILE
            return 0
        else
            echo "CHECK_NIC_STATUS() MODE=ONLINE RETURN : FALSE (${nic} Available)"| tee -a $LOG_DEBUG_FILE
            return 1
        fi

    elif [[ $MODE == "offline" ]]; then
        ######Add on 1-Aug-2025
        for anic in "${NEW_ASSIGNED_NICS[@]}" ; do
        {
            if [[ $anic == $nic ]]; then 
                echo "CHECK_NIC_STATUS() MODE=OFFLINE RETURN : TRUE (${nic} New Assigned)"| tee -a $LOG_DEBUG_FILE
                return 0
            fi
        } done
        ######    
        if grep -i $nic $UP_NIC_LIST ; then
            echo "CHECK_NIC_STATUS() MODE=OFFLINE RETURN : TRUE (${nic} Occupied)" | tee -a $LOG_DEBUG_FILE
            return 0
        else
            echo "CHECK_NIC_STATUS() MODE=OFFLINE RETURN : FALSE (${nic} Available)" | tee -a $LOG_DEBUG_FILE
            return 1
        fi	
        
    else
        echo "CHECK_NIC_STATUS() MODE=UNKNOWN RETURN : FALSE (Available)" | tee -a $LOG_DEBUG_FILE
        return 1
    fi
}
#####

set_new_nic() {
    local nic="$1"
    local new_nic=""

    # Case 1: onboard ethernet start with ens
    if [[ ${nic%%[0-9]*} == "eno" ]]; then
        local num=${nic//[!0-9]/}
        local new_num=$((num + 1))
        local prefix=${nic%%[0-9]*}
        new_nic="${prefix}${new_num}"

    # Case 2: PCI ethernet e.g., ens1f0np0 -> ens1f1np1
    elif [[ $nic =~ ^(.*f)([0-9]+)(np)([0-9]+)$ ]]; then
        local prefix_f="${BASH_REMATCH[1]}"
        local num_f="${BASH_REMATCH[2]}"
        local np="${BASH_REMATCH[3]}"
        local num_np="${BASH_REMATCH[4]}"

        local new_f=$((num_f + 1))
        local new_np=$((num_np + 1))

        new_nic="${prefix_f}${new_f}${np}${new_np}"

    # Case 3: PCI NIC, e.g ens1f0 -> ens1f1
    elif [[ $nic =~ ^(.*f)([0-9]+)$ ]]; then
        local prefix_f="${BASH_REMATCH[1]}"
        local num_f="${BASH_REMATCH[2]}"
        
        local new_f=$((num_f + 1))
        new_nic="${prefix_f}${new_f}"

    # Case 4: Test ENV VM NIC on Linux e.g. ens192 -> ens 161; ens224 -> ens256
    elif [[ ${nic%%[0-9]*} == "ens" ]]; then
        if [[ $nic == "ens192" ]]; then
            new_nic="ens161"
        elif [[ $nic == "ens224" ]]; then
            new_nic="ens256"
        fi
    fi

    echo "$new_nic"
}

set_nm_eth_file() {
	local old_nic=$1
	local new_nic=$2
	local old_cfg_file="$3""$1.nmconnection"
	local new_cfg_file="$3""$2.nmconnection"
	local old_nic_uuid=$(grep -i "^uuid=" $old_cfg_file)

	# if new_nic.nmconnection exist, swap the old new cfg. Otherwise, just change the existing config file for new nic.
	if [ -f $new_cfg_file ]; then
		local new_nic_uuid==$(grep -i "^uuid=" $new_cfg_file)

	        # rename the ensX.nmconnection file
        	mv $old_cfg_file $old_cfg_file".bak"
	        mv $new_cfg_file $old_cfg_file
        	mv $old_cfg_file".bak" $new_cfg_file

	        #Change the old_cfg_file content
        	sed -i "s/$new_nic/$old_nic/g" $old_cfg_file
	        sed -i "s/$new_nic_uuid/$old_nic_uuid/" $old_cfg_file

	else

	    	local new_nic_uuid="uuid=$(uuidgen $2)"
		mv $old_cfg_file $new_cfg_file
	fi


	#Change the new_cfg_file content
	sed -i "s/$old_nic/$new_nic/g" $new_cfg_file
	sed -i "s/$old_nic_uuid/$new_nic_uuid/g" $new_cfg_file

}

set_nm_bond_file() {
	local bond=$1
        local src_nic=$2
	local new_nic=$3
        local bond_file="$4""$1.nmconnection"
	
        sed -i "s/$src_nic/$new_nic/g" $bond_file
}

set_config_permission() {
        local filepath=$1
        chcon -Ru system_u -r object_r -t NetworkManager_etc_t $filepath
}

set_env_file() {
	local env_filepath=$1
    {
        echo "export ACTIVE_NIC_LIST=(${NM_CONFIG_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NM_CONFIG_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileBB_file"

    {
        echo "export ACTIVE_NIC_LIST=(${NM_SRC_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NM_SRC_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileAA_file"

    {
        echo "export ACTIVE_NIC_LIST=(${NM_CONFIG_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NM_SRC_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileBA_file"

}

leave_copy(){
    local copy_path="${LOG_PATH}leave_copy_$(date +%Y%m%d_%H%M%S)/"
    mkdir -p $copy_path

    echo "Create tar backup ${NM_CONFIG_PATH} ========="
    tar cvf "${copy_path}system-connections.tar" $NM_CONFIG_PATH

    echo "Copy Profile Folder to ${copy_path}" | tee -a $LOG_DEDUG_FILE
    cp -R $NM_NEW_CONFIG_PATH/* $copy_path | tee -a $LOG_DEDUG_FILE
    echo "chown $USER -R $LOG_PATH" | tee -a $LOG_DEDUG_FILE
    chown $USER -R $LOG_PATH | tee -a $LOG_DEDUG_FILE
    echo "chmod 755 -R $LOG_PATH" | tee -a $LOG_DEDUG_FILE
    chmod 755 -R $LOG_PATH | tee -a $LOG_DEDUG_FILE
}

diff_last_run() {
    local profile="Profile$1"
    local config_files=$(find "$NM_NEW_CONFIG_PATH/$profile" -type f)

    for filepath in $config_files; do
        file=$(basename "$filepath")
        echo "diff ${NM_NEW_CONFIG_PATH}/${profile}/${file} ${LAST_RUN_FOLDER}/${profile}/${file}" | tee -a "$DIFF_FILE" "$LOG_DEBUG_FILE"
        diff "${NM_NEW_CONFIG_PATH}/${profile}/${file}" "${LAST_RUN_FOLDER}/${profile}/${file}" | tee -a "$DIFF_FILE" "$LOG_DEBUG_FILE"
    done
}

##### Determine ONLINE/OFFLINE Mode. Modify date 22-Jul-2025
if [[ ! -z "$1" ]]; then
    if [[ -d "$1" ]]; then
	
        NM_NEW_CONFIG_PATH="$NM_CONFIG_PREFIX""new_config/"
        echo "Mode=OFFLINE LOG Path change to ${NM_CONFIG_PREFIX}set-network-script.running.log" | tee -a $LOG_DEBUG_FILE
        LOG_DEBUG_FILE="${NM_CONFIG_PREFIX}set-network-manager.running.log"
        echo "Log Path changed $(date)=============================================" | tee -a $LOG_DEBUG_FILE        

        LAST_RUN_FOLDER="${NM_NEW_CONFIG_PATH}last_run/" 
        NM_CONFIG_PATH="$(dirname `find $NM_CONFIG_PREFIX -name "bond0.nmconnection"`)/"
        NM_LOG_FILE=`find ${NM_CONFIG_PREFIX} -name network_info_*.log`

        MODE="offline"
        echo "Script execute in OFFLINE mode!" | tee -a $LOG_DEBUG_FILE
        echo "Config File Path : ${NM_CONFIG_PATH}" | tee -a $LOG_DEBUG_FILE
        echo "IP ADDRESS LIST FILE : ${NM_LOG_FILE}" | tee -a $LOG_DEBUG_FILE
	
        if grep -i "TYPE=Bond" "${NM_CONFIG_PATH}bond0.nmconnection" ; then
        
            if [[ ! -n "$NM_LOG_FILE" ]]; then
                echo "No ip addr list file for verifying" MODE="offline" | tee -a $LOG_DEBUG_FILE
                exit 1
            fi
        
            # Global variable for function call.
            UP_NIC_LIST="${NM_CONFIG_PREFIX}up_nic.txt"

            grep -i "master bond" $NM_LOG_FILE > $UP_NIC_LIST;
            echo "List out in used physical bond nic!" | tee -a $LOG_DEBUG_FILE
            cat $UP_NIC_LIST | tee -a $LOG_DEBUG_FILE
            echo "<< End of List >>" | tee -a $LOG_DEBUG_FILE

        else 
            echo "No bonding configure file under this directory!" | tee -a $LOG_DEBUG_FILE
            exit 1
        fi
    else
        echo "$1 isn't exist!" | tee -a $LOG_DEBUG_FILE
        exit 1
    fi
else
        MODE="online"
        echo "Script execute in ONLINE mode!" | tee -a $LOG_DEBUG_FILE
        echo "Config File Path : ${NM_CONFIG_PATH}" | tee -a $LOG_DEBUG_FILE
fi

#####

# Create NM_Profile
if [[ ! -d "$NM_NEW_CONFIG_PATH" ]]; then
    mkdir -p "$NM_NEW_CONFIG_PATH"
elif [[ -d "${NM_NEW_CONFIG_PATH}/ProfileBA" || -d "${NM_NEW_CONFIG_PATH}/ProfileBB" || -d "${NM_NEW_CONFIG_PATH}/ProfileAA" ]]; then
    echo "The Profile(s) folder exists! Please clean up the folder to avoid overwrite actions." | tee -a $LOG_DEBUG_FILE
    exit 1
fi

APPROACH_AA_PATH="$NM_NEW_CONFIG_PATH""$NM_SOURCE"
echo "Copying ${NM_CONFIG_PATH} to ${APPROACH_AA_PATH}........" | tee -a $LOG_DEBUG_FILE
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_AA_PATH"

APPROACH_BA_PATH="$NM_NEW_CONFIG_PATH""$NM_CONFIG1"
echo "Copying ${NM_CONFIG_PATH} to ${APPROACH_BA_PATH}........" | tee -a $LOG_DEBUG_FILE
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_BA_PATH"

APPROACH_BB_PATH="$NM_NEW_CONFIG_PATH""$NM_CONFIG2"
echo "Copying ${NM_CONFIG_PATH} to ${APPROACH_BB_PATH}........" | tee -a $LOG_DEBUG_FILE
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_BB_PATH"

# Get Bond List
MAIN_COPY_PATH=$APPROACH_AA_PATH

read -r -a  NM_BOND_LIST <<< "$(get_bond_list $MAIN_COPY_PATH)"
echo "# of BOND : ${#NM_BOND_LIST[@]}" | tee -a $LOG_DEBUG_FILE        # Debug use

# Create Approach BB NM_Profile
for bond in "${NM_BOND_LIST[@]}"; do
    #read -r -a  NM_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
    get_bond_nic_list $bond NM_BOND_NIC
    echo "===========================================================================" | tee -a $LOG_DEBUG_FILE
	echo "Approach BB-BOND: $bond" | tee -a $LOG_DEBUG_FILE                               # Debug use
    echo "# of NIC : ${#NM_BOND_NIC[@]}" | tee -a $LOG_DEBUG_FILE                           # Debug use
    	
    for nic in "${NM_BOND_NIC[@]}"; do
        echo "${nic} belongs to ${bond}" | tee -a $LOG_DEBUG_FILE
        if grep -i "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection" ; then
        #if grep -iq "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection" 2> /dev/null ; then
         #   echo "GREP -i primary ${nic}$ in {bond}.nmconnection"
			NM_SRC_ACTIVE_NIC=$nic
			NM_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

            # add at 22-July-2025
            while check_nic_status $NM_CONFIG_ACTIVE_NIC ; do
                    NM_CONFIG_ACTIVE_NIC="$(set_new_nic $NM_CONFIG_ACTIVE_NIC)"
            # echo "in loop : ${NM_CONFIG_ACTIVE_NIC}"              # debug use
            done
            #####
            NEW_ASSIGNED_NICS+=("$NM_CONFIG_ACTIVE_NIC")

			set_nm_eth_file $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			set_nm_bond_file $bond $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			
			echo "Active NIC : $nic" | tee -a $LOG_DEBUG_FILE                               # debug use
			echo "New Active NIC : $NM_CONFIG_ACTIVE_NIC" | tee -a $LOG_DEBUG_FILE          # debug use

			NM_CONFIG_ACTIVE_NIC_LIST+=("$NM_CONFIG_ACTIVE_NIC")
			NM_SRC_ACTIVE_NIC_LIST+=("$nic")
		else	
			NM_SRC_STANDBY_NIC=$nic
			NM_CONFIG_STANDBY_NIC="$(set_new_nic $nic)"

            # add at 22-July-2025
            while check_nic_status $NM_CONFIG_STANDBY_NIC ; do
                    NM_CONFIG_STANDBY_NIC="$(set_new_nic $NM_CONFIG_STANDBY_NIC)"
            # echo "in loop : ${NM_CONFIG_ACTIVE_NIC}"              # debug use
            done
            #####
            NEW_ASSIGNED_NICS+=("$NM_CONFIG_STANDBY_NIC")

			set_nm_eth_file $NM_SRC_STANDBY_NIC $NM_CONFIG_STANDBY_NIC $APPROACH_BB_PATH
			
			echo "Standby NIC : $nic" | tee -a $LOG_DEBUG_FILE                             # debug use
			echo "New Standby NIC : $NM_CONFIG_STANDBY_NIC" | tee -a $LOG_DEBUG_FILE       # debug use    

			NM_CONFIG_STANDBY_NIC_LIST+=("$NM_CONFIG_STANDBY_NIC")
			NM_SRC_STANDBY_NIC_LIST+=("$nic")
		fi

	done


done

##### Add on 1-Aug-2025, unset the array for new_nic_status() 
NEW_ASSIGNED_NICS=()

# create profile env file
set_env_file $NM_NEW_CONFIG_PATH 

# Create Approach BA NM_Profile
for bond in "${NM_BOND_LIST[@]}"; do
        #read -r -a  NM_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
        get_bond_nic_list $bond NM_BOND_NIC
        echo "===========================================================================" | tee -a $LOG_DEBUG_FILE
        echo "Approach BA-BOND: $bond" | tee -a $LOG_DEBUG_FILE
        echo "# of NIC : ${#NM_BOND_NIC[@]}" | tee -a $LOG_DEBUG_FILE
	    
        for nic in "${NM_BOND_NIC[@]}"; do
                if grep -i "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection"; then
                #if grep -i "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection" 2> /dev/null ; then
                        NM_SRC_ACTIVE_NIC=$nic
                        NM_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

                        ##### add at 22-July-2025
                        while check_nic_status $NM_CONFIG_ACTIVE_NIC ; do
                            NM_CONFIG_ACTIVE_NIC="$(set_new_nic $NM_CONFIG_ACTIVE_NIC)"
                            # echo "in loop : ${NM_CONFIG_ACTIVE_NIC}"              # debug use
                        done
                        #####
                        NEW_ASSIGNED_NICS+=("$NM_CONFIG_ACTIVE_NIC")

                        set_nm_eth_file $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH
                        set_nm_bond_file $bond $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH

                        echo "Active NIC : $nic" | tee -a $LOG_DEBUG_FILE                                  # debug use
                        echo "New Active NIC : $NM_CONFIG_ACTIVE_NIC" | tee -a $LOG_DEBUG_FILE            # debug use
                fi
        done
done

if [[ $MODE == "online" ]]; then
    echo "===========================================================================" | tee -a $LOG_DEBUG_FILE
    set_config_permission $APPROACH_AA_PATH
    set_config_permission $APPROACH_BB_PATH
    set_config_permission $APPROACH_BA_PATH
    
    leave_copy
        if [[ -d "${LAST_RUN_FOLDER}ProfileAA" ]]; then
            echo "${LAST_RUN_FOLDER}ProfileAA exist, start comparing the config file!" | tee -a $LOG_DEBUG_FILE
            diff_last_run AA
        fi
        if [[ -d "${LAST_RUN_FOLDER}ProfileBA" ]]; then
            echo "${LAST_RUN_FOLDER}ProfileBA exist, start comparing the config file!" | tee -a $LOG_DEBUG_FILE
            diff_last_run BA
        fi
        if [[ -d "${LAST_RUN_FOLDER}ProfileBB" ]]; then
            echo "${LAST_RUN_FOLDER}ProfileBB exist, start comparing the config file!" | tee -a $LOG_DEBUG_FILE
            diff_last_run BB 
        fi
fi

echo "==============================Exit script $(date)===============================" | tee -a $LOG_DEBUG_FILE