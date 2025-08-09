#!/bin/bash

# Enhanced startup script for Galera cluster with proper delays
# This script ensures nodes start in the correct order with appropriate delays

set -euo pipefail
cd "$(dirname "$0")"

# Load .env file (if present)
if [ -f .env ]; then
    set -a; source .env; set +a
fi

echo "[INFO] Starting Galera cluster with proper sequencing..."

# Function to wait for a container to be healthy
wait_for_container_healthy() {
    local container_name="$1"
    local max_wait="${2:-60}"
    local count=0
    
    echo "[INFO] Waiting for $container_name to become healthy..."
    while [ $count -lt $max_wait ]; do
        if docker compose ps --format "table {{.Name}} {{.Status}}" | grep "$container_name" | grep -q "Up"; then
            echo "[INFO] $container_name is up and running."
            return 0
        fi
        sleep 2
        count=$((count + 2))
        echo "[INFO] Waiting for $container_name... (${count}s/${max_wait}s)"
    done
    
    echo "[ERROR] $container_name failed to start properly within ${max_wait}s"
    return 1
}

# Function to wait for MySQL to be ready
wait_for_mysql_ready() {
    local container_name="$1"
    local max_wait="${2:-60}"
    local count=0
    
    echo "[INFO] Waiting for MySQL to be ready in $container_name..."
    while [ $count -lt $max_wait ]; do
        if docker compose exec -T "$container_name" sh -c "mysqladmin ping >/dev/null 2>&1" 2>/dev/null; then
            echo "[INFO] MySQL is ready in $container_name."
            return 0
        fi
        sleep 2
        count=$((count + 2))
        echo "[INFO] Waiting for MySQL in $container_name... (${count}s/${max_wait}s)"
    done
    
    echo "[ERROR] MySQL in $container_name failed to become ready within ${max_wait}s"
    return 1
}

# Function to check Galera cluster status
check_galera_status() {
    local container_name="$1"
    echo "[INFO] Checking Galera status for $container_name..."
    
    # Try to get cluster size
    if docker compose exec -T "$container_name" mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null; then
        echo "[INFO] Galera status check completed for $container_name."
    else
        echo "[WARN] Could not retrieve Galera status for $container_name (this might be normal during startup)."
    fi
}

# Ensure all containers are stopped first
echo "[INFO] Ensuring clean slate - stopping all containers..."
docker compose down 2>/dev/null || true
sleep 3

# Determine which node should be the bootstrap node
echo "[INFO] Determining bootstrap node based on highest sequence number..."
bootstrap_node=""
highest_seqno=-1
nodes_with_highest_seqno=()

# First pass: find the highest seqno
for i in 1 2 3 4; do
    grastate_file="./node${i}/data/grastate.dat"
    if [ -f "$grastate_file" ]; then
        seqno=$(grep "seqno:" "$grastate_file" | awk '{print $2}')
        safe_bootstrap=$(grep "safe_to_bootstrap:" "$grastate_file" | awk '{print $2}')
        echo "[INFO] Node${i}: seqno=$seqno, safe_to_bootstrap=$safe_bootstrap"
        
        if [ "$seqno" -gt "$highest_seqno" ]; then
            highest_seqno="$seqno"
            nodes_with_highest_seqno=("$i")
        elif [ "$seqno" -eq "$highest_seqno" ]; then
            nodes_with_highest_seqno+=("$i")
        fi
    fi
done

