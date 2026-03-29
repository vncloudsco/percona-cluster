#!/bin/bash
################################################################################
# Cluster Health Check Script
# =============================================================================
# This script monitors the health of the Percona XtraDB Cluster and ProxySQL
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

HEALTH_CHECK_LOG="cluster-health-check-$(date +%Y%m%d_%H%M%S).log"

################################################################################
# HEALTH CHECK FUNCTIONS
################################################################################

check_mysql_nodes() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         MySQL Cluster Nodes Status                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    printf "%-20s %-20s %-15s %-15s\n" "NODE NAME" "IP ADDRESS" "SERVICE" "GALERA"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for i in "${!MYSQL_NODES[@]}"; do
        local ip="${MYSQL_NODES[$i]}"
        local name="${MYSQL_NODE_NAMES[$i]}"
        
        # Check if MySQL is running
        local status="❌ DOWN"
        if ping_check "$ip"; then
            if remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" \
                "systemctl is-active --quiet mysql || systemctl is-active --quiet mysqld" 2>/dev/null; then
                status="✓ RUNNING"
            fi
        fi
        
        # Check Galera status
        local galera_status="⚠ UNKNOWN"
        if [ "$status" = "✓ RUNNING" ]; then
            local wsrep_ready=$(remote_execute "$ip" "$SSH_USER" "$SSH_KEY_PATH" \
                "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"SHOW STATUS LIKE 'wsrep_ready\\G'\" 2>/dev/null | grep Value | awk '{print \$NF}'" \
                2>/dev/null || echo "UNKNOWN")
            
            if [ "$wsrep_ready" = "ON" ]; then
                galera_status="✓ SYNCED"
            elif [ "$wsrep_ready" = "OFF" ]; then
                galera_status="⚠ NOT SYNCED"
            fi
        fi
        
        printf "%-20s %-20s %-15s %-15s\n" "$name" "$ip" "$status" "$galera_status"
    done
    echo ""
}

check_galera_details() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Galera Cluster Details                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    local primary_ip="${MYSQL_NODES[0]}"
    
    echo "Cluster Information (from primary node: $primary_ip)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    mysql -h "$primary_ip" -u root -p"${MYSQL_ROOT_PASSWORD}" -N -s -e \
        "SHOW STATUS LIKE 'wsrep%';" 2>/dev/null | while read key value; do
        printf "%-40s : %s\n" "$key" "$value"
    done
    
    echo ""
}

check_proxysql_status() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         ProxySQL Status                                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! ping_check "$PROXYSQL_IP"; then
        echo "⚠ ProxySQL server ($PROXYSQL_IP) is not reachable"
        echo ""
        return 1
    fi
    
    # Check if ProxySQL service is running
    if remote_execute "$PROXYSQL_IP" "$SSH_USER" "$SSH_KEY_PATH" \
        "systemctl is-active --quiet proxysql" 2>/dev/null; then
        echo "✓ ProxySQL Service Status: RUNNING"
    else
        echo "❌ ProxySQL Service Status: STOPPED"
        echo ""
        return 1
    fi
    
    echo ""
    echo "Backend MySQL Servers:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-20s %-20s %-10s %-15s\n" "HOSTNAME" "PORT" "WEIGHT" "STATUS"
    echo "────────────────────────────────────────────────────────────"
    
    mysql -h "$PROXYSQL_IP" -P "$PROXYSQL_ADMIN_PORT" -u admin -padmin -N -s -e \
        "SELECT hostname, port, weight, status FROM mysql_servers;" 2>/dev/null | \
        while read hostname port weight status; do
        local status_symbol="❌"
        [ "$status" = "ONLINE" ] && status_symbol="✓"
        printf "%-20s %-20s %-10s %-15s\n" "$hostname" "$port" "$weight" "$status_symbol $status"
    done || {
        echo "⚠ Could not connect to ProxySQL admin interface"
    }
    
    echo ""
}

check_connectivity() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Network Connectivity                            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    printf "%-20s %-20s %-15s\n" "TYPE" "IP ADDRESS" "PING STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check MySQL nodes
    for i in "${!MYSQL_NODES[@]}"; do
        local status="❌ UNREACHABLE"
        ping_check "${MYSQL_NODES[$i]}" && status="✓ REACHABLE"
        printf "%-20s %-20s %-15s\n" "MySQL Node $((i+1))" "${MYSQL_NODES[$i]}" "$status"
    done
    
    # Check ProxySQL
    local status="❌ UNREACHABLE"
    ping_check "$PROXYSQL_IP" && status="✓ REACHABLE"
    printf "%-20s %-20s %-15s\n" "ProxySQL" "$PROXYSQL_IP" "$status"
    
    echo ""
}

check_ports() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Open Ports (on MySQL primary node)              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    local primary_ip="${MYSQL_NODES[0]}"
    
    printf "%-15s %-15s %-20s\n" "PORT" "SERVICE" "STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for port in $MYSQL_PORT $GALERA_PORT $IST_PORT $XTRABACKUP_PORT; do
        local service="Unknown"
        local status="❌"
        
        case $port in
            $MYSQL_PORT) service="MySQL" ;;
            $GALERA_PORT) service="Galera Replication" ;;
            $IST_PORT) service="Galera IST" ;;
            $XTRABACKUP_PORT) service="XtraBackup" ;;
        esac
        
        if remote_execute "$primary_ip" "$SSH_USER" "$SSH_KEY_PATH" \
            "netstat -tlnp 2>/dev/null | grep -q ':$port ' || ss -tlnp 2>/dev/null | grep -q ':$port '" 2>/dev/null; then
            status="✓"
        fi
        
        printf "%-15s %-15s %-20s\n" "$port" "$service" "$status"
    done
    
    echo ""
}

check_disk_space() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Disk Space (on MySQL primary node)              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    local primary_ip="${MYSQL_NODES[0]}"
    
    printf "%-30s %-15s %-15s %-15s\n" "FILESYSTEM" "SIZE" "USED" "AVAILABLE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    remote_execute "$primary_ip" "$SSH_USER" "$SSH_KEY_PATH" \
        "df -h | grep -E '^/' | head -5" 2>/dev/null || echo "Could not get disk info"
    
    echo ""
}

show_summary() {
    cat << EOF
═════════════════════════════════════════════════════════════════════════════════
                      Health Check Summary
═════════════════════════════════════════════════════════════════════════════════

Interpretation:
  ✓  = Healthy/Online
  ⚠  = Warning (degraded but operational)
  ❌ = Error (offline or failed)

Next Steps:
  1. If any node is offline, check system logs: journalctl -u mysql
  2. If Galera is not synced, verify network connectivity between nodes
  3. If ProxySQL backends are offline, check MySQL user permissions
  4. For detailed MySQL status: mysql -h <ip> -u root -p<password> -e "SHOW STATUS LIKE 'wsrep%';"

═════════════════════════════════════════════════════════════════════════════════
EOF
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    {
        echo "╔═════════════════════════════════════════════════════════════════════════╗"
        echo "║              Cluster Health Check Report                                ║"
        echo "║              Generated: $(date '+%Y-%m-%d %H:%M:%S')                       ║"
        echo "╚═════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Load config
        detect_os
        parse_server_config
        
        # Run checks
        check_mysql_nodes
        check_galera_details
        check_proxysql_status
        check_connectivity
        check_ports
        check_disk_space
        show_summary
        
    } 2>&1 | tee "$HEALTH_CHECK_LOG"
    
    log_message SUCCESS "Health check report saved to: $HEALTH_CHECK_LOG"
}

# Run main
main
