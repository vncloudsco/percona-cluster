#!/bin/bash
################################################################################
# Percona XtraDB Cluster + ProxySQL - Shared Functions Library
# =============================================================================
# This file contains all common functions used by installation scripts
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/cluster-deployment-$(date +%Y%m%d_%H%M%S).log"

################################################################################
# LOGGING FUNCTIONS
################################################################################

log_message() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[✓]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    log_message ERROR "$message"
    log_message INFO "Log file: $LOG_FILE"
    exit "$exit_code"
}

################################################################################
# OS DETECTION
################################################################################

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE="$NAME"
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        error_exit "Cannot detect OS. /etc/os-release not found"
    fi
    
    case "$OS_ID" in
        ubuntu)
            OS_FAMILY="debian"
            PKG_MANAGER="apt-get"
            log_message SUCCESS "Detected Ubuntu $OS_VERSION"
            ;;
        rhel|rocky|centos)
            OS_FAMILY="rhel"
            PKG_MANAGER="yum"
            log_message SUCCESS "Detected Rocky/RHEL $OS_VERSION"
            ;;
        *)
            error_exit "Unsupported OS: $OS_ID (only Ubuntu and Rocky Linux supported)"
            ;;
    esac
    
    export OS_FAMILY PKG_MANAGER
}

################################################################################
# IP & NETWORK VALIDATION
################################################################################

