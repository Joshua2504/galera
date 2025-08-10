# Galera Cluster with HAProxy & phpMyAdmin

Docker Compose setup for a 4-node MariaDB Galera cluster fronted by HAProxy, with optional direct node exposure and phpMyAdmin.

## Quick Start

1. **Copy environment file**: Copy `.env.example` to `.env` and adjust values as needed:
   ```bash
   cp .env.example .env
   ```

2. **Configure environment**: Edit `.env` to set your desired configuration:
   - **Required**: Set a secure `MYSQL_ROOT_PASSWORD` 
   - **Optional**: Set any `NODE*_HOST_PORT` you want to expose directly (leave blank to keep internal-only)
   - **Optional**: Adjust resource limits, port mappings, and other settings

3. **Start the cluster** (recommended - handles proper sequencing):
   ```bash
   ./startup_cluster.sh
   ```
   
   Or use basic Docker Compose (less reliable for cluster formation):
   ```bash
   docker compose up -d
   ```

4. **Access points**:
   - **MySQL (via HAProxy)**: `localhost:${HAPROXY_MYSQL_PORT:-3306}`
   - **phpMyAdmin**: `http://localhost:${PHPMYADMIN_HOST_PORT:-90}`
   - **HAProxy Stats**: `http://localhost:${HAPROXY_STATS_PORT:-8080}/stats`

## Environment Variables

**Core Settings**:
- `MYSQL_ROOT_PASSWORD` - Root password (⚠️ **REQUIRED** - change from default!)
- `GALERA_CLUSTER_NAME` - Cluster name for node identification
- `MYSQL_DATABASE` - Optional initial database created on node1 bootstrap

**Container Images**:
- `HAPROXY_IMAGE` - HAProxy Docker image (default: `haproxy:2.4`)
- `MARIADB_IMAGE` - MariaDB Docker image (default: `mariadb:10.11`) 
- `PHPMYADMIN_IMAGE` - phpMyAdmin Docker image (default: `phpmyadmin/phpmyadmin`)

**Port Configuration**:
- `HAPROXY_MYSQL_PORT` - Public MySQL entrypoint through HAProxy (default: `3306`)
- `HAPROXY_STATS_PORT` - HAProxy stats page port (default: `8080`)
- `PHPMYADMIN_HOST_PORT` - Host port for phpMyAdmin (default: `90`)
- `NODE{1..4}_HOST_PORT` - Direct node access ports (leave blank to disable, set to expose directly)

**HAProxy Health Check**:
- `HAPROXY_HEALTHCHECK_USER` - MySQL user for HAProxy health checks (default: `haproxy_check`)
- `HAPROXY_HEALTHCHECK_HOST` - Host restriction for health check user (default: `galera-haproxy`)

**Node Names**:
- `NODE{1..4}_NAME` - Individual node names for cluster identification

**phpMyAdmin Settings**:
- `PMA_ARBITRARY` - Allow server selection (default: `1`)
- `UPLOAD_LIMIT` - File upload size limit (default: `300M`)
- `PMA_HOST` - Target server (default: `haproxy`)
- `PMA_PORT` - Target port (default: `3306`)

**Resource Limits** (Docker Compose deploy section):
- `HAPROXY_CPUS` / `HAPROXY_MEMORY` - HAProxy resource limits
- `NODE_CPUS` / `NODE_MEMORY` - Per-node resource limits  
- `PHPMYADMIN_CPUS` / `PHPMYADMIN_MEMORY` - phpMyAdmin resource limits

## Architecture & Components

**Galera Cluster**: 4-node MariaDB cluster with automatic synchronous replication
- **Node1**: Bootstrap node with `--wsrep-new-cluster` (primary during initialization)
- **Nodes 2-4**: Join the cluster automatically on startup
- **Data Persistence**: Each node mounts `./nodeX/data/` to `/var/lib/mysql`
- **Configuration**: Individual `./nodeX/my.cnf` files per node

**HAProxy Load Balancer**: 
- Provides single MySQL endpoint for applications
- Health checks ensure only healthy nodes receive traffic
- Built-in statistics dashboard
- Dedicated health check user with minimal privileges

