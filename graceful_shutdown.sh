 #!/bin/bash

# Graceful shutdown script for Galera cluster
# This script ensures proper shutdown sequence and sets safe_to_bootstrap correctly

set -euo pipefail
cd "$(dirname "$0")"

# Load .env file (if present)
if [ -f .env ]; then
    set -a; source .env; set +a
fi

echo "[INFO] Starting graceful shutdown of Galera cluster..."

# Function to wait for container to stop completely
wait_for_container_stop() {
    local container_name="$1"
    local max_wait=30
    local count=0
    
    while docker ps --format "table {{.Names}}" | grep -q "^${container_name}$" 2>/dev/null; do
        if [ $count -ge $max_wait ]; then
            echo "[WARN] Container $container_name didn't stop gracefully in ${max_wait}s, forcing stop..."
            docker stop "$container_name" 2>/dev/null || true
            break
        fi
        echo "[INFO] Waiting for $container_name to stop... (${count}s)"
        sleep 1
        count=$((count + 1))
    done
    echo "[INFO] Container $container_name stopped."
}

# Function to set safe_to_bootstrap for a node
set_safe_to_bootstrap() {
    local node_num="$1"
    local value="$2"
    local grastate_file="./node${node_num}/data/grastate.dat"
    
    if [ -f "$grastate_file" ]; then
        echo "[INFO] Setting safe_to_bootstrap: $value in node${node_num}"
        sed -i.bak "s/safe_to_bootstrap: [01]/safe_to_bootstrap: $value/" "$grastate_file"
    fi
}

# Step 1: Stop HAProxy first to prevent new connections
echo "[INFO] Stopping HAProxy and phpMyAdmin..."
docker compose stop haproxy phpmyadmin 2>/dev/null || true

# Step 2: Stop non-bootstrap nodes first (reverse order)
echo "[INFO] Stopping non-bootstrap nodes (node4, node3, node2)..."
for node in 4 3 2; do
    echo "[INFO] Stopping galera-node${node}..."
    docker compose stop "galera-node${node}" 2>/dev/null || true
    wait_for_container_stop "galera-node${node}"
    
    # Set safe_to_bootstrap to 0 for non-bootstrap nodes
    set_safe_to_bootstrap "$node" "0"
    
    # Small delay between stopping nodes
    sleep 2
done

# Step 3: Stop the bootstrap node (node1) last
echo "[INFO] Stopping bootstrap node (galera-node1)..."
docker compose stop galera-node1 2>/dev/null || true
wait_for_container_stop "galera-node1"

# Step 4: Set safe_to_bootstrap correctly
# Find the node with the highest seqno and set only that one to safe_to_bootstrap: 1
echo "[INFO] Determining which node should be safe to bootstrap..."

highest_seqno=-1
bootstrap_node=""

for i in 1 2 3 4; do
    grastate_file="./node${i}/data/grastate.dat"
    if [ -f "$grastate_file" ]; then
        seqno=$(grep "seqno:" "$grastate_file" | awk '{print $2}')
        echo "[INFO] Node${i} seqno: $seqno"
        
        if [ "$seqno" -gt "$highest_seqno" ]; then
            highest_seqno="$seqno"
            bootstrap_node="$i"
        fi
    fi
done

if [ -n "$bootstrap_node" ]; then
    echo "[INFO] Node${bootstrap_node} has highest seqno ($highest_seqno), marking as safe to bootstrap"
    
    # Set all nodes to safe_to_bootstrap: 0 first
    for i in 1 2 3 4; do
        set_safe_to_bootstrap "$i" "0"
    done
    
    # Set only the highest seqno node to safe_to_bootstrap: 1
    set_safe_to_bootstrap "$bootstrap_node" "1"
else
    echo "[WARN] Could not determine bootstrap node, defaulting to node1"
    set_safe_to_bootstrap "1" "1"
    for i in 2 3 4; do
        set_safe_to_bootstrap "$i" "0"
    done
fi

# Step 5: Final cleanup
echo "[INFO] Ensuring all containers are down..."
docker compose down 2>/dev/null || true

echo "[DONE] Graceful shutdown complete."
echo "[INFO] Node${bootstrap_node:-1} is marked as safe to bootstrap for next startup."
echo "[HINT] Use ./startup_cluster.sh or ./setup_haproxy_user.sh to restart the cluster."