# Second pass: if multiple nodes have highest seqno, prefer one with safe_to_bootstrap: 1
if [ ${#nodes_with_highest_seqno[@]} -eq 1 ]; then
    bootstrap_node="${nodes_with_highest_seqno[0]}"
    echo "[INFO] Node${bootstrap_node} has highest seqno ($highest_seqno), using as bootstrap node"
elif [ ${#nodes_with_highest_seqno[@]} -gt 1 ]; then
    echo "[INFO] Multiple nodes have highest seqno ($highest_seqno): ${nodes_with_highest_seqno[*]}"
    
    # Look for one that already has safe_to_bootstrap: 1
    for node in "${nodes_with_highest_seqno[@]}"; do
        grastate_file="./node${node}/data/grastate.dat"
        if grep -q "safe_to_bootstrap: 1" "$grastate_file"; then
            bootstrap_node="$node"
            echo "[INFO] Node${bootstrap_node} already marked as safe_to_bootstrap, using it"
            break
        fi
    done
    
    # If none has safe_to_bootstrap: 1, pick the first one
    if [ -z "$bootstrap_node" ]; then
        bootstrap_node="${nodes_with_highest_seqno[0]}"
        echo "[INFO] Using node${bootstrap_node} (first in list) as bootstrap node"
    fi
fi

if [ -n "$bootstrap_node" ]; then
    echo "[INFO] Selected node${bootstrap_node} with seqno $highest_seqno as bootstrap node"
    
    # Ensure the selected node has safe_to_bootstrap: 1
    grastate_file="./node${bootstrap_node}/data/grastate.dat"
    if ! grep -q "safe_to_bootstrap: 1" "$grastate_file"; then
        echo "[INFO] Setting safe_to_bootstrap: 1 for node${bootstrap_node}"
        sed -i.bak "s/safe_to_bootstrap: [01]/safe_to_bootstrap: 1/" "$grastate_file"
    fi
    
    # Ensure all other nodes have safe_to_bootstrap: 0
    for i in 1 2 3 4; do
        if [ "$i" != "$bootstrap_node" ]; then
            other_grastate="./node${i}/data/grastate.dat"
            if [ -f "$other_grastate" ] && grep -q "safe_to_bootstrap: 1" "$other_grastate"; then
                echo "[INFO] Setting safe_to_bootstrap: 0 for node${i}"
                sed -i.bak "s/safe_to_bootstrap: [01]/safe_to_bootstrap: 0/" "$other_grastate"
            fi
        fi
    done
else
    echo "[WARN] Could not determine bootstrap node, defaulting to node1"
    bootstrap_node="1"
fi

# Step 1: Start the bootstrap node first
echo "[INFO] Starting bootstrap node (galera-node${bootstrap_node})..."
docker compose up -d "galera-node${bootstrap_node}"

# Wait for bootstrap node to be fully ready
wait_for_container_healthy "galera-node${bootstrap_node}" 90
wait_for_mysql_ready "galera-node${bootstrap_node}" 90

# Give the bootstrap node extra time to initialize
echo "[INFO] Allowing bootstrap node to fully initialize..."
sleep 10

check_galera_status "galera-node${bootstrap_node}"

# Step 2: Setup HAProxy health check user and start HAProxy
echo "[INFO] Setting up HAProxy health check user..."

# Default values
HAPROXY_HEALTHCHECK_USER=${HAPROXY_HEALTHCHECK_USER:-haproxy_check}
HAPROXY_HEALTHCHECK_HOST=${HAPROXY_HEALTHCHECK_HOST:-galera-haproxy}

# Determine MySQL connection method (use bootstrap node)
MYSQL_EXEC=(docker compose exec -T "galera-node${bootstrap_node}" mysql -uroot)
if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
    MYSQL_EXEC=(docker compose exec -T "galera-node${bootstrap_node}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}")
fi

# Create health check user
SQL=""
SQL+="DROP USER IF EXISTS '${HAPROXY_HEALTHCHECK_USER}'@'%';\n"
SQL+="CREATE USER IF NOT EXISTS '${HAPROXY_HEALTHCHECK_USER}'@'${HAPROXY_HEALTHCHECK_HOST}' IDENTIFIED BY '';\n"
SQL+="REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${HAPROXY_HEALTHCHECK_USER}'@'${HAPROXY_HEALTHCHECK_HOST}';\n"
SQL+="FLUSH PRIVILEGES;\n"

"${MYSQL_EXEC[@]}" -e "$SQL" 2>/dev/null || echo "[WARN] Could not create health check user, will try during HAProxy startup"

# Start HAProxy now that the bootstrap node is ready
echo "[INFO] Starting HAProxy..."
docker compose up -d haproxy

wait_for_container_healthy "haproxy" 30

# Give HAProxy time to perform initial health checks
echo "[INFO] Allowing HAProxy to perform initial health checks..."
sleep 10

echo "[INFO] HAProxy started! Stats will be available once health checks complete."
echo "[NOTE] HAProxy stats may show nodes as DOWN initially - this is normal during startup."

# Step 3: Start remaining nodes (excluding the bootstrap node)
remaining_nodes=()
for i in 1 2 3 4; do
    if [ "$i" != "$bootstrap_node" ]; then
        remaining_nodes+=("$i")
    fi
done

for node in "${remaining_nodes[@]}"; do
    echo "[INFO] Starting galera-node${node}..."
    docker compose up -d "galera-node${node}"
    
    wait_for_container_healthy "galera-node${node}" 60
    wait_for_mysql_ready "galera-node${node}" 60
    
    # Wait for node to join the cluster
    echo "[INFO] Waiting for node${node} to join cluster..."
    sleep 15
    
    check_galera_status "galera-node${node}"
done

# Step 4: Start phpMyAdmin if defined
if docker compose config --services | grep -q '^phpmyadmin$'; then
    echo "[INFO] Starting phpMyAdmin..."
    docker compose up -d phpmyadmin
    wait_for_container_healthy "phpmyadmin" 30
fi

# Final cluster status check
echo "[INFO] Final cluster status check..."
sleep 5

echo "[INFO] Attempting to show final cluster status..."
if "${MYSQL_EXEC[@]}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null; then
    echo "[INFO] Cluster status retrieved successfully."
else
    echo "[WARN] Could not retrieve final cluster status."
fi

echo "[DONE] Galera cluster startup completed!"
echo "[INFO] Bootstrap node was: galera-node${bootstrap_node}"
echo "[INFO] All nodes should now be running and synchronized."
echo ""
echo "🔗 Access Points:"
echo "   HAProxy Stats: http://localhost:${HAPROXY_STATS_PORT:-8080}/stats"
echo "   MySQL (via HAProxy): localhost:${HAPROXY_MYSQL_PORT:-3306}"
echo "   phpMyAdmin: http://localhost:${PHPMYADMIN_HOST_PORT:-90}"
echo ""
echo "[HINT] Check cluster status with: docker compose exec galera-node${bootstrap_node} mysql -uroot -p -e \"SHOW STATUS LIKE 'wsrep%';\""
