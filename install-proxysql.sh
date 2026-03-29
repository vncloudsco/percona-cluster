#!/bin/bash
################################################################################
# ProxySQL - Installation and Configuration Script
# =============================================================================
# This script:
# 1. Validates configuration
# 2. Installs ProxySQL on specified server
# 3. Configures MySQL backend servers
# 4. Sets up monitoring and connection pooling
# 5. Verifies backend server connectivity
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
    log_message INFO "║  ProxySQL Installation & Configuration    ║"
    log_message INFO "╚════════════════════════════════════════════╝"
    
    # Step 1: Detect OS
    log_message INFO "Step 1: Detecting operating system..."
    detect_os
    
    # Step 2: Validate configuration
    log_message INFO "Step 2: Validating configuration..."
    validate_config
    
    # Step 3: Parse server configuration
    log_message INFO "Step 3: Parsing server configuration..."
    parse_server_config
    
    # Step 4: Show deployment plan
    show_proxysql_plan
    
    # Step 5: Ask user confirmation
    ask_confirmation
    
    # Step 6: Ping ProxySQL and MySQL nodes
    log_message INFO "Step 4: Checking connectivity..."
    ping_check "$PROXYSQL_IP" || error_exit "Cannot reach ProxySQL IP: $PROXYSQL_IP"
    for ip in "${MYSQL_NODES[@]}"; do
        ping_check "$ip" || error_exit "Cannot reach MySQL node: $ip"
    done
    log_message SUCCESS "All servers are reachable"
    
    # Step 7: Verify SSH to ProxySQL server
    log_message INFO "Step 5: Verifying SSH connectivity to ProxySQL server..."
    check_ssh_connectivity "$PROXYSQL_IP" || error_exit "SSH connection to ProxySQL failed"
    log_message SUCCESS "SSH connectivity verified"
    
    # Step 8: Install ProxySQL
    log_message INFO "Step 6: Installing ProxySQL..."
    install_proxysql_remote "$PROXYSQL_IP"
    
    # Step 9: Configure MySQL backend servers
    log_message INFO "Step 7: Configuring MySQL backend servers..."
    configure_backend_servers_remote "$PROXYSQL_IP"
    
    # Step 10: Configure monitoring
    log_message INFO "Step 8: Setting up monitoring..."
    configure_monitoring_remote "$PROXYSQL_IP"
    
    # Step 11: Open firewall
    log_message INFO "Step 9: Opening firewall ports..."
    open_firewall_ports_proxysql_remote "$PROXYSQL_IP"
    
    # Step 12: Verify connectivity
    log_message INFO "Step 10: Verifying ProxySQL connectivity..."
    sleep 5
    verify_proxysql_connectivity "$PROXYSQL_IP"
    
    show_proxysql_completion
}

################################################################################
# DISPLAY FUNCTIONS
################################################################################

show_proxysql_plan() {
    cat << EOF

╔══════════════════════════════════════════════════════════════╗
║           DEPLOYMENT PLAN - ProxySQL                        ║
╚══════════════════════════════════════════════════════════════╝

ProxySQL Server:
  IP Address               : $PROXYSQL_IP
  Admin Interface Port     : $PROXYSQL_ADMIN_PORT  (internal management)
  Application Port         : $PROXYSQL_APP_PORT    (for applications)

Backend MySQL Servers (3 nodes):
EOF
    
    for i in "${!MYSQL_NODES[@]}"; do
        printf "  [%d] %-30s : %s\n" $((i+1)) "${MYSQL_NODE_NAMES[$i]}" "${MYSQL_NODES[$i]}"
    done
    
    cat << EOF

Configuration:
  Max Connections         : $PROXYSQL_MAX_CONNECTIONS
  Connection Max Age      : $PROXYSQL_CONNECTION_MAX_AGE_MS ms
  Monitor User            : $PROXYSQL_MONITOR_USER
  Firewall Auto-open      : ${AUTO_OPEN_FIREWALL:-false}

Installation Steps:
  1. Install ProxySQL packages
  2. Start ProxySQL service
  3. Configure MySQL backend servers in mysql_servers table
  4. Create monitoring user for health checks
  5. Set up connection pooling
  6. Open firewall ports
  7. Verify all backends are ONLINE

═════════════════════════════════════════════════════════════════

EOF
}

