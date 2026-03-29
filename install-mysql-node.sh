#!/bin/bash
################################################################################
# Percona XtraDB Cluster - MySQL Node Installation Script
# =============================================================================
# This script:
# 1. Validates configuration
# 2. Detects OS and installs Percona XtraDB Cluster
# 3. Configures Galera replication
# 4. Sets up MySQL users
# 5. Opens firewall ports
# 6. Verifies cluster sync
################################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source configuration and functions
if [ ! -f "$SCRIPT_DIR/cluster-config.sh" ]; then
    echo "ERROR: cluster-config.sh not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/lib-functions.sh" ]; then
    echo "ERROR: lib-functions.sh not found in $SCRIPT_DIR"
    exit 1
fi

source "$SCRIPT_DIR/cluster-config.sh"
source "$SCRIPT_DIR/lib-functions.sh"

################################################################################
# MAIN EXECUTION FLOW
################################################################################

main() {
    log_message INFO "╔════════════════════════════════════════════╗"
    log_message INFO "║  Percona XtraDB Cluster Installation      ║"
    log_message INFO "║  MySQL Nodes Setup                         ║"
    log_message INFO "╚════════════════════════════════════════════╝"
    
    # Step 1: Detect OS
    log_message INFO "Step 1: Detecting operating system..."
    detect_os
    
    # Step 2: Validate configuration
    log_message INFO "Step 2: Validating configuration..."
    validate_config
    
    # Step 3: Validate control node
    log_message INFO "Step 3: Validating control node..."
    validate_control_node
    
    # Step 4: Parse server configuration
    log_message INFO "Step 4: Parsing server configuration..."
    parse_server_config
    
    # Step 5: Show deployment plan
    show_deployment_plan
    
    # Step 6: Ask user confirmation
    ask_confirmation
    
    # Step 7: Ping all servers
    log_message INFO "Step 5: Checking connectivity to all servers..."
    ping_all_servers
    
    # Step 8: Verify SSH connectivity
    log_message INFO "Step 6: Verifying SSH connectivity..."
    verify_all_ssh_connectivity
    
    # Step 9: Detect firewall
    log_message INFO "Step 7: Detecting firewall..."
    detect_firewall
    
    # Step 10: Install MySQL nodes
    log_message INFO "Step 8: Installing Percona XtraDB Cluster..."
    install_mysql_nodes
    
    # Step 11: Verify cluster
    log_message INFO "Step 9: Verifying cluster synchronization..."
    sleep 10  # Wait for cluster to stabilize
    verify_cluster_sync
    
    # Step 12: Generate report
    log_message INFO "Step 10: Generating deployment report..."
    generate_deployment_report
    
    show_completion_message
}

################################################################################
# DISPLAY FUNCTIONS
################################################################################

show_deployment_plan() {
    cat << EOF

╔══════════════════════════════════════════════════════════════╗
║           DEPLOYMENT PLAN - MySQL Cluster                   ║
╚══════════════════════════════════════════════════════════════╝

Configuration Summary:
  Cluster Name    : $CLUSTER_NAME
  MySQL Version   : $MYSQL_VERSION
  
MySQL Nodes (3 total):
EOF
    
    for i in "${!MYSQL_NODES[@]}"; do
        local role="Primary (Read/Write)"
        [ $i -gt 0 ] && role="Secondary (Read-only replica)"
        printf "    [%d] %-15s -> %s (%s)\n" $((i+1)) "${MYSQL_NODE_NAMES[$i]}" "${MYSQL_NODES[$i]}" "$role"
    done
    
    cat << EOF

ProxySQL Server:
    [4] ProxySQL         -> $PROXYSQL_IP (will be installed separately)

Network Configuration:
  MySQL Port      : $MYSQL_PORT
  Galera Port     : $GALERA_PORT
  IST Port        : $IST_PORT
  XtraBackup Port : $XTRABACKUP_PORT
  ProxySQL Admin  : $PROXYSQL_ADMIN_PORT
  ProxySQL App    : $PROXYSQL_APP_PORT

Firewall:
  Auto open ports : ${AUTO_OPEN_FIREWALL:-false}
  Type detected   : ${FIREWALL_TYPE:-none}

Installation Steps:
  1. Install Percona XtraDB Cluster packages on all 3 nodes
  2. Configure Galera replication
  3. Initialize primary node (node-1) with --wsrep-new-cluster
  4. Secondary nodes join cluster automatically
  5. Create MySQL users on primary (replicate to secondaries)
  6. Verify cluster synchronization
  7. Open firewall ports
  8. Install XtraBackup on all nodes

═════════════════════════════════════════════════════════════════

EOF
}

