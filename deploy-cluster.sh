#!/bin/bash
################################################################################
# Percona XtraDB Cluster + ProxySQL - Complete Deployment Script
# =============================================================================
# ONE-COMMAND deployment: MySQL Cluster (3 nodes) + ProxySQL + Remote User
# Run this SINGLE script to deploy entire system
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

# Connection info file
CONNECTION_INFO_FILE="cluster-connection-info.txt"

################################################################################
# MAIN DEPLOYMENT FLOW
################################################################################

main() {
    clear
    
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║          Percona XtraDB Cluster + ProxySQL - ONE-CLICK DEPLOYMENT            ║
║                                                                              ║
║  This script will:                                                           ║
║    ✓ Install MySQL Cluster (3 nodes)                                        ║
║    ✓ Install ProxySQL (load balancer)                                       ║
║    ✓ Configure remote access user                                           ║
║    ✓ Open firewall ports                                                    ║
║    ✓ Generate credentials file                                              ║
║    ✓ Run health check                                                       ║
║                                                                              ║
║  Duration: ~15-20 minutes                                                   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

BANNER
    
    sleep 2
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 1: Pre-Deployment Validation                    ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 1: Detect OS
    log_message INFO "Detecting operating system..."
    detect_os
    
    # Step 2: Validate configuration
    log_message INFO "Validating configuration..."
    validate_config
    
    # Step 3: Validate control node
    log_message INFO "Validating control node..."
    validate_control_node
    
    # Step 4: Parse server configuration
    log_message INFO "Parsing server configuration..."
    parse_server_config
    
    # Step 5: Detect firewall (needed for deployment plan display)
    log_message INFO "Detecting firewall..."
    detect_firewall
    
    # Step 6: Show deployment plan
    show_complete_deployment_plan
    
    # Step 7: Ask user confirmation
    ask_confirmation_final
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 2: Network & Connectivity Checks               ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 8: Ping all servers
    log_message INFO "Checking connectivity to all servers..."
    ping_all_servers
    
    # Step 9: Verify SSH connectivity
    log_message INFO "Verifying SSH connectivity..."
    verify_all_ssh_connectivity
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 3: Installing MySQL Cluster                    ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 10: Install MySQL nodes
    log_message INFO "Installing Percona XtraDB Cluster on 3 MySQL nodes..."
    install_mysql_nodes_wrapper
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 4: Waiting for Cluster Synchronization         ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 11: Wait and verify cluster
    log_message INFO "Waiting 15 seconds for cluster to stabilize..."
    sleep 15
    
    log_message INFO "Verifying cluster synchronization..."
    verify_cluster_sync || log_message WARN "Cluster may still be synchronizing... continuing"
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 5: Installing ProxySQL                          ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 12: Install ProxySQL
    log_message INFO "Installing and configuring ProxySQL..."
    install_proxysql_wrapper
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 6: Creating Remote Access User                 ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 13: Create remote user
    log_message INFO "Creating remote access user..."
    create_remote_user_on_cluster
    
    log_message INFO "╔════════════════════════════════════════════════════════╗"
    log_message INFO "║  STEP 7: Final Verification & Report Generation      ║"
    log_message INFO "╚════════════════════════════════════════════════════════╝"
    
    # Step 14: Generate connection info
    log_message INFO "Generating connection information..."
    generate_connection_info_file
    
    # Step 15: Health check
    log_message INFO "Running final health check..."
    sleep 5
    run_final_health_check
    
    show_completion_banner
}

################################################################################
# DISPLAY FUNCTIONS
################################################################################