**phpMyAdmin**: Web-based MySQL administration interface
- Connects through HAProxy for high availability
- Optional component (can be disabled)

## Optional Direct Node Access

Direct node port mappings are removed from the base `docker-compose.yml` to reduce attack surface. The `docker-compose.override.yml` adds conditional port mappings:

```yaml
services:
  galera-node1:
    ports:
      - "${NODE1_HOST_PORT:-}:3306"
```

- **Empty variable**: Compose ignores the mapping (node remains internal-only)
- **Set variable**: Direct access enabled (e.g., `NODE1_HOST_PORT=3307`)
- **Use case**: Direct debugging, monitoring, or application-specific connections

⚠️ **Security Note**: Only expose nodes you specifically need for debugging or specialized applications.

## Cluster Management

### Bootstrap & Recovery Process

**Initial Bootstrap**: Node1 starts with `--wsrep-new-cluster` to initialize the cluster. Other nodes join automatically.

**Recovery After Shutdown**: The cluster automatically determines the correct bootstrap node:
1. **Automatic Detection**: Scripts analyze `grastate.dat` files to find the node with highest sequence number (`seqno`)
2. **Safe Bootstrap**: Only the most advanced node gets `safe_to_bootstrap: 1`
3. **Sequential Startup**: Bootstrap node starts first, others join in sequence

**Manual Recovery** (if needed):
- Check `./nodeX/data/grastate.dat` files for `seqno` values
- The node with **highest `seqno`** should have `safe_to_bootstrap: 1`
- All other nodes should have `safe_to_bootstrap: 0`

### Recommended Management Scripts

**🚀 Start Cluster** (with proper sequencing and delays):
```bash
./startup_cluster.sh
```

**🛑 Graceful Shutdown** (preserves cluster state):
```bash
./graceful_shutdown.sh
```

**📊 Monitor with Graceful CTRL+C Handling**:
```bash
./monitor_cluster.sh
```

**👤 Setup/Reset HAProxy Health Check User**:
```bash
./setup_haproxy_user.sh
```

### Enhanced Signal Handling

The cluster includes improved handling for graceful operations:

- **SIGTERM Support**: All nodes configured with `stop_signal: SIGTERM` and `stop_grace_period: 30s`
- **Automatic Bootstrap Detection**: Scripts auto-detect the correct node for bootstrap based on highest `seqno`
- **Sequential Startup**: Proper delays between node startups prevent split-brain scenarios
- **CTRL+C Safety**: Monitor script handles interruption gracefully

## Security Considerations

**🔐 Essential Security Steps**:

1. **Change Default Password**: Always modify `MYSQL_ROOT_PASSWORD` in `.env` before deployment
2. **Limit Exposure**: Use firewall rules to restrict HAProxy access beyond local development
3. **Health Check User**: HAProxy uses a dedicated `haproxy_check` user with no privileges
4. **Host Restrictions**: Health check user is scoped to `galera-haproxy` hostname (not `%` wildcard)

**⚠️ Production Hardening**:
- Create dedicated application users instead of using root
- Disable root remote login: `SET sql_mode = 'TRADITIONAL'; UPDATE mysql.user SET host = 'localhost' WHERE user = 'root';`
- Use strong, rotated passwords with proper secrets management
- Enable SSL/TLS for MySQL connections
- Consider network-level encryption (VPN, service mesh)

**🔧 Configuration Notes**:
- Adjust `HAPROXY_HEALTHCHECK_HOST` if container name resolution fails (use subnet like `172.%`)
- Avoid `%` wildcard except for local testing environments
- Health check user is automatically created by `setup_haproxy_user.sh`

## Common Operations

### Manual Docker Compose Operations

**Update images and restart**:
```bash
docker compose pull
docker compose up -d --remove-orphans
```

**View container status**:
```bash
docker compose ps
```

**View logs** (specific service):
```bash
docker compose logs -f galera-node1
docker compose logs -f haproxy
```

### Database Operations

