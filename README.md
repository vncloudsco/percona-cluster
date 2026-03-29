# Percona XtraDB Cluster + ProxySQL - Automated Installation

**Version**: 1.0  
**Last Updated**: March 2026  
**Supported OS**: Ubuntu 20.04/22.04 LTS, Rocky Linux 8/9

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Configuration Guide](#configuration-guide)
6. [Installation Steps](#installation-steps)
7. [Verification & Testing](#verification--testing)
8. [Operations & Maintenance](#operations--maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Security Best Practices](#security-best-practices)
11. [FAQ](#faq)

---

## 📚 Overview

This project provides fully automated bash scripts to deploy a **Percona XtraDB Cluster** (3 MySQL nodes) with **ProxySQL** load balancer.

**Key Features**:
- ✅ Automated multi-node MySQL cluster setup
- ✅ SSH-based remote deployment
- ✅ Auto-firewall detection and port opening
- ✅ XtraBackup pre-installed and documented
- ✅ Deployment report generation
- ✅ Health check monitoring
- ✅ Cross-platform support (Ubuntu + Rocky Linux)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Node                             │
│              (Where you run the scripts)                    │
└────────┬────────────────────────────────────────────────────┘
         │ SSH Deploy & SSH Manage
         │
    ┌────┴────────────────────────────────────────────────────┐
    │                                                          │
┌───▼─────┐      ┌─────────┐      ┌──────────┐     ┌────────┐
│ MySQL   │◄────►│ MySQL   │◄────►│ MySQL    │     │ProxySQL│
│Node-1   │      │ Node-2  │      │ Node-3   │     │        │
│Primary  │      │Secondary│      │Secondary │     │        │
│(3306)   │      │(3306)   │      │(3306)    │     │(6033)  │
└────▲────┘      └─────────┘      └──────────┘     └────────┘
     │ Galera Replication (Port 4567)
     │ IST Incremental (Port 4568)
     │ XtraBackup (Port 4444)
```

**Components**:
- **MySQL Cluster (3 nodes)**: Percona Server 8.0 with Galera replication
- **ProxySQL**: Load balancer + connection pooling (failover transparent)
- **XtraBackup**: Pre-installed for backup/recovery operations

---

## 📋 Prerequisites

### Control Node (Where You Run Scripts)
- Linux machine with SSH client
- Bash 4.0+
- SSH key-pair (already generated or will generate)
- Network access to all cluster nodes

### Cluster Nodes (Minimum 4 servers)
- **3 servers** for MySQL XtraDB Cluster
- **1 server** for ProxySQL
- **Supported OS**: Ubuntu 20.04/22.04 LTS OR Rocky Linux 8/9
- **Minimum specs per node**:
  - 2 vCPU
  - 4 GB RAM (8 GB recommended)
  - 20 GB disk space
- **Network**: Private network between nodes (recommended)
- **Sudo access** via SSH key (required)
- **Firewall**: Either ufw (Ubuntu) or firewalld (Rocky) - will be auto-configured
- **No services on ports**: 3306, 4567, 4568, 4444, 6032, 6033

### SSH Key Setup

If you don't have an SSH key pair:

```bash
# On your control node
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Copy public key to all cluster nodes
for ip in 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.20; do
    ssh-copy-id -i ~/.ssh/id_rsa.pub root@$ip
done
```

---

## 🚀 Quick Start

### 1. Prepare Configuration

Edit `cluster-config.sh` and fill in **4-6 server IPs**:

```bash
vim cluster-config.sh
```

Change this section:
```bash
ALL_SERVER_IPS=(
    "192.168.1.10"    # Node 1 - MySQL
    "192.168.1.11"    # Node 2 - MySQL
    "192.168.1.12"    # Node 3 - MySQL
    "192.168.1.20"    # Node 4 - ProxySQL
)
```

And update passwords (search for "change_me"):
```bash
MYSQL_ROOT_PASSWORD="your_strong_password_here"
```

### 2. Make Deploy Script Executable

```bash
chmod +x deploy-cluster.sh
```

### 3. Run ONE-CLICK Deployment

```bash
./deploy-cluster.sh
```

**That's it!** This single script will:
- ✓ Validate configuration (4+ servers, IPs, SSH keys)
- ✓ Check network connectivity (ping + SSH verification)
- ✓ Install MySQL Cluster on 3 nodes (auto-configure Galera)
- ✓ Initialize primary node and join secondaries
- ✓ Install ProxySQL with load balancing
- ✓ Create remote access user (can connect from anywhere)
- ✓ Configure monitoring and health checks
- ✓ Open firewall ports automatically
- ✓ Generate complete connection information file
- ✓ Run final health check
- ✓ Display all credentials and connection strings

**Expected time**: 15-20 minutes total

### 4. After Deployment Completes

The script will save connection information to `cluster-connection-info.txt`:

```bash
# View connection details
cat cluster-connection-info.txt
```

This file contains:
- ✓ Remote user credentials (for applications)
- ✓ Admin credentials (for management)
- ✓ Connection strings (MySQL, PHP, Node.js, Python, Java)
- ✓ All server IPs and ports
- ✓ Verification commands
- ✓ Common operations (backup, health check, etc)

### 5. Quick Test - Connect Using Remote User

```bash
# Test remote application connection
mysql -h 192.168.1.20 -P 6033 -u appremote -p<password> -e "SELECT 'ProxySQL Connected' AS status;"

# Or load and use provided functions
source cluster-deployment-report.sh
mysql_cluster_status
proxysql_status
test_proxysql_query
```

---

## 🔧 Configuration Guide

### cluster-config.sh Structure

The config file has 3 main sections:

#### Section 1: Server IPs (REQUIRED)

```bash
ALL_SERVER_IPS=(
    "192.168.1.10"    # Server 1 → Will be mysql-node-1 (Primary)
    "192.168.1.11"    # Server 2 → Will be mysql-node-2 (Secondary)
    "192.168.1.12"    # Server 3 → Will be mysql-node-3 (Secondary)
    "192.168.1.20"    # Server 4 → Will be ProxySQL
)
```

**Rules**:
- Minimum 4 IPs (3 for MySQL + 1 for ProxySQL)
- Maximum any number (extra IPs ignored)
- **CANNOT include the IP of control node** (where script runs)
- Must be on same network (recommend private network)

#### Section 2: Credentials (RECOMMENDED TO CHANGE)

```bash
MYSQL_ROOT_PASSWORD="change_me_strong_password_123"
MYSQL_APP_USER="appuser"
MYSQL_APP_PASSWORD="app_password_456"
```

**Best practices**:
- Use strong passwords (mix uppercase, lowercase, numbers, symbols)
- Store credentials securely (not in git)
- Rotate passwords periodically

#### Section 3: Remote Access User (NEW - for applications)

```bash
# User that can connect from ANYWHERE (%)
# Use this in your application code
REMOTE_USER="appremote"
REMOTE_PASSWORD="remote_password_456"
```

**Important**:
- This user can connect from ANY IP (not restricted to cluster network)
- Use via ProxySQL: `mysql -h PROXYSQL_IP -P 6033 -u appremote -pPASSWORD`
- Ideal for application servers, microservices, remote clients
- Has SELECT, INSERT, UPDATE, DELETE permissions
- Does NOT have administrative privileges (safe for apps)

#### Section 4: SSH Configuration

```bash
SSH_USER="root"
SSH_KEY_PATH="/root/.ssh/id_rsa"
SSH_PORT=22
```

**Notes**:
- SSH_USER must have sudo privileges
- SSH_KEY_PATH is path to **private key**, not public
- Adjust SSH_PORT if your servers use non-standard port

#### Section 5: Firewall (OPTIONAL)

```bash
AUTO_OPEN_FIREWALL=true    # Set false if you manage firewall manually
MINIMAL_FIREWALL_RULE=true # Only open required ports
```

---

## 📦 Installation Steps

#### Step 1: Prepare Control Node

```bash
# Download/clone the scripts
cd /path/to/cluster
ls -la *.sh

# Verify key files exist:
# - cluster-config.sh
# - lib-functions.sh
# - deploy-cluster.sh  ⭐ Main deployment script
# - health-check.sh
# - README.md
```

#### Step 2: Configure IPs and Passwords

```bash
# Edit config - ONLY THIS FILE
nano cluster-config.sh

# Required changes:
# 1. Fill ALL_SERVER_IPS with 4-6 server IPs
# 2. Change MYSQL_ROOT_PASSWORD
# 3. Change REMOTE_PASSWORD (for applications)
# Optional changes:
# 4. SSH_KEY_PATH (if different)
# 5. SSH_USER (if not root)

# Verify servers are reachable
ping 192.168.1.10
ping 192.168.1.11
ping 192.168.1.12
ping 192.168.1.20
```

#### Step 3: Test SSH Connectivity

```bash
# Test SSH to each server
ssh -i ~/.ssh/id_rsa root@192.168.1.10 "echo OK"
ssh -i ~/.ssh/id_rsa root@192.168.1.11 "echo OK"
ssh -i ~/.ssh/id_rsa root@192.168.1.12 "echo OK"
ssh -i ~/.ssh/id_rsa root@192.168.1.20 "echo OK"

# All should return "OK"
```

#### Step 4: Make Deploy Script Executable

```bash
chmod +x deploy-cluster.sh
```

#### Step 5: RUN COMPLETE DEPLOYMENT ⭐

```bash
./deploy-cluster.sh
```

**This ONE script will:**
- Validate all configuration
- Display deployment plan (ask confirmation)
- Install MySQL Cluster (3 nodes) ~5-10 min
- Install ProxySQL ~2-3 min
- Create remote access user
- Configure firewall
- Generate connection info file
- Run health check
- Display all credentials

**Monitor output:**
- Watch progress (colored output: INFO=blue, SUCCESS=green, ERROR=red)
- Script asks for final confirmation - type "YES" to proceed
- Installation logs saved to `/tmp/cluster-deployment-*.log`
- Connection info saved to `cluster-connection-info.txt`

#### Step 6: Access Cluster Information

```bash
# View connection information
cat cluster-connection-info.txt

# File contains:
# - Remote user (for applications)
# - Admin credentials
# - Connection strings (MySQL, PHP, Node.js, Python, Java)
# - All server IPs and ports
```

**That's it! ✅ Entire cluster is ready to use.**

---

## ✅ Verification & Testing

### Post-Installation Checklists

#### MySQL Cluster Status

```bash
# Check primary node
mysql -h 192.168.1.10 -u root -p<password> -e \
  "SHOW STATUS LIKE 'wsrep%';" 

# Check wsrep_cluster_size = 3
# Check wsrep_ready = ON
# Check wsrep_connected = ON
```

#### Verify Data Replication

```bash
# Create test database on primary
mysql -h 192.168.1.10 -u root -p<password> << EOF
CREATE DATABASE test_replication;
USE test_replication;
CREATE TABLE test (id INT, msg TEXT);
INSERT INTO test VALUES (1, 'Hello from primary');
EOF

# Check on secondary nodes
mysql -h 192.168.1.11 -u root -p<password> -e \
  "SELECT * FROM test_replication.test;"
```

Should see the data replicated immediately.

#### ProxySQL Connectivity

```bash
# Connect through ProxySQL app port
mysql -h 192.168.1.20 -P 6033 -u appuser -p<password> -e \
  "SELECT 'Connected via ProxySQL' AS status;"

# Connect to admin interface
mysql -h 192.168.1.20 -P 6032 -u admin -padmin -e \
  "SELECT * FROM mysql_servers;"

# All 3 backends should show ONLINE status
```

#### Health Check Report

```bash
./health-check.sh
```

Expected output:
- All MySQL nodes: ✓ RUNNING
- All Galera nodes: ✓ SYNCED
- ProxySQL: ✓ RUNNING
- All backends: ✓ ONLINE

---

## 🔧 Operations & Maintenance

### User Management

#### Creating New Database User

```bash
mysql -h 192.168.1.10 -u root -p<password> << EOF
CREATE USER 'newuser'@'%' IDENTIFIED BY 'newpassword';
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'newuser'@'%';
FLUSH PRIVILEGES;
EOF

# User automatically replicates to all nodes
```

#### Using Remote Application User

The `appremote` user is created automatically during deployment and can connect from ANYWHERE:

```bash
# Test connection (from any computer)
mysql -h 192.168.1.20 -P 6033 -u appremote -p<REMOTE_PASSWORD> -e "SELECT 'Connected via ProxySQL' AS status;"

# Create application database
mysql -h 192.168.1.20 -P 6033 -u appremote -p<REMOTE_PASSWORD> << EOF
CREATE DATABASE myapp_db;
USE myapp_db;
CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100));
INSERT INTO users (name) VALUES ('John'), ('Jane');
EOF

# Query from phone, IoT device, or remote server
mysql -h 192.168.1.20 -P 6033 -u appremote -p<REMOTE_PASSWORD> -e "SELECT * FROM myapp_db.users;"
```

**Application Code Examples:**

PHP (Laravel):
```php
'mysql' => [
    'driver' => 'mysql',
    'host' => '192.168.1.20',
    'port' => 6033,
    'database' => 'myapp_db',
    'username' => 'appremote',
    'password' => 'remote_password_456',
],
```

Node.js (mysql2):
```javascript
const mysql = require('mysql2/promise');
const connection = await mysql.createConnection({
  host: '192.168.1.20',
  port: 6033,
  user: 'appremote',
  password: 'remote_password_456',
  database: 'myapp_db'
});
```

Python (pymysql):
```python
import pymysql
conn = pymysql.connect(
    host='192.168.1.20',
    port=6033,
    user='appremote',
    password='remote_password_456',
    database='myapp_db'
)
```

#### Resetting Passwords

```bash
# On primary node
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'newpassword';"
```

### Backup & Recovery

#### Full Backup with XtraBackup

```bash
# On any MySQL node
innobackupex --user=root --password=<password> \
  --host=192.168.1.10 --port=3306 /backup/mysql-$(date +%Y%m%d)/

# Prepare backup (make it consistent)
innobackupex --apply-log /backup/mysql-YYYYMMDD/
```

#### Restore from Backup

```bash
# Stop MySQL
systemctl stop mysql

# Restore backup
innobackupex --copy-back /backup/mysql-YYYYMMDD/

# Fix permissions
chown -R mysql:mysql /var/lib/mysql

# Start MySQL
systemctl start mysql
```

#### Automated Daily Backups (Cron)

```bash
# Add to crontab
crontab -e

# Add this line (backup at 2 AM daily)
0 2 * * * /usr/bin/innobackupex --user=root --password=<password> --host=127.0.0.1 /backups/$(date +\%Y\%m\%d)

# Keep only last 7 days
0 3 * * * find /backups -mtime +7 -exec rm -rf {} \;
```

### Monitoring

#### Check Cluster Health

```bash
./health-check.sh

# Or manually
mysql -h 192.168.1.10 -u root -p -e "SHOW STATUS LIKE 'wsrep%';"
mysql -h 192.168.1.20 -P 6032 -u admin -padmin \
  -e "SELECT * FROM mysql_servers;"
```

#### Monitor Replication Lag

```bash
mysql -h 192.168.1.10 -u root -p -e \
  "SHOW STATUS LIKE 'wsrep_local_recv_queue';" 

# Should be 0 (no lag)
```

#### Monitor ProxySQL Connections

```bash
mysql -h 192.168.1.20 -P 6032 -u admin -padmin \
  -e "SELECT * FROM stats_mysql_global;"
```

### Node Recovery

#### If a Node Goes Down

```bash
# ProxySQL automatically removes offline node
# Applications fail over to other nodes transparently

# To bring node back online:
# 1. Fix the issue on that node
# 2. Start MySQL:
systemctl start mysql

# 3. Node auto-joins cluster (SST - full state transfer)
# 4. Verify:
./health-check.sh
```

#### If Primary Node Fails

```bash
# Secondary nodes continue (no single point of failure)
# One secondary is automatically promoted
# No manual action needed

# Verify cluster health:
mysql -h 192.168.1.11 -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
# Should still be 3 (or 2 if second node also down)
```

---

## 🔍 Troubleshooting

### Common Issues

#### Problem: "Cannot reach server IP"

**Solution**:
```bash
# 1. Check network connectivity
ping <ip>

# 2. Check SSH
ssh -i ~/.ssh/id_rsa root@<ip> echo "OK"

# 3. Check firewall on that server
sudo iptables -L | grep 3306
sudo ufw status | grep 3306
```

#### Problem: "Nodes not syncing (wsrep_ready=OFF)"

**Solution**:
```bash
# 1. Check MySQL is running
ssh root@<ip> systemctl status mysql

# 2. Check MySQL error log
ssh root@<ip> tail -100 /var/log/mysql/error.log

# 3. Check Galera connection
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_connected';"

# 4. Restart node if necessary
ssh root@<ip> systemctl restart mysql
```

#### Problem: "ProxySQL backends offline"

**Solution**:
```bash
# 1. Check admin interface
mysql -h 192.168.1.20 -P 6032 -u admin -padmin \
  -e "SELECT * FROM mysql_servers;"

# 2. Verify MySQL nodes are up
./health-check.sh

# 3. Check monitor user can connect
mysql -h 192.168.1.10 -u monitor_user -p<password> -e "SELECT 1;"

# 4. Restart ProxySQL
ssh root@192.168.1.20 systemctl restart proxysql
```

#### Problem: "Script permission denied"

**Solution**:
```bash
# Make scripts executable
chmod +x *.sh

# Or run explicitly with bash
bash install-mysql-node.sh
```

#### Problem: "SSH key permission error"

**Solution**:
```bash
# SSH key must have correct permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Check key works
ssh -i ~/.ssh/id_rsa -v root@<ip> echo "OK"
```

### Diagnostic Commands

```bash
# Check cluster status
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep%';" | tee cluster-status.txt

# Check ProxySQL
mysql -h 192.168.1.20 -P 6032 -u admin -padmin \
  -e "SELECT * FROM mysql_servers; SELECT * FROM stats_mysql_global;"

# Check system resources
ssh root@192.168.1.10 free -h
ssh root@192.168.1.10 df -h
ssh root@192.168.1.10 top -b -n 1

# Check logs
ssh root@192.168.1.10 journalctl -u mysql -n 50
```

---

## 🔐 Security Best Practices

### Passwords

- ✓ Change default passwords in cluster-config.sh **before** installation
- ✓ Use strong passwords (minimum 12 chars, mix upper/lower/numbers/symbols)
- ✓ Store passwords securely (use password manager, not plain text)
- ✓ Rotate passwords quarterly using:
  ```bash
  mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'newpass';"
  ```

### SSH Keys

- ✓ Use SSH key-based authentication (enabled by default)
- ✓ Never share private SSH keys
- ✓ Use passphrase for private key (optional but recommended)
- ✓ Add SSH key to ssh-agent for convenience:
  ```bash
  ssh-add ~/.ssh/id_rsa
  ```

### Network

- ✓ Use private network for cluster communication (don't expose to internet)
- ✓ Restrict SSH access (use bastion host if needed)
- ✓ MySQL ports 3306/4567/4568 should only be accessible from cluster nodes
- ✓ ProxySQL public port (6033) accessible from application servers only
- ✓ Admin ports (22, 6032) accessible from your office IP only

### Database Users

- ✓ Never use root for application connections
- ✓ Create application-specific users with minimal privileges:
  ```bash
  CREATE USER 'app'@'%' IDENTIFIED BY 'strongpass';
  GRANT SELECT, INSERT, UPDATE, DELETE ON app_db.* TO 'app'@'%';
  ```
- ✓ ProxySQL monitor user has read-only permissions

### Firewall

- ✓ Enable firewall on all nodes (enabled by default)
- ✓ Only open necessary ports (3306, 4567, 4568, 4444, 6032, 6033)
- ✓ Review firewall rules regularly:
  ```bash
  sudo ufw show added
  sudo firewall-cmd --permanent --list-all
  ```

### Backups

- ✓ Store backups securely (different location/server)
- ✓ Encrypt backups if stored on shared storage:
  ```bash
  innobackupex --user=root --password=pass --encrypt=AES256 \
    --encrypt-key=your-key-here /backups/
  ```
- ✓ Test backup restoration regularly

### Regular Maintenance

- ✓ Update OS and packages monthly:
  ```bash
  sudo apt-get update && sudo apt-get upgrade
  ```
- ✓ Monitor error logs daily
- ✓ Check cluster health daily:
  ```bash
  ./health-check.sh
  ```
- ✓ Review audit logs if enabled

---

## ❓ FAQ

### Q: Can I run this on my existing MySQL server?
**A**: No. The scripts will overwrite MySQL configuration. Use a fresh OS installation.

### Q: What if I only have 3 servers?
**A**: Minimum is 4 servers (3 MySQL + 1 ProxySQL). You cannot run this cluster with only 3 servers.

### Q: Can I add more nodes later?
**A**: Currently this script creates a fixed 3-node cluster. For scaling, manually add nodes following Percona documentation.

### Q: Do I need ProxySQL?
**A**: ProxySQL is optional but recommended. It provides:
- Load balancing across nodes
- Automatic failover (transparent to apps)
- Connection pooling
- Query caching

Without it, manually manage connections.

### Q: What if scripts fail?
**A**: 
1. Check log file: `/tmp/cluster-deployment-*.log`
2. Fix the issue
3. Re-run the script (it's idempotent for most operations)
4. Check troubleshooting section above

### Q: How long does installation take?
**A**: 
- MySQL cluster: 5-15 minutes (depends on server performance)
- ProxySQL: 2-3 minutes
- Total: 10-20 minutes

### Q: Can I use this with Docker/Kubernetes?
**A**: These scripts are for bare-metal/VM. For containers, see Percona XtraDB Cluster Docker image.

### Q: What's the backup strategy?
**A**: Pre-install XtraBackup. Use the `cluster-deployment-report.sh` for backup commands. See "Operations" section for details.

### Q: Can I use different passwords for each node?
**A**: Not recommended. Cluster requires same credentials. Manage different passwords for different applications via application-specific users.

### Q: How do I monitor the cluster?
**A**: Use provided `health-check.sh` script. For production, integrate with:
- Prometheus + Grafana
- Zabbix
- CloudWatch (if on AWS)
- Custom scripts

### Q: What if control node fails?
**A**: Control node is only used for initial deployment. Once cluster is running, it can be turned off.

### Q: Can I upgrade MySQL version later?
**A**: Yes, but follow Percona upgrade guide. Not covered by this script.

---

## 📞 Support & Documentation

- **Percona XtraDB Cluster**: https://www.percona.com/doc/
- **ProxySQL**: https://proxysql.com/documentation/
- **XtraBackup**: https://www.percona.com/doc/percona-xtrabackup/

---

## 📝 License

These scripts are provided as-is for automated deployment of Percona XtraDB Cluster.

---

**Happy clustering! 🚀**