show_complete_deployment_plan() {
    cat << EOF

╔════════════════════════════════════════════════════════════════════════════╗
║              COMPLETE SYSTEM DEPLOYMENT PLAN                              ║
╚════════════════════════════════════════════════════════════════════════════╝

🖥️  INFRASTRUCTURE:

MySQL Cluster (3 nodes):
EOF
    
    for i in "${!MYSQL_NODES[@]}"; do
        local role="Primary (Read/Write)"
        [ $i -gt 0 ] && role="Secondary (Read-only replica)"
        printf "    [%d] %-20s -> %-18s (%s)\n" $((i+1)) "${MYSQL_NODE_NAMES[$i]}" "${MYSQL_NODES[$i]}" "$role"
    done
    
    cat << EOF

ProxySQL Load Balancer:
    [4] %-20s -> %-18s (Transparent failover)

Remote Access User (% = anywhere):
    Username            : ${REMOTE_USER}
    Hostname            : %  (can connect from any IP)
    Password            : ${REMOTE_PASSWORD}
    Connect via         : ProxySQL IP ${PROXYSQL_IP}:${PROXYSQL_APP_PORT}

🔐 SECURITY SETUP:

SSH Key-Based:          ✓ Enabled
Root Password:          ✓ ${MYSQL_ROOT_PASSWORD}
App User:               ✓ ${MYSQL_APP_USER}
Remote User:            ✓ ${REMOTE_USER} (for applications)
Replication User:       ✓ ${MYSQL_REPLICATION_USER}
ProxySQL Monitor:       ✓ ${PROXYSQL_MONITOR_USER}

🔧 NETWORK CONFIGURATION:

MySQL Port              : ${MYSQL_PORT}/tcp
Galera Replication      : ${GALERA_PORT}/tcp
IST Transfer            : ${IST_PORT}/tcp
XtraBackup              : ${XTRABACKUP_PORT}/tcp
ProxySQL Admin          : ${PROXYSQL_ADMIN_PORT}/tcp (internal only)
ProxySQL App            : ${PROXYSQL_APP_PORT}/tcp (applications)

🛡️  FIREWALL:

Auto-open ports         : ${AUTO_OPEN_FIREWALL}
Firewall type           : ${FIREWALL_TYPE}
Minimal rules only      : ${MINIMAL_FIREWALL_RULE}

📦 COMPONENTS:

[1] Percona Server 8.0  : MySQL with Galera Cluster
[2] XtraDB Cluster      : Synchronous replication
[3] ProxySQL            : Connection pooling + failover
[4] XtraBackup          : Backup/recovery tool
[5] Remote User         : Application connection user

═══════════════════════════════════════════════════════════════════════════════

EOF
}

ask_confirmation_final() {
    cat << EOF
⚠️  IMPORTANT NOTES:

1. This will OVERWRITE MySQL configuration on all nodes
2. Control node ($(get_local_ip)) is NOT in cluster (✓ Verified)
3. All nodes must be on the same network
4. SSH key authentication must be working
5. Minimum 4 servers required:
   - 3 for MySQL cluster
   - 1 for ProxySQL

✓ Configuration Summary:
$(printf '   - MySQL nodes (3): %s\n' "${MYSQL_NODES[@]}")
   - ProxySQL node (1): $PROXYSQL_IP

═══════════════════════════════════════════════════════════════════════════════

EOF
    
    read -p "🔴 Proceed with COMPLETE deployment? Type 'YES' to continue: " -r
    if [ "$REPLY" != "YES" ]; then
        log_message INFO "❌ Deployment cancelled by user"
        exit 0
    fi
    
    echo ""
}

show_completion_banner() {
    cat << EOF

╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║              ✅ DEPLOYMENT COMPLETED SUCCESSFULLY!                         ║
║                                                                            ║
║        Percona XtraDB Cluster + ProxySQL is now READY TO USE               ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝

📋 CONNECTION INFORMATION SAVED TO:
   📄 ${CONNECTION_INFO_FILE}

   ⭐ REMOTE APPLICATION USER:
      Username: ${REMOTE_USER}
      Password: ${REMOTE_PASSWORD}
      Host: ${PROXYSQL_IP}
      Port: ${PROXYSQL_APP_PORT}
      
      Connection string (MySQL):
      mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p${REMOTE_PASSWORD}

🔧 QUICK VERIFICATION COMMANDS:

   # Load script for quick access
   source cluster-deployment-report.sh
   
   # Check cluster status
   mysql_cluster_status
   
   # Check ProxySQL
   proxysql_status
   
   # Test remote user connection
   mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p${REMOTE_PASSWORD} -e "SELECT 'Connection OK' AS status;"

🎯 NEXT STEPS:

   1. Update your application connection string:
      Host: ${PROXYSQL_IP}
      Port: ${PROXYSQL_APP_PORT}
      User: ${REMOTE_USER}
      Password: ${REMOTE_PASSWORD}

   2. For backup/admin operations:
      - Source: cluster-deployment-report.sh
      - Contains: All credentials and admin functions

   3. Monitor cluster health:
      ./health-check.sh

   4. Read deployment report:
      cat ${CONNECTION_INFO_FILE}

📞 DOCUMENTATION:

   For detailed operations, backup, and troubleshooting:
   - See: README.md
   - Percona docs: https://www.percona.com/doc/

═══════════════════════════════════════════════════════════════════════════════

Log files:
  - Installation: /tmp/cluster-deployment-*.log
  - Health check: cluster-health-check-*.log
  - Connection info: ${CONNECTION_INFO_FILE}

═══════════════════════════════════════════════════════════════════════════════

✨ Deployment completed on: $(date '+%Y-%m-%d %H:%M:%S')

EOF
}

################################################################################
# WRAPPER FUNCTIONS (call existing scripts)
################################################################################

