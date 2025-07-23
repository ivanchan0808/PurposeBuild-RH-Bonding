#!/bin/bash

# ONLINE MODE VARS
SERVER=`hostname`
NM_CONFIG_PATH="/etc/NetworkManager/system-connections/"
NM_NEW_CONFIG_PATH="/root/$SERVER/new_config/"

# OFFLINE MODE VARS
NM_CONFIG_PREFIX=$1
NM_CONFIG_SUFFIX="tmp/network_backup_20250712_091735/network-scripts/network-scripts/"

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

# Global var for create env_profile_file Only
declare -a NM_SRC_STANDBY_NIC_LIST
declare -a NM_SRC_ACTIVE_NIC_LIST
declare -a NM_CONFIG_ACTIVE_NIC_LIST
declare -a NM_CONFIG_STANDBY_NIC_LIST
declare -a MODE                                                 #New add at 22-Jul-2025 for online/offline mode
declare -a UP_NIC_LIST                                          #New add at 22-Jul-2025 for check_nic_status of offline mode

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

get_bond_nic_list() {
    local config_path="$1"
    local ethernet_array=()
    local bond=$2

    while read -r filepath; do
        file=$(echo "$filepath" | sed 's|.*/||')                # remove path
        ethernet_name=${file%.nmconnection}                     # remove prefix
        ethernet_array+=("$ethernet_name")
    done < <(grep -il "type=ethernet" "$config_path"/*.nmconnection | xargs grep -il master=$bond 2> /dev/null)

    echo "${ethernet_array[@]}"
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

##### New add at 22-July-2025,
# if nic in used return true.
check_nic_status()
{
    local nic=$1

    if [[ $MODE == "online" ]]; then
        if ip address show $nic | grep -iq "master bond*" ; then
            return 0
        else
            return 1
        fi

    elif [[ $MODE == "offline" ]]; then
        if grep -i $nic $UP_NIC_LIST ; then
            return 0
        else
            return 1
        fi	
        
    else
            return 1
    fi
}
#####

set_new_nic() {
    local nic="$1"
    local new_nic=""

    # Case 1: onboard ethernet start with ens
    if [[ $nic =~ ^(.*f)([0-9]+)$ ]]; then
        local prefix_f="${BASH_REMATCH[1]}"
        local num_f="${BASH_REMATCH[2]}"
        local new_f=$((num_f + 1))

        new_nic="${prefix_f}${new_f}"

    # Case 2: PCI ethernet e.g., ens1f0np0 -> ens1f1np1
    elif [[ $nic =~ ^(.*f)([0-9]+)(np)([0-9]+)$ ]]; then
        local prefix_f="${BASH_REMATCH[1]}"
        local num_f="${BASH_REMATCH[2]}"
        local np="${BASH_REMATCH[3]}"
        local num_np="${BASH_REMATCH[4]}"

        local new_f=$((num_f + 1))
        local new_np=$((num_np + 1))

        new_nic="${prefix_f}${new_f}${np}${new_np}"

    # Case 3: Test ENV VM NIC on Linux e.g. ens192 -> ens 161; ens224 -> ens256
    elif [[ ${nic%%[0-9]*} == "ens" ]]; then
        echo "in loop $nic" >> debug.txt
        if [[ $nic == "ens192" ]]; then
            new_nic="ens161"
            echo "$new_nic" >> debug.txt
        elif [[ $nic == "ens224" ]]; then
            new_nic="ens256"
            echo "$new_nic" >> debug.txt
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

##### Determine ONLINE/OFFLINE Mode. Modify date 22-Jul-2025
if [ ! -z "$1" ]; then
    if [ -d "$1" ]; then
	NM_CONFIG_PATH="$NM_CONFIG_PREFIX""$NM_CONFIG_SUFFIX"
        NM_NEW_CONFIG_PATH="$NM_CONFIG_PREFIX""new_config/"

	if grep -iq "TYPE=Bond" "$NM_CONFIG_PATH""ifcfg-bond"* 2>/dev/null; then
            if [ -z "$2" ]; then
                echo "No ip addr list file for verifying"
                exit 1
            fi
            
            # Global variable for function call.
            MODE="offline"                              
            echo "Script execute in OFFLINE mode!"
            echo "Config File Path : ${NM_CONFIG_PATH}"
	    
	    UP_NIC_LIST="${NM_CONFIG_PREFIX}/up_nic.txt"
 	    grep -i "master bond" $2 > $UP_NIC_LIST
	    cat $UP_NIC_LIST

        else 
            echo "No bonding configure file under this directory!"
            exit 1
        fi
    else
        echo "$1 isn't exist!"
        exit 1
    fi
else
        echo "Script execute in ONLINE mode!"
        echo "Config File Path : ${NM_CONFIG_PATH}"
        MODE="online"
fi
#####

# Create NM_Profile
if [ ! -d "$NM_NEW_CONFIG_PATH" ]; then
    mkdir -p "$NM_NEW_CONFIG_PATH"
else 
    echo "The folder exists! Please clean up the folder to avoid overwrite actions."
    exit 1
fi

APPROACH_AA_PATH="$NM_NEW_CONFIG_PATH""$NM_SOURCE"
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_AA_PATH"

APPROACH_BA_PATH="$NM_NEW_CONFIG_PATH""$NM_CONFIG1"
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_BA_PATH"

APPROACH_BB_PATH="$NM_NEW_CONFIG_PATH""$NM_CONFIG2"
cp -Rp "$NM_CONFIG_PATH" "$APPROACH_BB_PATH"

# Get Bond List
MAIN_COPY_PATH=$APPROACH_AA_PATH

read -r -a  NM_BOND_LIST <<< "$(get_bond_list $MAIN_COPY_PATH)"
#echo "# of BOND : ${#NM_BOND_LIST[@]}"                             # Debug use

# Create Approach BB NM_Profile
for bond in "${NM_BOND_LIST[@]}"; do
    	read -r -a  NM_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
	#echo "# of NIC : ${#NM_BOND_NIC[@]}"                           # Debug use
	#echo " Approach BB-BOND: $bond"                                # Debug use
    	for nic in "${NM_BOND_NIC[@]}"; do
			
		if grep -q "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection" 2> /dev/null ; then
			NM_SRC_ACTIVE_NIC=$nic
			NM_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

            # add at 22-July-2025
            while check_nic_status $NM_CONFIG_ACTIVE_NIC ; do
                    NM_CONFIG_ACTIVE_NIC="$(set_new_nic $NM_CONFIG_ACTIVE_NIC)"
            # echo "in loop : ${NM_CONFIG_ACTIVE_NIC}"              # debug use
            done
            #####

			set_nm_eth_file $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			set_nm_bond_file $bond $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			
			#echo "Active NIC : $nic"                               # debug use
			#echo "New Active NIC : $NM_CONFIG_ACTIVE_NIC"          # debug use

			NM_CONFIG_ACTIVE_NIC_LIST+=("$NM_CONFIG_ACTIVE_NIC")
			NM_SRC_ACTIVE_NIC_LIST+=("$nic")
		else	
			NM_SRC_STANDBY_NIC=$nic
			NM_CONFIG_STANDBY_NIC="$(set_new_nic $nic)"

			set_nm_eth_file $NM_SRC_STANDBY_NIC $NM_CONFIG_STANDBY_NIC $APPROACH_BB_PATH
			
			#echo "Standby NIC : $nic"                              # debug use
			#echo "New Standby NIC : $NM_CONFIG_STANDBY_NIC"        # debug use    

			NM_CONFIG_STANDBY_NIC_LIST+=("$NM_CONFIG_STANDBY_NIC")
			NM_SRC_STANDBY_NIC_LIST+=("$nic")
		fi

	done


done

# create profile env file
set_env_file $NM_NEW_CONFIG_PATH 

# Create Approach BA NM_Profile
for bond in "${NM_BOND_LIST[@]}"; do
        read -r -a  NM_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
        #echo "# of NIC : ${#NM_BOND_NIC[@]}"
	    #echo "Approach BA-BOND: $bond"

        for nic in "${NM_BOND_NIC[@]}"; do

                if grep -q "primary=$nic" "$NM_CONFIG_PATH""$bond"".nmconnection" 2> /dev/null ; then
                        NM_SRC_ACTIVE_NIC=$nic
                        NM_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

                        ##### add at 22-July-2025
                        while check_nic_status $NM_CONFIG_ACTIVE_NIC ; do
                            NM_CONFIG_ACTIVE_NIC="$(set_new_nic $NM_CONFIG_ACTIVE_NIC)"
                            # echo "in loop : ${NM_CONFIG_ACTIVE_NIC}"              # debug use
                        done
                        #####

                        set_nm_eth_file $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH
                        set_nm_bond_file $bond $NM_SRC_ACTIVE_NIC $NM_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH

                        #echo "Active NIC : $nic"                                   # debug use
                        #echo "New Active NIC : $NM_CONFIG_ACTIVE_NIC"              # debug use
                fi
        done
done

set_config_permission $APPROACH_AA_PATH
set_config_permission $APPROACH_BB_PATH
set_config_permission $APPROACH_BA_PATH