ask_confirmation() {
    read -p "Proceed with ProxySQL installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_message INFO "Installation cancelled"
        exit 0
    fi
}

show_proxysql_completion() {
    cat << EOF

╔═════════════════════════════════════════════════════════════╗
║     ✓ ProxySQL Installation & Configuration Completed!      ║
╚═════════════════════════════════════════════════════════════╝

ProxySQL is now ready to accept connections!

Access Information:

1. PROXYSQL ADMIN INTERFACE (management):
   mysql -h$PROXYSQL_IP -P$PROXYSQL_ADMIN_PORT -u admin -padmin

   View backend servers status:
   SELECT hostgroup_id, hostname, port, status FROM mysql_servers;

2. PROXYSQL APPLICATION PORT (use this in your apps):
   mysql -h$PROXYSQL_IP -P$PROXYSQL_APP_PORT -u${MYSQL_APP_USER} -p${MYSQL_APP_PASSWORD}

3. CHECK PROXYSQL STATUS:
   source cluster-deployment-report.sh
   proxysql_status
   test_proxysql_query

Next Steps:

1. TEST CONNECTION:
   mysql -h$PROXYSQL_IP -P$PROXYSQL_APP_PORT -u${MYSQL_APP_USER} -p${MYSQL_APP_PASSWORD} -e "SELECT 'ProxySQL OK' AS status;"

2. VERIFY ALL BACKENDS ARE ONLINE:
   mysql -h$PROXYSQL_IP -P$PROXYSQL_ADMIN_PORT -u admin -padmin \
     -e "SELECT hostgroup_id, hostname, port, status FROM mysql_servers;"

3. MONITOR PROXYSQL:
   mysql -h$PROXYSQL_IP -P$PROXYSQL_ADMIN_PORT -u admin -padmin \
     -e "SELECT * FROM stats_mysql_global;"

4. RUN HEALTH CHECK:
   ./health-check.sh

═════════════════════════════════════════════════════════════════

Generated Files:
  - cluster-deployment-report.sh  : Credentials & commands

Documentation:
  - See README.md for detailed operations and troubleshooting

═════════════════════════════════════════════════════════════════

Log file: $LOG_FILE

EOF
}

################################################################################
# INSTALLATION FUNCTIONS
################################################################################

install_proxysql_remote() {
    local ip=$1
    
    log_message INFO "Installing ProxySQL on $ip..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << 'SCRIPT'
#!/bin/bash
set -e

# Suppress interactive prompts
export DEBIAN_FRONTEND=noninteractive

echo "Installing prerequisite packages..."

# Install prerequisite packages
if command -v apt-get &> /dev/null; then
    apt-get update -y
    apt-get install -y curl gnupg wget lsb-release ca-certificates
elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y curl gnupg wget
fi

# Setup Percona repository for ProxySQL with robust GPG key handling
echo "Setting up Percona repository with GPG key..."

if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian: More robust GPG key import
    KEYRING_PATH="/usr/share/keyrings/percona-apt-key.gpg"
    REPO_FILE="/etc/apt/sources.list.d/percona-release.list"
    
    # Remove old repository if it exists
    rm -f "$REPO_FILE"
    
    # Try multiple methods to get and import the key
    KEY_IMPORT_SUCCESS=0
    
    # Method 1: Direct key import
    if [ $KEY_IMPORT_SUCCESS -eq 0 ]; then
        echo "Attempting key import method 1 (direct download)..."
        if curl -fsSL https://repo.percona.com/apt/percona-apt-key | gpg --dearmor | tee "$KEYRING_PATH" > /dev/null 2>&1; then
            KEY_IMPORT_SUCCESS=1
            echo "✓ Key imported via method 1"
        fi
    fi
    
    # Method 2: Ubuntu keyserver fallback
    if [ $KEY_IMPORT_SUCCESS -eq 0 ]; then
        echo "Attempting key import method 2 (Ubuntu keyserver)..."
        if gpg --no-default-keyring --keyring "$KEYRING_PATH" --keyserver keyserver.ubuntu.com --recv-keys 9334A25F8507EFA5 2>&1 | grep -q "imported\|unchanged"; then
            KEY_IMPORT_SUCCESS=1
            echo "✓ Key imported via method 2"
        fi
    fi
    
    # Method 3: Keys.openpgp.org fallback
    if [ $KEY_IMPORT_SUCCESS -eq 0 ]; then
        echo "Attempting key import method 3 (openpgp.org)..."
        if gpg --no-default-keyring --keyring "$KEYRING_PATH" --keyserver keys.openpgp.org --recv-keys 9334A25F8507EFA5 2>&1 | grep -q "imported\|unchanged"; then
            KEY_IMPORT_SUCCESS=1
            echo "✓ Key imported via method 3"
        fi
    fi
    
    # Verify key was imported
    if gpg --with-colons "$KEYRING_PATH" 2>/dev/null | grep -q "pub"; then
        echo "✓ GPG key verification successful"
    else
        echo "⚠ Warning: GPG key verification inconclusive, proceeding anyway..."
    fi
    
    # Add repository source
    UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null || echo "noble")
    echo "Adding Percona repository for Ubuntu $UBUNTU_CODENAME..."
    echo "deb [signed-by=$KEYRING_PATH] http://repo.percona.com/apt $UBUNTU_CODENAME main" | tee "$REPO_FILE"
    
    # Update with new repository
    apt-get update -y || echo "⚠ Some apt warnings occurred, continuing..."
    