**Check cluster status**:
```bash
docker compose exec galera-node1 mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

**Detailed cluster information**:
```bash
docker compose exec galera-node1 mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'wsrep%';"
```

**Connect to specific node directly**:
```bash
docker compose exec galera-node1 mysql -uroot -p"$MYSQL_ROOT_PASSWORD"
```

**Run SQL commands**:
```bash
docker compose exec galera-node1 mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE myapp; SHOW DATABASES;"
```

## Troubleshooting

### Common Issues & Solutions

**❌ Node fails to join cluster**:
```bash
# Check grastate.dat consistency
cat ./node*/data/grastate.dat | grep -E "(seqno|safe_to_bootstrap)"

# Verify cluster name matches across all nodes
docker compose exec galera-node1 mysql -uroot -p -e "SHOW VARIABLES LIKE 'wsrep_cluster_name';"
```

**❌ Cluster won't start after all nodes stopped**:
1. Use `./startup_cluster.sh` (auto-detects correct bootstrap node)
2. Or manually check which node has highest `seqno` in `grastate.dat`
3. Set only that node to `safe_to_bootstrap: 1`

**❌ HAProxy shows nodes as DOWN**:
- **Normal during startup** - health checks need time to complete
- Check health check user exists: `docker compose exec galera-node1 mysql -uroot -p -e "SELECT user,host FROM mysql.user WHERE user='haproxy_check';"`
- Verify network connectivity: `docker compose exec haproxy ping galera-node1`

**❌ Port not accessible from host**:
- Ensure `NODE*_HOST_PORT` is set in `.env` (numeric value, no quotes)  
- Recreate containers: `docker compose up -d --force-recreate`
- Check port conflicts: `netstat -ln | grep :3307`

**❌ Permission denied / authentication errors**:
- Verify `MYSQL_ROOT_PASSWORD` matches initialized data
- For complete reset (⚠️ **DATA LOSS**): Remove `./node*/data/` directories

**❌ Split-brain scenarios**:
- Stop all nodes: `./graceful_shutdown.sh`
- Check `grastate.dat` files for consistency
- Use `./startup_cluster.sh` for proper recovery

### Reset Cluster (Development Only)

**⚠️ WARNING**: This destroys all data!
```bash
docker compose down
sudo rm -rf ./node*/data/
docker compose up -d
```

## Testing & Validation

### Load Testing

Use the included `stress_test.sh` script or create custom load tests:

```bash
# Example sysbench test through HAProxy
sysbench oltp_read_write \
  --mysql-host=localhost \
  --mysql-port=3306 \
  --mysql-user=root \
  --mysql-password="$MYSQL_ROOT_PASSWORD" \
  --mysql-db=testdb \
  --tables=4 \
  --table-size=10000 \
  --threads=8 \
  --time=60 \
  --report-interval=10 \
  run
```

### High Availability Testing

**Test node failure**:
```bash
# Stop a non-bootstrap node
docker compose stop galera-node2

# Verify cluster continues operating
docker compose exec galera-node1 mysql -uroot -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# Restart the node
docker compose start galera-node2
```

**Test HAProxy failover**:
```bash
# Connect through HAProxy and monitor which node serves requests
docker compose exec galera-node1 mysql -uroot -p -e "SELECT @@hostname;"
```

### Performance Monitoring

**Galera-specific metrics**:
```bash
docker compose exec galera-node1 mysql -uroot -p -e "
  SELECT VARIABLE_NAME, VARIABLE_VALUE 
  FROM information_schema.GLOBAL_STATUS 
  WHERE VARIABLE_NAME LIKE 'wsrep%' 
  AND VARIABLE_NAME IN (
    'wsrep_cluster_size',
    'wsrep_local_state_comment', 
    'wsrep_flow_control_paused',
    'wsrep_cert_deps_distance'
  );"
```

---

## Development vs Production

This setup is optimized for **development and testing**. For production use:

- [ ] Enable SSL/TLS for MySQL connections
- [ ] Implement proper secrets management (not `.env` files)
- [ ] Add comprehensive monitoring (Prometheus, Grafana)
- [ ] Configure log aggregation and rotation  
- [ ] Set up automated backups
- [ ] Implement network security (firewalls, VPNs)
- [ ] Use dedicated servers with proper resource allocation
- [ ] Enable audit logging for compliance
- [ ] Test disaster recovery procedures

**Maintained for development & testing scenarios. Thoroughly test and harden before production use.**
