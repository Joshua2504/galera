#!/bin/bash

# First-run (idempotent) helper to:
#  1. Start ONLY galera-node1 (bootstrap node)
#  2. Create / tighten the HAProxy MySQL health‑check user
#  3. Start the remaining nodes and HAProxy (and phpMyAdmin if defined)
# Can be safely re-run later: it will just recreate / lock down the user.

set -euo pipefail

cd "$(dirname "$0")"

# Load .env file (if present)
if [ -f .env ]; then
	set -a; source .env; set +a
fi

# Defaults (can be overridden in .env)
HAPROXY_HEALTHCHECK_USER=${HAPROXY_HEALTHCHECK_USER:-haproxy_check}
# Host the user is allowed to connect from. Avoid '%'. Options:
#  - Specific container name (requires reverse DNS): galera-haproxy
#  - Subnet pattern (e.g. '172.%') if name resolution is disabled
#  - '%' (NOT recommended) only for local dev experiments
HAPROXY_HEALTHCHECK_HOST=${HAPROXY_HEALTHCHECK_HOST:-galera-haproxy}

if [ "${HAPROXY_HEALTHCHECK_HOST}" = "%" ]; then
	echo "[WARN] HAPROXY_HEALTHCHECK_HOST is '%' (public wildcard). Consider narrowing it (e.g. galera-haproxy or 172.%)." >&2
fi

need_start_node1=false
need_start_others=false

is_running() { # service name
		docker compose ps -q "$1" >/dev/null 2>&1 && [ -n "$(docker compose ps -q "$1" 2>/dev/null)" ]
}

# Determine a working way to connect as root inside galera-node1
pick_mysql_exec() {
	echo "[DEBUG] Trying auth method 1: with password from .env..."
	# Try with provided password - use printf to avoid shell interpretation issues
	if printf '%s\n' "SELECT 1;" | docker compose exec -T galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1; then
		MYSQL_EXEC=(docker compose exec -T galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}")
		echo "[DEBUG] Auth method 1 succeeded."
		return 0
	fi
	echo "[DEBUG] Trying auth method 2: empty password..."
	# Try empty password
	if printf '%s\n' "SELECT 1;" | docker compose exec -T galera-node1 mysql -uroot -p"" >/dev/null 2>&1; then
		MYSQL_EXEC=(docker compose exec -T galera-node1 mysql -uroot -p"")
		echo "[DEBUG] Auth method 2 succeeded."
		return 0
	fi
	echo "[DEBUG] Trying auth method 3: no password (socket)..."
	# Try no password (socket auth)
	if printf '%s\n' "SELECT 1;" | docker compose exec -T galera-node1 mysql -uroot >/dev/null 2>&1; then
		MYSQL_EXEC=(docker compose exec -T galera-node1 mysql -uroot)
		echo "[DEBUG] Auth method 3 succeeded."
		return 0
	fi
	echo "[DEBUG] All auth methods failed."
	return 1
}

# Enhanced cluster health check
check_cluster_health() {
	echo "[INFO] Checking Galera cluster status..."
	local ready_count=0
	local nodes=("galera-node1" "galera-node2" "galera-node3" "galera-node4")
	
	for node in "${nodes[@]}"; do
		if is_running "$node"; then
			if docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | grep -q "ON"; then
				echo "[INFO] $node is ready and synced"
				((ready_count++))
			else
				echo "[WARN] $node is running but not ready/synced"
			fi
		else
			echo "[WARN] $node is not running"
		fi
	done
	
	echo "[INFO] $ready_count/4 nodes are ready and synced"
	return $ready_count
}

if ! is_running galera-node1; then
	echo "[INFO] galera-node1 not running -> starting bootstrap node only..."
	docker compose up -d galera-node1
	need_start_others=true
else
	# If node1 is up but haproxy not, we'll still treat it as partial startup
	if ! is_running haproxy; then
		need_start_others=true
	fi
fi

if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
	echo "[WARN] MYSQL_ROOT_PASSWORD is empty/unset in environment. If the data dir was initialized with a password, this will fail." >&2