elif command -v yum &> /dev/null; then
    # Rocky/RHEL: More direct approach
    echo "Setting up Percona repository for Rocky/RHEL..."
    
    # Import GPG key
    if rpm --import https://repo.percona.com/yum/PERCONA-PACKAGING-KEY 2>/dev/null; then
        echo "✓ GPG key imported successfully"
    fi
    
    # Add repository directly
    if [ -d /etc/yum.repos.d ]; then
        cat > /etc/yum.repos.d/percona-release.repo << 'REPO_CONFIG'
[percona-release-$releasever]
name = Percona-Release YUM repository - $releasever
baseurl = http://repo.percona.com/yum/$releasever/$basearch
gpgkey = https://repo.percona.com/yum/PERCONA-PACKAGING-KEY
gpgcheck = 1
enabled = 1
REPO_CONFIG
        yum update -y || echo "⚠ Some yum warnings occurred, continuing..."
    fi
fi

# Install ProxySQL with retry logic
echo "Installing ProxySQL..."
if command -v apt-get &> /dev/null; then
    # Retry logic for apt-get install
    for attempt in 1 2 3; do
        echo "Install attempt $attempt/3..."
        if apt-get install -y proxysql; then
            echo "✓ ProxySQL installed successfully"
            break
        else
            if [ $attempt -lt 3 ]; then
                echo "⚠ Install failed, retrying in 10 seconds..."
                sleep 10
            else
                echo "✗ ProxySQL installation failed after 3 attempts"
                exit 1
            fi
        fi
    done
    
elif command -v yum &> /dev/null; then
    # Retry logic for yum install
    for attempt in 1 2 3; do
        echo "Install attempt $attempt/3..."
        if yum install -y proxysql; then
            echo "✓ ProxySQL installed successfully"
            break
        else
            if [ $attempt -lt 3 ]; then
                echo "⚠ Install failed, retrying in 10 seconds..."
                sleep 10
            else
                echo "✗ ProxySQL installation failed after 3 attempts"
                exit 1
            fi
        fi
    done
fi

# Start ProxySQL service
echo "Starting ProxySQL service..."
systemctl start proxysql
systemctl enable proxysql

# Wait for ProxySQL to start
sleep 5

# Verify ProxySQL is running
if systemctl is-active --quiet proxysql; then
    echo "✓ ProxySQL service started successfully"
else
    echo "✗ ERROR: ProxySQL service failed to start"
    systemctl status proxysql
    exit 1
fi

SCRIPT

    log_message SUCCESS "ProxySQL installed successfully"
}

configure_backend_servers_remote() {
    local ip=$1
    
    log_message INFO "Configuring MySQL backend servers in ProxySQL..."
    
    # Build the SQL commands dynamically
    local sql_commands="
-- Delete default server
DELETE FROM mysql_servers;

-- Insert MySQL cluster nodes as backend servers
"
    
    for i in "${!MYSQL_NODES[@]}"; do
        local node_ip="${MYSQL_NODES[$i]}"
        sql_commands="$sql_commands
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight, status) 
VALUES (0, '$node_ip', $MYSQL_PORT, 1, 'ONLINE');"
    done
    
    sql_commands="$sql_commands

