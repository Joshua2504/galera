# Galera Cluster with HAProxy & phpMyAdmin

Docker Compose setup for a 4-node MariaDB Galera cluster fronted by HAProxy, with optional direct node exposure and phpMyAdmin.

## Quick Start
1. Copy `.env.example` to `.env` and adjust as needed.
2. (Optional) Set any `NODE*_HOST_PORT` you want to expose (leave blank to keep internal-only).
3. Start services:
```bash
docker compose up -d
```
4. phpMyAdmin: http://localhost:${PHPMYADMIN_HOST_PORT:-90}
5. HAProxy stats: http://localhost:${HAPROXY_STATS_PORT:-8080}
   (Default stats credentials depend on your `haproxy.cfg`).

## Environment Variables
Core:
- `MYSQL_ROOT_PASSWORD` Root password (change in production!)
- `GALERA_CLUSTER_NAME` Cluster name
- `MYSQL_DATABASE` Optional initial DB on node1 bootstrap

Images:
- `HAPROXY_IMAGE`, `MARIADB_IMAGE`, `PHPMYADMIN_IMAGE`

Ports:
- `HAPROXY_MYSQL_PORT` Public MySQL entrypoint through HAProxy (default 3306)
- `HAPROXY_STATS_PORT` HAProxy stats page (default 8080)
- `PHPMYADMIN_HOST_PORT` Host port for phpMyAdmin (default 90)
- `NODE{1..4}_HOST_PORT` Leave blank to disable direct exposure. Set (e.g. 3307) to map host:node port via `docker-compose.override.yml`.

phpMyAdmin:
- `PMA_ARBITRARY`, `UPLOAD_LIMIT`, `PMA_HOST`, `PMA_PORT`

Resource Limits (Compose deploy section – effective in Swarm or as documentation locally):
- `HAPROXY_CPUS`, `HAPROXY_MEMORY`
- `NODE_CPUS`, `NODE_MEMORY`
- `PHPMYADMIN_CPUS`, `PHPMYADMIN_MEMORY`

## Optional Direct Node Ports
Direct node port mappings are removed from the base `docker-compose.yml` to reduce surface area.
The file `docker-compose.override.yml` adds conditional mappings:
```yaml
services:
  galera-node1:
    ports:
      - "${NODE1_HOST_PORT:-}:3306"
```
If the variable is empty, Compose will ignore the mapping. Set only those you need.

## Cluster Bootstrap
Node1 runs with `--wsrep-new-cluster` to initialize the cluster. Subsequent nodes join automatically.
If you need to re-bootstrap after a crash, ensure the most advanced node is started with `--wsrep-new-cluster` (adjust command temporarily) or clear data dirs (development only).

## Data Persistence
Each node mounts `./nodeX/data` to `/var/lib/mysql`. Removing those directories resets that node's state.

## Security Notes
- Always change `MYSQL_ROOT_PASSWORD` before exposing publicly.
- Limit HAProxy exposure via firewall if used beyond local dev.
- Consider adding user accounts and disabling root remote login for real deployments.
- The HAProxy MySQL health check user is created by `setup_haproxy_user.sh` as `haproxy_check` scoped to `galera-haproxy` (not `'%'`). Adjust with `HAPROXY_HEALTHCHECK_USER` / `HAPROXY_HEALTHCHECK_HOST` in `.env`. Avoid using `%` except for throwaway local tests.

## Common Tasks

### Graceful Cluster Management

**Start the cluster with proper delays:**
```bash
./startup_cluster.sh
```

**Gracefully shutdown the cluster:**
```bash
./graceful_shutdown.sh
```

**Monitor cluster with graceful shutdown on CTRL+C:**
```bash
./monitor_cluster.sh
```

**Setup HAProxy health check user (enhanced with delays):**
```bash
./setup_haproxy_user.sh
```

### Manual Operations

Rebuild after image change:
```bash
docker compose pull
docker compose up -d --remove-orphans
```

Check cluster size:
```bash
docker exec -it galera-node1 mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

### Handling CTRL+C and Cluster Crashes

The cluster now includes improved handling for graceful shutdowns:

1. **Automatic safe_to_bootstrap management**: The `graceful_shutdown.sh` script automatically determines which node has the highest sequence number and sets only that node to `safe_to_bootstrap: 1`
2. **Sequential startup with delays**: The `startup_cluster.sh` auto-detects the correct bootstrap node and ensures proper startup sequencing
3. **Signal handling**: Use `monitor_cluster.sh` to run a monitoring session that handles CTRL+C gracefully
4. **Enhanced Docker Compose**: Added `stop_signal: SIGTERM` and `stop_grace_period: 30s` to all Galera nodes

**If you accidentally CTRL+C without graceful shutdown:**
1. Check `grastate.dat` files in each node's data directory
2. **IMPORTANT**: Only the node with the **highest `seqno`** should have `safe_to_bootstrap: 1`
3. All other nodes should have `safe_to_bootstrap: 0`
4. Use `./startup_cluster.sh` to restart with proper sequencing (it will auto-detect the correct bootstrap node)

## Troubleshooting
- Node fails to join: verify `grastate.dat` and consistent cluster name.
- Stale cluster after all nodes stopped: remove `gvwstate.dat` if necessary (dev only) or explicitly bootstrap node with highest seqno.
- Port not exposed: ensure you set the `NODE*_HOST_PORT` variable (no quotes, numeric) and recreated containers.

## Stress / Testing
Scripts like `stress_test.sh` (if present) can be adapted to run sysbench or custom load through HAProxy to validate replication.

---
Maintained for development & testing scenarios. Harden before production use.
