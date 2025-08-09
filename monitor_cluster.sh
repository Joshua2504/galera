#!/bin/bash

# Signal handler script for graceful Galera cluster management
# This script can be used to handle SIGINT (CTRL+C) and SIGTERM signals gracefully

set -euo pipefail
cd "$(dirname "$0")"

# Load .env file (if present)
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Function to handle signals gracefully
graceful_shutdown() {
    echo ""
    echo "[INFO] Received shutdown signal. Performing graceful cluster shutdown..."
    
    # Call the graceful shutdown script
    if [ -f "./graceful_shutdown.sh" ]; then
        ./graceful_shutdown.sh
    else
        echo "[WARN] graceful_shutdown.sh not found, falling back to basic shutdown..."
        docker compose down
    fi
    
    echo "[INFO] Graceful shutdown completed."
    exit 0
}

# Function to show cluster status
show_status() {
    echo "[INFO] Current cluster status:"
    docker compose ps
    echo ""
    echo "[INFO] Galera cluster status (if accessible):"
    if docker compose exec -T galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null; then
        docker compose exec -T galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-}" -e "SHOW STATUS LIKE 'wsrep%';" 2>/dev/null | grep -E "(wsrep_cluster_size|wsrep_local_state_comment|wsrep_ready)"
    else
        echo "[WARN] Could not connect to cluster for status check"
    fi
}

# Set up signal handlers
trap graceful_shutdown SIGINT SIGTERM

echo "[INFO] Galera cluster monitor started."
echo "[INFO] Press CTRL+C for graceful shutdown, or 's' + Enter for status."
echo "[INFO] The cluster will be safely shut down with proper safe_to_bootstrap settings."
echo ""

# Show initial status
show_status

# Keep the script running and listen for input
while true; do
    read -t 1 -n 1 input 2>/dev/null || true
    
    if [[ "${input:-}" == "s" ]]; then
        show_status
        input=""
    fi
    
    # Check if containers are still running
    if ! docker compose ps -q galera-node1 >/dev/null 2>&1; then
        echo "[INFO] Primary node is not running. Exiting monitor."
        break
    fi
    
    sleep 5
done

echo "[INFO] Monitor exiting."