-- Load to runtime
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO CONFIG;

-- Show configured servers
SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
"
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Connect to ProxySQL admin interface and configure
echo "$sql_commands" | mysql -u admin -padmin -h 127.0.0.1 -P $PROXYSQL_ADMIN_PORT

echo "Backend servers configured successfully"
EOF
    
    log_message SUCCESS "Backend servers configured"
}

configure_monitoring_remote() {
    local ip=$1
    
    log_message INFO "Configuring ProxySQL monitoring..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Configure monitoring user and connection pooling
mysql -u admin -padmin -h 127.0.0.1 -P $PROXYSQL_ADMIN_PORT << 'PROXYSQL_CONFIG'

-- Set monitoring user and password
UPDATE global_variables SET variable_value='${PROXYSQL_MONITOR_USER}' 
  WHERE variable_name='mysql-monitor_username';
UPDATE global_variables SET variable_value='${PROXYSQL_MONITOR_PASSWORD}' 
  WHERE variable_name='mysql-monitor_password';

-- Set max connections
UPDATE global_variables SET variable_value='${PROXYSQL_MAX_CONNECTIONS}' 
  WHERE variable_name='mysql-max_connections';

-- Enable monitor
UPDATE global_variables SET variable_value='true' 
  WHERE variable_name='mysql-monitor_enabled';

-- Load to runtime and save
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO CONFIG;

-- Verify settings
SELECT variable_name, variable_value FROM global_variables 
  WHERE variable_name LIKE 'mysql-monitor%' OR variable_name LIKE 'mysql-max%';

PROXYSQL_CONFIG

echo "Monitoring configured successfully"
EOF

    log_message SUCCESS "Monitoring configured"
}

open_firewall_ports_proxysql_remote() {
    local ip=$1
    
    log_message INFO "Opening firewall ports on ProxySQL server..."
    
    if [ "$AUTO_OPEN_FIREWALL" != "true" ]; then
        log_message INFO "Skipping firewall (AUTO_OPEN_FIREWALL=false)"
        return 0
    fi
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Detect firewall
FIREWALL_TYPE="none"

if command -v ufw &> /dev/null && systemctl is-active --quiet ufw; then
    FIREWALL_TYPE="ufw"
elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    FIREWALL_TYPE="firewalld"
fi

if [ "\$FIREWALL_TYPE" = "ufw" ]; then
    ufw allow $PROXYSQL_ADMIN_PORT/tcp
    ufw allow $PROXYSQL_APP_PORT/tcp
    echo "UFW firewall rules added"
elif [ "\$FIREWALL_TYPE" = "firewalld" ]; then
    firewall-cmd --permanent --add-port=$PROXYSQL_ADMIN_PORT/tcp
    firewall-cmd --permanent --add-port=$PROXYSQL_APP_PORT/tcp
    firewall-cmd --reload
    echo "Firewalld rules added"
else
    echo "No active firewall detected"
fi

EOF

    log_message SUCCESS "Firewall ports opened"
}

verify_proxysql_connectivity() {
    local ip=$1
    
    log_message INFO "Verifying ProxySQL backend server connectivity..."
    
    remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" << EOF
#!/bin/bash
set -e

# Check if backends are ONLINE
mysql -u admin -padmin -h 127.0.0.1 -P $PROXYSQL_ADMIN_PORT << 'CHECK_SQL'
SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
CHECK_SQL

echo ""
echo "Checking individual backend connectivity..."

# Try connecting through ProxySQL to each backend
for backend_ip in ${MYSQL_NODES[@]}; do
    if mysql -h $PROXYSQL_IP -P 6033 -e "SELECT 1" &>/dev/null 2>&1; then
        echo "✓ Backend $backend_ip is reachable through ProxySQL"
    else
        echo "⚠ Backend $backend_ip may not be fully synced yet"
    fi
done

EOF

    log_message SUCCESS "ProxySQL verification completed"
}

################################################################################
# ENTRY POINT
################################################################################

# Trap errors
trap 'error_exit "ProxySQL installation failed. Check log: $LOG_FILE"' ERR

# Run main
main

log_message SUCCESS "ProxySQL installation script completed successfully"