fi

echo "[INFO] Waiting for galera-node1 MySQL to become ready..."
retries=60
auth_retries=10
while true; do
	if docker compose exec -T galera-node1 sh -lc "mysqladmin ping >/dev/null 2>&1"; then
		echo "[INFO] mysqld is alive. Selecting authentication method..."
		if pick_mysql_exec; then
			echo "[INFO] Selected root authentication method successfully."
			break
		fi
		# If we can't auth yet, keep waiting a little more (e.g., grants not ready)
		auth_retries=$((auth_retries-1)) || true
		if [ $auth_retries -le 0 ]; then
			echo "[ERROR] mysqld is alive but no root auth method worked after multiple attempts." >&2
			echo "        This suggests the root password in .env doesn't match the initialized data." >&2
			echo "        For a local dev reset, run: ./reset_cluster.sh (DESTROYS local data)." >&2
			exit 1
		fi
	fi
	retries=$((retries-1)) || true
	if [ $retries -le 0 ]; then
		echo "[ERROR] MySQL on galera-node1 did not become ready (or no usable root auth) in time." >&2
		echo "        Tried: password from .env, empty password, and socket without password." >&2
		echo "        If you initialized the data dir with a different root password, update .env or wipe ./node*/data to re-bootstrap (data loss)." >&2
		echo "        For a local dev reset, run: ./reset_cluster.sh (DESTROYS local data)." >&2
		exit 1
	fi
	sleep 2
done

echo "[INFO] Creating locked-down HAProxy health check user '${HAPROXY_HEALTHCHECK_USER}'@'${HAPROXY_HEALTHCHECK_HOST}' on galera-node1..."

SQL=""
SQL+="DROP USER IF EXISTS '${HAPROXY_HEALTHCHECK_USER}'@'%';\n"
SQL+="CREATE USER IF NOT EXISTS '${HAPROXY_HEALTHCHECK_USER}'@'${HAPROXY_HEALTHCHECK_HOST}' IDENTIFIED BY '';\n"
SQL+="REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${HAPROXY_HEALTHCHECK_USER}'@'${HAPROXY_HEALTHCHECK_HOST}';\n"
SQL+="FLUSH PRIVILEGES;\n"

"${MYSQL_EXEC[@]}" -e "$SQL"

echo "[INFO] Current matching user entries:" 
"${MYSQL_EXEC[@]}" -N -e "SELECT user, host FROM mysql.user WHERE user='${HAPROXY_HEALTHCHECK_USER}' ORDER BY host;"

if [ "$need_start_others" = true ]; then
	echo "[INFO] Starting remaining Galera nodes sequentially..."
	
	# Start nodes one by one with delays to ensure proper cluster formation
	echo "[INFO] Starting galera-node2..."
	docker compose up -d galera-node2
	echo "[INFO] Waiting for node2 to join cluster..."
	sleep 15
	
	echo "[INFO] Starting galera-node3..."
	docker compose up -d galera-node3
	echo "[INFO] Waiting for node3 to join cluster..."
	sleep 15
	
	echo "[INFO] Starting galera-node4..."
	docker compose up -d galera-node4
	echo "[INFO] Waiting for node4 to join cluster..."
	sleep 15
	
	echo "[INFO] Starting HAProxy..."
	# haproxy & optional phpmyadmin
	if docker compose config --services | grep -q '^haproxy$'; then
		docker compose up -d haproxy
		sleep 5
	fi
	if docker compose config --services | grep -q '^phpmyadmin$'; then
		docker compose up -d phpmyadmin
	fi
else
	echo "[INFO] Not starting other nodes (already running)."
fi

echo "[DONE] Health check user ensured. haproxy.cfg expects: option mysql-check user ${HAPROXY_HEALTHCHECK_USER}"
echo "[HINT] If HAProxy can't connect, adjust HAPROXY_HEALTHCHECK_HOST (reverse DNS issues) – you can use a subnet like '172.%'."
