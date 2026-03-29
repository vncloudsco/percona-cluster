#!/bin/bash
################################################################################
# Percona XtraDB Cluster + ProxySQL - Configuration File
# =============================================================================
# IMPORTANT: This is the ONLY file you need to edit!
# Just fill in 4-6 server IPs below, everything else is auto-generated.
#
# ⚠️  CRITICAL: Control node (where script runs) MUST NOT be in this list!
#     Script will validate that local IP is not in ALL_SERVER_IPS
################################################################################

################################################################################
# SERVER CONFIGURATION - User only needs to fill this!
################################################################################

# Array of 4-6 server IPs
# - First 3 IPs will be MySQL Cluster nodes
# - 4th IP will be used for ProxySQL
# - 5+ IPs (optional) will be ignored with warning
#
# MINIMUM: 4 IPs (3 for MySQL, 1 for ProxySQL)
# MAXIMUM: 6+ IPs (script handles any count)
#
# Example: ALL_SERVER_IPS=( "192.168.1.10" "192.168.1.11" "192.168.1.12" "192.168.1.20" )
#
ALL_SERVER_IPS=(
    "10.104.0.5"    # Node 1 - Will become mysql-node-1 (Primary)
    "10.104.0.6"    # Node 2 - Will become mysql-node-2
    "10.104.0.2"    # Node 3 - Will become mysql-node-3
    "10.104.0.4"    # Node 4 - Will become ProxySQL server
    # "192.168.1.21"   # (Optional) Node 5 - will be ignored
    # "192.168.1.22"   # (Optional) Node 6 - will be ignored
)

################################################################################
# CLUSTER INFORMATION
################################################################################

CLUSTER_NAME="MyXtraDBCluster"
MYSQL_VERSION="8.0"

################################################################################
# MYSQL CREDENTIALS & USERS
#
# These users will be created on primary node (node-1) and replicated to others
################################################################################

# Root user password (MUST change this)
MYSQL_ROOT_PASSWORD="t3p35Dcjj52SqywS"

# Application user (can be used by your application)
MYSQL_APP_USER="appuser"
MYSQL_APP_PASSWORD="X8e5guYuUz3vL6q8"

# Replication user (for internal cluster replication)
MYSQL_REPLICATION_USER="repl_user"
MYSQL_REPLICATION_PASSWORD="V4SbQzMJXNypnkrC"

# Remote access user (for applications, can connect from anywhere)
# This user can connect from ANY IP (hostname: %)
# Use this in your application code or for external connections
REMOTE_USER="appremote"
REMOTE_PASSWORD="LJpE2QEJvzC93nFQ"

################################################################################
# PROXYSQL CONFIGURATION
################################################################################

# Monitor user (very minimal permissions - only SELECT from system tables)
PROXYSQL_MONITOR_USER="monitor_user"
PROXYSQL_MONITOR_PASSWORD="v9Tv3wBj8MsqTUxs"

################################################################################
# NETWORK & PORT CONFIGURATION
################################################################################

# MySQL port (Percona XtraDB default)
MYSQL_PORT=3306

# Galera replication port
GALERA_PORT=4567

# Galera IST (Incremental State Transfer) port
IST_PORT=4568

# XtraBackup port (backup traffic)
XTRABACKUP_PORT=4444

# ProxySQL admin port (management interface)
PROXYSQL_ADMIN_PORT=6032

# ProxySQL application port (where apps connect)
PROXYSQL_APP_PORT=6033

################################################################################
# SSH CONFIGURATION (for automated deployment)
################################################################################

# SSH user (must have sudo privileges on all cluster nodes)
SSH_USER="root"

# SSH key path (for key-based authentication - more secure)
# Examples:
#   - /root/.ssh/id_rsa          (running as root)
#   - /home/ubuntu/.ssh/id_rsa   (running as ubuntu user)
#   - /home/admin/.ssh/id_rsa    (running as admin user)
SSH_KEY_PATH="/root/.ssh/id_rsa"

# SSH port (standard SSH port)
SSH_PORT=22

################################################################################
# FIREWALL CONFIGURATION
################################################################################

# Auto-detect and open firewall ports (ufw on Ubuntu, firewalld on Rocky Linux)
# Set to 'true' to auto-open ports, 'false' to skip
AUTO_OPEN_FIREWALL=true

# Minimal firewall rule (only open required ports)
# Principle: Close all, open only what's necessary
MINIMAL_FIREWALL_RULE=true

################################################################################
# ADVANCED OPTIONS (Optional - change only if needed)
################################################################################

# Max connections per ProxySQL backend
PROXYSQL_MAX_CONNECTIONS=100

# Connection max age (in milliseconds)
PROXYSQL_CONNECTION_MAX_AGE_MS=3600000

# Enable XtraBackup (for backup/recovery)
ENABLE_XTRABACKUP=true

# Enable health check script
ENABLE_HEALTH_CHECK=true

################################################################################
# AUTO-GENERATED VARIABLES (Do NOT edit below)
################################################################################

# These will be populated by the installation script
MYSQL_NODE_COUNT=3  # Always 3 MySQL nodes
MYSQL_PRIMARY_IP="${ALL_SERVER_IPS[0]}"
PROXYSQL_IP="${ALL_SERVER_IPS[3]}"

# Script will auto-generate these:
# MYSQL_NODES=( "${ALL_SERVER_IPS[0]}" "${ALL_SERVER_IPS[1]}" "${ALL_SERVER_IPS[2]}" )
# MYSQL_NODE_NAMES=( "mysql-node-1" "mysql-node-2" "mysql-node-3" )
# GALERA_CLUSTER_ADDRESS="gcomm://${ALL_SERVER_IPS[0]},${ALL_SERVER_IPS[1]},${ALL_SERVER_IPS[2]}"

################################################################################
# END OF CONFIGURATION
################################################################################