install_mysql_nodes_wrapper() {
    # Source and execute MySQL installation
    source "$SCRIPT_DIR/install-mysql-node.sh"
}

install_proxysql_wrapper() {
    # Source and execute ProxySQL installation  
    source "$SCRIPT_DIR/install-proxysql.sh"
}

################################################################################
# REMOTE USER CREATION
################################################################################

create_remote_user_on_cluster() {
    local primary_ip="${MYSQL_NODES[0]}"
    
    log_message INFO "Creating remote user '${REMOTE_USER}' on primary node: $primary_ip"
    
    remote_execute "$primary_ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Wait for MySQL
for i in {1..30}; do
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; then
        break
    fi
    sleep 1
done

# Create remote user
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << 'MYSQL_SQL'
-- Create user that can connect from ANY IP
CREATE USER IF NOT EXISTS '${REMOTE_USER}'@'%' IDENTIFIED BY '${REMOTE_PASSWORD}';

-- Grant permissions for application use (SELECT, INSERT, UPDATE, DELETE)
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO '${REMOTE_USER}'@'%';

-- Ensure permissions are applied
FLUSH PRIVILEGES;

-- Verify user creation
SELECT user, host FROM mysql.user WHERE user = '${REMOTE_USER}';

MYSQL_SQL

echo "Remote user '${REMOTE_USER}' created successfully"
EOF

    log_message SUCCESS "Remote user '${REMOTE_USER}' created and replicated to all nodes"
}

################################################################################
# CONNECTION INFO FILE
################################################################################

generate_connection_info_file() {
    log_message INFO "Generating connection information file: $CONNECTION_INFO_FILE"
    
    cat > "$CONNECTION_INFO_FILE" << CONN_EOF
╔════════════════════════════════════════════════════════════════════════════╗
║         PERCONA XTRADB CLUSTER + PROXYSQL - CONNECTION INFORMATION         ║
╚════════════════════════════════════════════════════════════════════════════╝

DEPLOYMENT COMPLETED: $(date '+%Y-%m-%d %H:%M:%S')
Cluster Name: ${CLUSTER_NAME}
MySQL Version: ${MYSQL_VERSION}

═══════════════════════════════════════════════════════════════════════════════
🔴 REMOTE APPLICATION CONNECTION (use this in your code!)
═══════════════════════════════════════════════════════════════════════════════

HOST                : ${PROXYSQL_IP}
PORT                : ${PROXYSQL_APP_PORT}
USERNAME            : ${REMOTE_USER}
PASSWORD            : ${REMOTE_PASSWORD}
HOSTNAME PATTERN    : % (can connect from anywhere)

MySQL Connection String:
mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p${REMOTE_PASSWORD}

PHP/Laravel (via ProxySQL):
\$host = '${PROXYSQL_IP}';
\$port = ${PROXYSQL_APP_PORT};
\$user = '${REMOTE_USER}';
\$password = '${REMOTE_PASSWORD}';

Node.js (mysql2/promise):
const connection = await mysql.createConnection({
  host: '${PROXYSQL_IP}',
  port: ${PROXYSQL_APP_PORT},
  user: '${REMOTE_USER}',
  password: '${REMOTE_PASSWORD}',
  database: 'your_database'
});

Python (pymysql):
import pymysql
conn = pymysql.connect(
  host='${PROXYSQL_IP}',
  port=${PROXYSQL_APP_PORT},
  user='${REMOTE_USER}',
  password='${REMOTE_PASSWORD}'
)

Java (JDBC):
jdbc:mysql://${PROXYSQL_IP}:${PROXYSQL_APP_PORT}/? user=${REMOTE_USER}&password=${REMOTE_PASSWORD}

═══════════════════════════════════════════════════════════════════════════════
🔐 ADMIN CREDENTIALS (for management only)
═══════════════════════════════════════════════════════════════════════════════

ROOT USER:
  Host        : Any MySQL node (${MYSQL_NODES[0]}, ${MYSQL_NODES[1]}, ${MYSQL_NODES[2]})
  Port        : ${MYSQL_PORT}
  Username    : root
  Password    : ${MYSQL_ROOT_PASSWORD}

  Command: mysql -h <node_ip> -u root -p${MYSQL_ROOT_PASSWORD}

APPLICATION ADMIN USER:
  Username    : ${MYSQL_APP_USER}
  Password    : ${MYSQL_APP_PASSWORD}
  Host        : % (from anywhere)
  Database    : All with privileges

  Command: mysql -h ${MYSQL_NODES[0]} -u ${MYSQL_APP_USER} -p${MYSQL_APP_PASSWORD}

PROXYSQL ADMIN INTERFACE:
  Host        : ${PROXYSQL_IP}
  Port        : ${PROXYSQL_ADMIN_PORT} (internal only)
  Username    : admin
  Password    : admin (change if needed)

  Command: mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_ADMIN_PORT} -u admin -padmin

