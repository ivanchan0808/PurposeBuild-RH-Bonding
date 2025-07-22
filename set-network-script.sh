#!/bin/bash

SERVER=`hostname`
NS_CONFIG_PATH="/etc/sysconfig/network-scripts/"
#NS_CONFIG_PATH="/root/develop/network-script/$SERVER/tmp/network_backup_20250712_091735/network-scripts/network-scripts/"
NS_NEW_CONFIG_PATH="/root/$SERVER/new_config/"

NS_SOURCE="ProfileAA/"
NS_CONFIG1="ProfileBA/"
NS_CONFIG2="ProfileBB/"

NS_BOND_LIST=()
NS_BOND_NIC=()
NS_SRC_ACTIVE_NIC=""
NS_SRC_STANDBY_NIC=""
NS_CONFIG_ACTIVE_NIC=""
NS_CONFIG_STANDBY_NIC=""

# Global var for create env_profile_file Only
declare -a NS_SRC_STANDBY_NIC_LIST
declare -a NS_SRC_ACTIVE_NIC_LIST
declare -a NS_CONFIG_ACTIVE_NIC_LIST
declare -a NS_CONFIG_STANDBY_NIC_LIST

get_bond_list() {
    local config_path="$1"
    local bond_array=()

    while read -r filepath; do
        file=$(echo "$filepath" | sed 's|.*/||')         # remove path
        bond_name=${file#ifcfg-}                         # remove prefix
        bond_array+=("$bond_name")
    done < <(grep -il "TYPE=Bond" "$config_path"/ifcfg-* 2> /dev/null)

# Optional: return array as space-separated string
    echo "${bond_array[@]}"
}

get_bond_nic_list() {
    local config_path="$1"
    local ethernet_array=()
    local bond=$2

    while read -r filepath; do
        file=$(echo "$filepath" | sed 's|.*/||')         # remove path
        ethernet_name=${file#ifcfg-}                     # remove prefix
        ethernet_array+=("$ethernet_name")
    done < <(grep -il "TYPE=Ethernet" "$config_path"/ifcfg-* | xargs grep -l $bond 2> /dev/null)

    echo "${ethernet_array[@]}"
}

get_active_nic_from_bond() {
    local bond_config_file="$1"
    local nic="$2"
    local active_nic="none"
    
        if grep -l "primary=$nic" "$bond_config_file" 2> /dev/null ; then	
	    active_nic="$nic"
        fi

    echo "$active_nic"
}

set_new_nic() {
    local nic="$1"
    local new_nic=""

    # Case 1: Simple eno-style, e.g., eno1 → eno2
    if [[ ${nic%%[0-9]*} == "eno" ]]; then
        local num=${nic//[!0-9]/}
        local new_num=$((num + 1))
        local prefix=${nic%%[0-9]*}
        new_nic="${prefix}${new_num}"

    # Case 2: Complex pattern, e.g., ens1f0np0 → ens1f1np1
    elif [[ $nic =~ ^(.*f)([0-9]+)(np)([0-9]+)$ ]]; then
        local prefix_f="${BASH_REMATCH[1]}"
        local num_f="${BASH_REMATCH[2]}"
        local np="${BASH_REMATCH[3]}"
        local num_np="${BASH_REMATCH[4]}"

        local new_f=$((num_f + 1))
        local new_np=$((num_np + 1))

        new_nic="${prefix_f}${new_f}${np}${new_np}"
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

set_ifcfg_eth_file() {
	local src_nic=$1
	local new_nic=$2
	local old_cfg_file="$3""ifcfg-$1"
	local new_cfg_file="$3""ifcfg-$2"
	
	#rename the ifcfg-ethX file
	mv $old_cfg_file $new_cfg_file

	#Change the ifcfg-ethX content
	sed -i "s#$src_nic#$new_nic#g" $new_cfg_file
	sed -i "s#^UUID=.*#UUID=$(uuidgen $new_nic)#g" $new_cfg_file
}

set_ifcfg_bond_file() {
	local bond=$1
        local src_nic=$2
	local new_nic=$3
        local bond_file="$4""ifcfg-$1"
	
        sed -i "s#$src_nic#$new_nic#g" $bond_file
}

set_config_permission() {
        local filepath=$1
        chcon -Ru system_u -r object_r -t net_conf_t $filepath
}

set_env_file() {
        local env_filepath=$1
    {
        echo "export ACTIVE_NIC_LIST=(${NS_CONFIG_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NS_CONFIG_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileBB_file"

    {
        echo "export ACTIVE_NIC_LIST=(${NS_SRC_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NS_SRC_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileAA_file"

    {
        echo "export ACTIVE_NIC_LIST=(${NS_CONFIG_ACTIVE_NIC_LIST[@]})"
        echo "export STANDBY_NIC_LIST=(${NS_SRC_STANDBY_NIC_LIST[@]})"
    } > "$env_filepath""env_ProfileBA_file"

}


# Create NS_Profile
if [ ! -d "$NS_NEW_CONFIG_PATH" ]; then
    mkdir -p "$NS_NEW_CONFIG_PATH"
fi

APPROACH_AA_PATH="$NS_NEW_CONFIG_PATH""$NS_SOURCE"
cp -Rp "$NS_CONFIG_PATH" "$APPROACH_AA_PATH"


APPROACH_BA_PATH="$NS_NEW_CONFIG_PATH""$NS_CONFIG1"
cp -Rp "$NS_CONFIG_PATH" "$APPROACH_BA_PATH"


APPROACH_BB_PATH="$NS_NEW_CONFIG_PATH""$NS_CONFIG2"
cp -Rp "$NS_CONFIG_PATH" "$APPROACH_BB_PATH"

# Get Bond List
MAIN_COPY_PATH=$APPROACH_AA_PATH

read -r -a  NS_BOND_LIST <<< "$(get_bond_list $MAIN_COPY_PATH)"
#echo "# of BOND : ${#NS_BOND_LIST[@]}"


# Create Approach BB NS_Profile
for bond in "${NS_BOND_LIST[@]}"; do
    	read -r -a  NS_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
	#echo "# of NIC : ${#NS_BOND_NIC[@]}"
    	for nic in "${NS_BOND_NIC[@]}"; do
	
		if grep -q "primary=$nic" "$NS_CONFIG_PATH""ifcfg-$bond" 2> /dev/null ; then
			NS_SRC_ACTIVE_NIC=$nic
			NS_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

			set_ifcfg_eth_file $NS_SRC_ACTIVE_NIC $NS_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			set_ifcfg_bond_file $bond $NS_SRC_ACTIVE_NIC $NS_CONFIG_ACTIVE_NIC $APPROACH_BB_PATH
			
			echo "Active NIC : $nic"
			echo "New Active NIC : $NS_CONFIG_ACTIVE_NIC"

                        NS_CONFIG_ACTIVE_NIC_LIST+=("$NS_CONFIG_ACTIVE_NIC")
                        NS_SRC_ACTIVE_NIC_LIST+=("$nic")
		else	
			NS_SRC_STANDBY_NIC=$nic
			NS_CONFIG_STANDBY_NIC="$(set_new_nic $nic)"

			set_ifcfg_eth_file $NS_SRC_STANDBY_NIC $NS_CONFIG_STANDBY_NIC $APPROACH_BB_PATH
			
			echo "Standby NIC : $nic"
			echo "New Standby NIC : $NS_CONFIG_STANDBY_NIC"

                        NS_CONFIG_STANDBY_NIC_LIST+=("$NS_CONFIG_STANDBY_NIC")
                        NS_SRC_STANDBY_NIC_LIST+=("$nic")

		fi
	done
done

# create env_profile_file
set_env_file $NS_NEW_CONFIG_PATH

# Create Approach BA NS_Profile
for bond in "${NS_BOND_LIST[@]}"; do
        read -r -a  NS_BOND_NIC <<< "$(get_bond_nic_list $MAIN_COPY_PATH $bond)"
        #echo "# of NIC : ${#NS_BOND_NIC[@]}"
        for nic in "${NS_BOND_NIC[@]}"; do

                if grep -q "primary=$nic" "$NS_CONFIG_PATH""ifcfg-$bond" 2> /dev/null ; then
                        NS_SRC_ACTIVE_NIC=$nic
                        NS_CONFIG_ACTIVE_NIC="$(set_new_nic $nic)"

                        set_ifcfg_eth_file $NS_SRC_ACTIVE_NIC $NS_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH
                        set_ifcfg_bond_file $bond $NS_SRC_ACTIVE_NIC $NS_CONFIG_ACTIVE_NIC $APPROACH_BA_PATH

                        echo "Active NIC : $nic"
                        echo "New Active NIC : $NS_CONFIG_ACTIVE_NIC"
                fi
        done
done

set_config_permission $APPROACH_AA_PATH
set_config_permission $APPROACH_BB_PATH
set_config_permission $APPROACH_BA_PATH