ask_confirmation() {
    read -p "Proceed with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_message INFO "Installation cancelled"
        exit 0
    fi
}

show_completion_message() {
    cat << EOF

╔═════════════════════════════════════════════════════════════╗
║        ✓ MySQL Cluster Installation Completed!             ║
╚═════════════════════════════════════════════════════════════╝

Cluster Status:
  Cluster Name: $CLUSTER_NAME
  Nodes Ready : $(printf '%d/3' $((${#MYSQL_NODES[@]})))
  
Next Steps:

1. VERIFY CLUSTER STATUS:
   source cluster-deployment-report.sh
   mysql_cluster_status

2. TEST CONNECTION:
   mysql -h${MYSQL_NODES[0]} -u$MYSQL_ROOT_USER -p$MYSQL_ROOT_PASSWORD

3. INSTALL PROXYSQL:
   ./install-proxysql.sh

4. HEALTH CHECK:
   ./health-check.sh

Generated Files:
  - cluster-deployment-report.sh  : Credentials & commands
  - cluster-health-check.log      : System log

Documentation:
  - See README.md for detailed operations, troubleshooting, and backup procedures

═════════════════════════════════════════════════════════════════

Log file: $LOG_FILE

EOF
}

################################################################################
# INSTALLATION FUNCTIONS
################################################################################

install_mysql_nodes() {
    for i in "${!MYSQL_NODES[@]}"; do
        local node_ip="${MYSQL_NODES[$i]}"
        local node_name="${MYSQL_NODE_NAMES[$i]}"
        
        log_message INFO "Installing MySQL on node $((i+1))/3: $node_name ($node_ip)"
        
        # Step 1: Install packages
        install_packages_remote "$node_ip" "$node_name"
        
        # Step 2: Configure Galera
        configure_galera_remote "$node_ip" "$node_name" "$i"
        
        # Step 3: Start MySQL
        if [ $i -eq 0 ]; then
            # Primary node: start with --wsrep-new-cluster
            start_mysql_primary_remote "$node_ip" "$node_name"
            # Create users on primary
            create_mysql_users_remote "$node_ip"
        else
            # Secondary nodes: start normally
            start_mysql_secondary_remote "$node_ip" "$node_name"
        fi
        
        log_message SUCCESS "Node $((i+1))/3 installation completed: $node_name"
        
        # Wait between nodes
        if [ $i -lt $((${#MYSQL_NODES[@]} - 1)) ]; then
            log_message INFO "Waiting 5 seconds before next node..."
            sleep 5
        fi
    done
}

install_packages_remote() {
    local ip=$1
    local node_name=$2
    
    log_message INFO "  Installing system packages on $node_name..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << 'SCRIPT'
#!/bin/bash
set -e

# Install prerequisite packages first
if command -v apt-get &> /dev/null; then
    apt-get update -y
    apt-get install -y curl gnupg wget
elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y curl gnupg wget
fi

# Install Percona repository BEFORE trying to install specific packages
if ! [ -f /etc/apt/sources.list.d/percona-release.list ] && \
   ! [ -f /etc/yum.repos.d/percona-release.repo ]; then
    echo "Installing Percona repository..."
    
    if command -v apt-get &> /dev/null; then
        # For Debian/Ubuntu: use percona-release package
        if ! command -v percona-release &> /dev/null; then
            curl -O https://repo.percona.com/apt/percona-release_latest.deb
            dpkg -i percona-release_latest.deb
            rm -f percona-release_latest.deb
        fi
        percona-release setup -y
    elif command -v yum &> /dev/null; then
        # For Rocky/RHEL
        if ! command -v percona-release &> /dev/null; then
            rpm -Uhv https://repo.percona.com/yum/percona-release-latest.noarch.rpm
        fi
    fi
fi

# Now update again after repo setup
if command -v apt-get &> /dev/null; then
    apt-get update -y
elif command -v yum &> /dev/null; then
    yum update -y
fi

# Install Percona XtraDB Cluster and related packages
if command -v apt-get &> /dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        percona-server-server \
        percona-xtradb-cluster \
        percona-xtradb-cluster-server \
        percona-xtrabackup-80
elif command -v yum &> /dev/null; then
    yum install -y \
        percona-server-server \
        percona-xtradb-cluster \
        percona-xtradb-cluster-server \
        percona-xtrabackup-80
fi

echo "Packages installed successfully"
SCRIPT
}

configure_galera_remote() {
    local ip=$1
    local node_name=$2
    local node_index=$3
    
    log_message INFO "  Configuring Galera on $node_name..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Find MySQL config file path
if [ -f /etc/mysql/mysql.conf.d/mysqld.cnf ]; then
    MYSQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"
elif [ -f /etc/my.cnf ]; then
    MYSQL_CONFIG="/etc/my.cnf"
else
    MYSQL_CONFIG="/etc/mysql/my.cnf"
fi

# Determine library path based on OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "\$ID" = "ubuntu" ] || [ "\$ID" = "debian" ]; then
        GALERA_LIB="/usr/lib/x86_64-linux-gnu/libgalera_smm.so"
    else
        GALERA_LIB="/usr/lib64/galera4/libgalera_smm.so"
    fi
fi

# Stop MySQL if running
systemctl stop mysql || true
sleep 2

# Backup original config
cp \$MYSQL_CONFIG \${MYSQL_CONFIG}.backup

# Create new Galera configuration
cat >> \$MYSQL_CONFIG << 'GALERA_CONFIG'

[mysqld]
# Galera Settings
wsrep_provider=$GALERA_LIB
wsrep_cluster_name="$CLUSTER_NAME"
wsrep_cluster_address="gcomm://$GALERA_CLUSTER_ADDRESS"
wsrep_node_address="${ip}:$GALERA_PORT"
wsrep_node_name="$node_name"
wsrep_sst_method=xtrabackup-v2
wsrep_sst_auth="${MYSQL_REPLICATION_USER}:${MYSQL_REPLICATION_PASSWORD}"

# Required for XtraDB Cluster
default-storage-engine=InnoDB
innodb_autoinc_lock_mode=2
wsrep_replicate_myisam=OFF
binlog_format=row
bind-address=0.0.0.0
server-id=$((node_index + 1))

GALERA_CONFIG

echo "Galera configuration completed"
EOF
}

start_mysql_primary_remote() {
    local ip=$1
    local node_name=$2
    
    log_message INFO "  Starting primary node (with --wsrep-new-cluster): $node_name..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << 'SCRIPT'
#!/bin/bash
set -e

# Start with --wsrep-new-cluster for primary initialization
mysqld_safe --wsrep-new-cluster &
sleep 10

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin -u root ping &> /dev/null; then
        echo "MySQL is ready"
        break
    fi
    echo "Waiting for MySQL... ($i/30)"
    sleep 1
done

echo "Primary node started successfully"
SCRIPT
}

start_mysql_secondary_remote() {
    local ip=$1
    local node_name=$2
    
    log_message INFO "  Starting secondary node: $node_name..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << 'SCRIPT'
#!/bin/bash
set -e

# Start MySQL normally (will join cluster automatically)
systemctl start mysql

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin -u root ping &> /dev/null; then
        echo "MySQL is ready"
        break
    fi
    echo "Waiting for MySQL... ($i/30)"
    sleep 1
done

# Verify Galera status
echo "Verifying Galera status..."
mysql -u root -e "SHOW STATUS LIKE 'wsrep%';" || echo "Status check pending..."

echo "Secondary node started successfully"
SCRIPT
}

create_mysql_users_remote() {
    local ip=$1
    
    log_message INFO "  Creating MySQL users on primary node..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysql -u root -e "SELECT 1" &> /dev/null; then
        break
    fi
    sleep 1
done

# Create users
mysql -u root << 'MYSQL_SQL'
-- Ensure root password is set
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;

-- Create application user
CREATE USER '${MYSQL_APP_USER}'@'%' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_APP_USER}'@'%';

-- Create replication user
CREATE USER '${MYSQL_REPLICATION_USER}'@'%' IDENTIFIED BY '${MYSQL_REPLICATION_PASSWORD}';
GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO '${MYSQL_REPLICATION_USER}'@'%';

-- Create ProxySQL monitor user (minimal permissions)
CREATE USER '${PROXYSQL_MONITOR_USER}'@'%' IDENTIFIED BY '${PROXYSQL_MONITOR_PASSWORD}';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '${PROXYSQL_MONITOR_USER}'@'%';

FLUSH PRIVILEGES;
MYSQL_SQL

echo "MySQL users created successfully"
EOF
}

################################################################################
# ENTRY POINT
################################################################################

# Trap errors
trap 'error_exit "Installation failed. Check log: $LOG_FILE"' ERR

# Run main
main

log_message SUCCESS "MySQL installation script completed successfully"
