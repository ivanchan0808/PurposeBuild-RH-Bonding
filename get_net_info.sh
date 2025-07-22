#!/bin/bash
# RHEL Network Configuration Collector and Backup Script
# Version: 1.0
# Description: Collects network configuration and backs up critical files
# Compatible with RHEL 8/9 using NetworkManager

# Set variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/network_backup_${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/network_info_${TIMESTAMP}.log"

# Create backup directory
mkdir -p "${BACKUP_DIR}"
echo "Network configuration backup started at $(date)" > "${LOG_FILE}"

# Function to log commands
log_cmd() {
    echo -e "\n# $1" >> "${LOG_FILE}"
    eval "$1" >> "${LOG_FILE}" 2>&1
}

# 1. System Information
log_cmd "echo '===== System Information ====='"
log_cmd "cat /etc/redhat-release"
log_cmd "uname -a"
log_cmd "hostname"

# 2. Network Interface Information
log_cmd "echo -e '\n===== Network Interfaces ====='"
log_cmd "nmcli device status"
log_cmd "ip link show"
log_cmd "ip addr show"

# 3. Bonding Information
log_cmd "echo -e '\n===== Bonding Information ====='"
for bond in $(ls /sys/class/net | grep bond | grep -v bonding_master); do
    log_cmd "echo -e '\n--- Bond: ${bond} ---'"
    log_cmd "cat /proc/net/bonding/${bond}"
    log_cmd "nmcli connection show ${bond}"
    log_cmd "cat /sys/class/net/${bond}/bonding/mode"
    log_cmd "cat /sys/class/net/${bond}/bonding/slaves"
done

# 4. NetworkManager Connections
log_cmd "echo -e '\n===== NetworkManager Connections ====='"
log_cmd "nmcli connection show"

# 5. Routing Information
log_cmd "echo -e '\n===== Routing Information ====='"
log_cmd "ip route show"
log_cmd "ip -6 route show"
log_cmd "nmcli connection show | grep route"

# 6. DNS Configuration
log_cmd "echo -e '\n===== DNS Configuration ====='"
log_cmd "cat /etc/resolv.conf"
log_cmd "nmcli connection show | grep dns"

# 7. ARP and Neighbor Cache
log_cmd "echo -e '\n===== ARP/Neighbor Cache ====='"
log_cmd "ip neigh show"

# 8. Firewall Information
log_cmd "echo -e '\n===== Firewall Information ====='"
log_cmd "systemctl status firewalld"
log_cmd "firewall-cmd --list-all"

# 9. Backup configuration files
log_cmd "echo -e '\n===== Backing up configuration files ====='"

# NetworkManager connections
mkdir -p "${BACKUP_DIR}/NetworkManager"
log_cmd "cp -a /etc/NetworkManager/system-connections/ ${BACKUP_DIR}/NetworkManager/"

# Legacy network scripts (if any)
mkdir -p "${BACKUP_DIR}/network-scripts"
log_cmd "cp -a /etc/sysconfig/network-scripts/ ${BACKUP_DIR}/network-scripts/"

# Other important files
log_cmd "cp /etc/hosts ${BACKUP_DIR}/"
log_cmd "cp /etc/resolv.conf ${BACKUP_DIR}/"
log_cmd "cp /etc/hostname ${BACKUP_DIR}/"

# 10. Create archive
log_cmd "echo -e '\n===== Creating backup archive ====='"
log_cmd "tar -czvf /tmp/network_backup.tar.gz ${BACKUP_DIR}"

echo -e "\nBackup completed!"
echo "Network information log: ${LOG_FILE}"
echo "Configuration backup archive: /tmp/network_backup.tar.gz"
echo "Backup directory: ${BACKUP_DIR}"