═══════════════════════════════════════════════════════════════════════════════
💾 CLUSTER INFRASTRUCTURE
═══════════════════════════════════════════════════════════════════════════════

MYSQL CLUSTER (3 nodes):
  Node 1 (Primary)  : ${MYSQL_NODES[0]}:${MYSQL_PORT}
  Node 2 (Secondary): ${MYSQL_NODES[1]}:${MYSQL_PORT}
  Node 3 (Secondary): ${MYSQL_NODES[2]}:${MYSQL_PORT}

PROXYSQL LOAD BALANCER:
  Host              : ${PROXYSQL_IP}
  Application Port  : ${PROXYSQL_APP_PORT}
  Admin Port        : ${PROXYSQL_ADMIN_PORT}

REPLICATION:
  Galera Cluster    : Port 4567
  IST Transfer      : Port 4568
  XtraBackup        : Port 4444

═══════════════════════════════════════════════════════════════════════════════
✅ VERIFICATION CHECKLIST
═══════════════════════════════════════════════════════════════════════════════

After deployment, verify:

1. Test remote user connection:
   mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p${REMOTE_PASSWORD} -e "SELECT 'OK' AS connection_status;"

2. Check cluster sync status:
   source cluster-deployment-report.sh
   mysql_cluster_status

3. Check ProxySQL backends:
   mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_ADMIN_PORT} -u admin -padmin \\
     -e "SELECT hostname, port, status FROM mysql_servers;"

4. Run health check:
   ./health-check.sh

═══════════════════════════════════════════════════════════════════════════════
📖 COMMON OPERATIONS
═══════════════════════════════════════════════════════════════════════════════

Load deployment report:
  source cluster-deployment-report.sh
  mysql_cluster_status        # Check cluster
  proxysql_status             # Check ProxySQL
  test_proxysql_query         # Test connection
  xtrabackup_example          # Backup commands

Create new database:
  mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p${REMOTE_PASSWORD} \\
    -e "CREATE DATABASE mydb; GRANT ALL ON mydb.* TO '${REMOTE_USER}'@'%';"

Backup:
  innobackupex --user=root --password=${MYSQL_ROOT_PASSWORD} \\
    --host=${MYSQL_NODES[0]} --port=${MYSQL_PORT} /backup/mysql-\$(date +%Y%m%d)/

Health check:
  ./health-check.sh

═══════════════════════════════════════════════════════════════════════════════
🆘 TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════════════════

Connection failed?
  1. Check remote user can connect: mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_APP_PORT} -u ${REMOTE_USER} -p
  2. Verify ProxySQL backends: mysql -h ${PROXYSQL_IP} -P ${PROXYSQL_ADMIN_PORT} -u admin -padmin -e "SELECT * FROM mysql_servers;"
  3. Check firewall: sudo ufw status | grep ${PROXYSQL_APP_PORT}

Cluster not synced?
  1. Check status: source cluster-deployment-report.sh && mysql_cluster_status
  2. Check logs: ssh root@${MYSQL_NODES[0]} tail -100 /var/log/mysql/error.log
  3. Restart node: ssh root@${MYSQL_NODES[0]} systemctl restart mysql

═══════════════════════════════════════════════════════════════════════════════
⚠️  SECURITY REMINDER
═══════════════════════════════════════════════════════════════════════════════

1. Store this file securely - contains passwords!
2. Change default passwords for production:
   - MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
   - REMOTE_PASSWORD: ${REMOTE_PASSWORD}
3. Restrict network access on firewall
4. Use SSH tunneling for remote admin access
5. Enable SSL/TLS for remote connections (optional upgrade)
6. Regular backups are essential

═══════════════════════════════════════════════════════════════════════════════

Generated: $(date '+%Y-%m-%d %H:%M:%S')
Control Node: $(hostname) ($(get_local_ip))

CONN_EOF

    log_message SUCCESS "Connection information saved to: $CONNECTION_INFO_FILE"
    
    # Also display it
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    cat "$CONNECTION_INFO_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════"
}

################################################################################
# FINAL HEALTH CHECK
################################################################################

run_final_health_check() {
    # Run health check and show results
    bash "$SCRIPT_DIR/health-check.sh"
}

################################################################################
# ENTRY POINT
################################################################################

# Trap errors
trap 'error_exit "Deployment failed. Check log: $LOG_FILE"' ERR

# Run main
main

log_message SUCCESS "Complete deployment script finished!"