validate_ip() {
    local ip=$1
    local pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $pattern ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

get_local_ip() {
    # Get primary IP (not localhost)
    local ip=$(hostname -I | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(/sbin/ip route | awk '/default/ {print $NF}' | xargs /sbin/ip addr show | awk '/inet / {print $2}' | cut -d'/' -f1 | head -1)
    fi
    echo "$ip"
}

validate_control_node() {
    local control_ip=$(get_local_ip)
    local ip_found=0
    
    log_message INFO "Control node IP: $control_ip"
    
    for server_ip in "${ALL_SERVER_IPS[@]}"; do
        if [ "$control_ip" = "$server_ip" ]; then
            ip_found=1
            break
        fi
    done
    
    if [ $ip_found -eq 1 ]; then
        error_exit "❌ ERROR: Control node ($control_ip) cannot be part of cluster nodes!
        
Please run this script from a DIFFERENT machine that is NOT in the cluster.

Current configuration:
$(printf '%s\n' "${ALL_SERVER_IPS[@]}" | nl -v1 -w1 -s'. IP: ')

The machine where you run this script must have SSH access to all cluster nodes above.
        "
    fi
    
    log_message SUCCESS "Control node validation OK (not in cluster)"
}

################################################################################
# CONNECTIVITY CHECKS
################################################################################

ping_check() {
    local ip=$1
    local max_attempts=3
    
    for ((i=1; i<=max_attempts; i++)); do
        if ping -c 1 -W 2 "$ip" &> /dev/null; then
            return 0
        fi
    done
    return 1
}

ping_all_servers() {
    log_message INFO "Checking connectivity to all servers..."
    local failed_ips=()
    
    for ip in "${ALL_SERVER_IPS[@]}"; do
        if ping_check "$ip"; then
            log_message SUCCESS "✓ $ip is reachable"
        else
            log_message WARN "✗ $ip is NOT reachable"
            failed_ips+=("$ip")
        fi
    done
    
    if [ ${#failed_ips[@]} -gt 0 ]; then
        error_exit "Cannot reach the following IPs: ${failed_ips[*]}"
    fi
    
    log_message SUCCESS "All servers are reachable"
}

check_ssh_connectivity() {
    local ip=$1
    local user="${2:-$SSH_USER}"
    local key="${3:-$SSH_KEY_PATH}"
    
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i "$key" "${user}@${ip}" "echo 'SSH OK'" &> /dev/null; then
        return 1
    fi
    return 0
}

verify_all_ssh_connectivity() {
    log_message INFO "Verifying SSH connectivity to all cluster nodes..."
    local failed_ips=()
    
    for ip in "${ALL_SERVER_IPS[@]}"; do
        if check_ssh_connectivity "$ip"; then
            log_message SUCCESS "✓ SSH connection to $ip OK"
        else
            log_message WARN "✗ SSH connection to $ip FAILED"
            failed_ips+=("$ip")
        fi
    done
    
    if [ ${#failed_ips[@]} -gt 0 ]; then
        error_exit "SSH connection failed to: ${failed_ips[*]}
        
Check:
1. SSH_KEY_PATH is correct: $SSH_KEY_PATH
2. SSH_USER is correct: $SSH_USER
3. SSH port is correct: $SSH_PORT
4. SSH key permissions (should be 600): $(ls -la $SSH_KEY_PATH 2>/dev/null || echo 'NOT FOUND')"
    fi
    
    log_message SUCCESS "SSH connectivity verified for all nodes"
}

################################################################################
# CONFIG VALIDATION
################################################################################

validate_config() {
    log_message INFO "Validating configuration..."
    
    # Check minimum number of IPs
    local ip_count=${#ALL_SERVER_IPS[@]}
    if [ "$ip_count" -lt 4 ]; then
        error_exit "❌ Insufficient servers!
        
Minimum requirement: 4 servers (3 for MySQL cluster + 1 for ProxySQL)
You provided: $ip_count servers

Please add at least $((4 - ip_count)) more server IP(s) to cluster-config.sh"
    fi
    
    if [ "$ip_count" -gt 6 ]; then
        log_message WARN "You provided $ip_count IPs (> 6). Will use first 4: MySQL (3) + ProxySQL (1)"
    fi
    
    # Validate IP format
    for ip in "${ALL_SERVER_IPS[@]}"; do
        if ! validate_ip "$ip"; then
            error_exit "Invalid IP format: $ip"
        fi
    done
    
    # Check SSH key exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        error_exit "SSH key not found: $SSH_KEY_PATH"
    fi
    
    # Check SSH key permissions
    local key_perms=$(stat -f%A "$SSH_KEY_PATH" 2>/dev/null || stat -c %a "$SSH_KEY_PATH" 2>/dev/null)
    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
        log_message WARN "SSH key permissions are $key_perms (should be 600). Attempting to fix..."
        chmod 600 "$SSH_KEY_PATH" || error_exit "Cannot fix SSH key permissions"
    fi
    
    log_message SUCCESS "Configuration validation passed"
}

################################################################################
# AUTO-ASSIGNMENT LOGIC
################################################################################

parse_server_config() {
    log_message INFO "Parsing server configuration..."
    
    # Assign first 3 IPs to MySQL cluster
    MYSQL_NODES=(
        "${ALL_SERVER_IPS[0]}"
        "${ALL_SERVER_IPS[1]}"
        "${ALL_SERVER_IPS[2]}"
    )
    
    # Assign 4th IP to ProxySQL
    PROXYSQL_IP="${ALL_SERVER_IPS[3]}"
    
    # Generate node names
    MYSQL_NODE_NAMES=(
        "mysql-node-1"
        "mysql-node-2"
        "mysql-node-3"
    )
    
    # Build Galera cluster address
    GALERA_CLUSTER_ADDRESS="gcomm://${MYSQL_NODES[0]},${MYSQL_NODES[1]},${MYSQL_NODES[2]}"
    
    log_message SUCCESS "Server configuration parsed:"
    log_message INFO "  MySQL Cluster (3 nodes):"
    for i in "${!MYSQL_NODES[@]}"; do
        log_message INFO "    ${MYSQL_NODE_NAMES[$i]}: ${MYSQL_NODES[$i]}"
    done
    log_message INFO "  ProxySQL Server: $PROXYSQL_IP"
    
    if [ ${#ALL_SERVER_IPS[@]} -gt 4 ]; then
        log_message WARN "Extra IPs provided (beyond 4) will be ignored:"
        for i in $(seq 4 $((${#ALL_SERVER_IPS[@]} - 1))); do
            log_message INFO "    Ignored: ${ALL_SERVER_IPS[$i]}"
        done
    fi
    
    export MYSQL_NODES PROXYSQL_IP MYSQL_NODE_NAMES GALERA_CLUSTER_ADDRESS
}

################################################################################
# FIREWALL MANAGEMENT
################################################################################

detect_firewall() {
    FIREWALL_TYPE="none"
    
    if command -v ufw &> /dev/null; then
        if systemctl is-active --quiet ufw; then
            FIREWALL_TYPE="ufw"
            log_message SUCCESS "Detected UFW firewall (Ubuntu)"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            FIREWALL_TYPE="firewalld"
            log_message SUCCESS "Detected firewalld (Rocky Linux)"
        fi
    fi
    
    if [ "$FIREWALL_TYPE" = "none" ]; then
        log_message INFO "No active firewall detected"
    fi
    
    export FIREWALL_TYPE
}

open_firewall_ports_mysql() {
    if [ "$AUTO_OPEN_FIREWALL" != "true" ]; then
        log_message INFO "Skipping firewall configuration (AUTO_OPEN_FIREWALL=false)"
        return 0
    fi
    
    if [ "$FIREWALL_TYPE" = "none" ]; then
        log_message INFO "No firewall to configure"
        return 0
    fi
    
    log_message INFO "Opening firewall ports for MySQL cluster..."
    
    local ports=($MYSQL_PORT $GALERA_PORT $IST_PORT $XTRABACKUP_PORT)
    
    if [ "$FIREWALL_TYPE" = "ufw" ]; then
        for port in "${ports[@]}"; do
            if ufw allow "$port/tcp" &> /dev/null; then
                log_message SUCCESS "  Opened UFW port $port/tcp"
            fi
        done
    elif [ "$FIREWALL_TYPE" = "firewalld" ]; then
        for port in "${ports[@]}"; do
            if firewall-cmd --permanent --add-port="$port/tcp" &> /dev/null; then
                log_message SUCCESS "  Opened firewalld port $port/tcp"
            fi
        done
        firewall-cmd --reload &> /dev/null
    fi
}

open_firewall_ports_proxysql() {
    if [ "$AUTO_OPEN_FIREWALL" != "true" ]; then
        return 0
    fi
    
    if [ "$FIREWALL_TYPE" = "none" ]; then
        return 0
    fi
    
    log_message INFO "Opening firewall ports for ProxySQL..."
    
    local ports=($PROXYSQL_ADMIN_PORT $PROXYSQL_APP_PORT)
    
    if [ "$FIREWALL_TYPE" = "ufw" ]; then
        for port in "${ports[@]}"; do
            if ufw allow "$port/tcp" &> /dev/null; then
                log_message SUCCESS "  Opened UFW port $port/tcp"
            fi
        done
    elif [ "$FIREWALL_TYPE" = "firewalld" ]; then
        for port in "${ports[@]}"; do
            if firewall-cmd --permanent --add-port="$port/tcp" &> /dev/null; then
                log_message SUCCESS "  Opened firewalld port $port/tcp"
            fi
        done
        firewall-cmd --reload &> /dev/null
    fi
}

################################################################################
# SSH EXECUTION
################################################################################

remote_execute() {
    local ip=$1
    local user="${2:-$SSH_USER}"
    local key="${3:-$SSH_KEY_PATH}"
    shift 3
    local command="$@"
    
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$key" "${user}@${ip}" "$command"
}

transfer_file() {
    local local_path=$1
    local remote_ip=$2
    local remote_path=$3
    local user="${4:-$SSH_USER}"
    local key="${5:-$SSH_KEY_PATH}"
    
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$key" "$local_path" "${user}@${remote_ip}:${remote_path}"
}

################################################################################
# MYSQL VERIFICATION
################################################################################

check_galera_status() {
    local ip=$1
    local user="${2:-root}"
    local password="${3:-$MYSQL_ROOT_PASSWORD}"
    
    mysql -h "$ip" -u "$user" -p"$password" -N -s -e \
        "SHOW STATUS LIKE 'wsrep%';" 2>/dev/null || return 1
}

verify_cluster_sync() {
    log_message INFO "Verifying Galera cluster synchronization..."
    
    local all_synced=0
    for ip in "${MYSQL_NODES[@]}"; do
        log_message INFO "Checking node: $ip"
        
        local wsrep_status=$(check_galera_status "$ip" | grep wsrep_ready | awk '{print $NF}')
        local wsrep_connected=$(check_galera_status "$ip" | grep wsrep_connected | awk '{print $NF}')
        
        if [ "$wsrep_status" = "ON" ] && [ "$wsrep_connected" = "ON" ]; then
            log_message SUCCESS "  Node $ip is synced"
        else
            log_message WARN "  Node $ip sync status: ready=$wsrep_status, connected=$wsrep_connected"
            all_synced=1
        fi
    done
    
    return $all_synced
}

################################################################################
# DEPLOYMENT REPORT GENERATION
################################################################################

generate_deployment_report() {
    local report_file="cluster-deployment-report.sh"
    
    log_message INFO "Generating deployment report: $report_file"
    
    cat > "$report_file" << 'EOF'
#!/bin/bash
################################################################################
# MySQL Percona XtraDB Cluster + ProxySQL Deployment Report
# GENERATED REPORT - Contains credentials and system information
# ⚠️  KEEP THIS FILE SAFE - CONTAINS SENSITIVE INFORMATION
################################################################################

# Auto-generated on: $(date)
# Cluster Name: ${CLUSTER_NAME}
# MySQL Version: ${MYSQL_VERSION}

## ========== CLUSTER CONFIGURATION ==========
export CLUSTER_NAME="${CLUSTER_NAME}"
export MYSQL_VERSION="${MYSQL_VERSION}"
export MYSQL_NODE_COUNT=3

export MYSQL_NODES=(
    "${MYSQL_NODES[0]}"     # mysql-node-1
    "${MYSQL_NODES[1]}"     # mysql-node-2
    "${MYSQL_NODES[2]}"     # mysql-node-3
)

export MYSQL_NODE_NAMES=(
    "mysql-node-1"
    "mysql-node-2"
    "mysql-node-3"
)

export PROXYSQL_IP="${PROXYSQL_IP}"
export GALERA_CLUSTER_ADDRESS="${GALERA_CLUSTER_ADDRESS}"

## ========== CREDENTIALS ==========
export MYSQL_ROOT_USER="root"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
export MYSQL_APP_USER="${MYSQL_APP_USER}"
export MYSQL_APP_PASSWORD="${MYSQL_APP_PASSWORD}"
export MYSQL_REPLICATION_USER="${MYSQL_REPLICATION_USER}"
export MYSQL_REPLICATION_PASSWORD="${MYSQL_REPLICATION_PASSWORD}"
export PROXYSQL_MONITOR_USER="${PROXYSQL_MONITOR_USER}"
export PROXYSQL_MONITOR_PASSWORD="${PROXYSQL_MONITOR_PASSWORD}"

## ========== PORTS ==========
export MYSQL_PORT=${MYSQL_PORT}
export GALERA_PORT=${GALERA_PORT}
export IST_PORT=${IST_PORT}
export XTRABACKUP_PORT=${XTRABACKUP_PORT}
export PROXYSQL_ADMIN_PORT=${PROXYSQL_ADMIN_PORT}
export PROXYSQL_APP_PORT=${PROXYSQL_APP_PORT}

## ========== VERIFICATION COMMANDS ==========

# Check MySQL Cluster Status
mysql_cluster_status() {
    echo "=== MySQL Cluster Status ==="
    for i in "${!MYSQL_NODES[@]}"; do
        echo -e "\n--- ${MYSQL_NODE_NAMES[$i]}: ${MYSQL_NODES[$i]} ---"
        mysql -h"${MYSQL_NODES[$i]}" -u"$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" \
            -e "SHOW STATUS LIKE 'wsrep%';" 2>/dev/null || echo "Connection failed"
    done
}

# Check ProxySQL Status
proxysql_status() {
    echo "=== ProxySQL Backend Servers ==="
    mysql -h"$PROXYSQL_IP" -P"$PROXYSQL_ADMIN_PORT" -u"admin" -padmin \
        -e "SELECT hostgroup_id, hostname, port, status FROM mysql_servers;" 2>/dev/null || echo "Connection failed"
}

# Test query through ProxySQL
test_proxysql_query() {
    echo "=== Test Query via ProxySQL (App Port) ==="
    mysql -h"$PROXYSQL_IP" -P"$PROXYSQL_APP_PORT" -u"$MYSQL_APP_USER" -p"$MYSQL_APP_PASSWORD" \
        -e "SELECT 'ProxySQL Connection OK' AS status;" 2>/dev/null || echo "Connection failed"
}

# SSH to nodes
ssh_to_node() {
    local node_num=$1
    local ip="${MYSQL_NODES[$((node_num - 1))]}"
    echo "ssh -i /path/to/ssh/key root@$ip"
}

# Backup example
xtrabackup_example() {
    echo "=== XtraBackup Commands ==="
    echo "# Full backup:"
    echo "innobackupex --user='$MYSQL_ROOT_USER' --password='$MYSQL_ROOT_PASSWORD' \\"
    echo "  --host='${MYSQL_NODES[0]}' --port=$MYSQL_PORT /path/to/backup/dir"
    echo ""
    echo "# Prepare:"
    echo "innobackupex --apply-log /path/to/backup/dir"
    echo ""
    echo "# Restore:"
    echo "innobackupex --copy-back /path/to/backup/dir"
}

export -f mysql_cluster_status proxysql_status test_proxysql_query ssh_to_node xtrabackup_example

echo "Deployment report loaded. Available functions:"
echo "  - mysql_cluster_status      : Check cluster sync status"
echo "  - proxysql_status           : Check ProxySQL backends"
echo "  - test_proxysql_query       : Test connection via ProxySQL"
echo "  - ssh_to_node <num>         : SSH command to specific node"
echo "  - xtrabackup_example        : Show backup examples"
EOF

    log_message SUCCESS "Deployment report created: $report_file"
}

################################################################################
# EXPORT FUNCTIONS FOR USE
################################################################################

export -f log_message error_exit detect_os validate_ip get_local_ip
export -f validate_control_node ping_check ping_all_servers check_ssh_connectivity
export -f verify_all_ssh_connectivity validate_config parse_server_config
export -f detect_firewall open_firewall_ports_mysql open_firewall_ports_proxysql
export -f remote_execute transfer_file check_galera_status verify_cluster_sync
export -f generate_deployment_report

# Export variables
export LOG_FILE RED GREEN YELLOW BLUE NC
