#!/bin/bash

# Enhanced monitoring script for HAProxy + Galera cluster
# Monitors both HAProxy statistics and Galera cluster health

set -euo pipefail

cd "$(dirname "$0")"

# Load .env file (if present)
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# Configuration
HAPROXY_STATS_URL="${HAPROXY_STATS_URL:-http://localhost:8080/stats}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
LOG_FILE="${LOG_FILE:-haproxy_galera_monitor.log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}======================================"
    echo -e " HAProxy + Galera Cluster Monitor"
    echo -e " $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "======================================${NC}"
}

check_haproxy_stats() {
    echo -e "\n${BLUE}=== HAProxy Statistics ===${NC}"
    
    if command -v curl >/dev/null 2>&1; then
        local stats_output
        if stats_output=$(curl -s "$HAPROXY_STATS_URL;csv" 2>/dev/null); then
            echo "$stats_output" | grep -E "galera-node|galera-backend" | while IFS=',' read -r -a fields; do
                # Check if we have enough fields before accessing them
                if [ ${#fields[@]} -lt 24 ]; then
                    echo -e "  ${YELLOW}!${NC} Incomplete CSV data for line: ${fields[*]}"
                    continue
                fi
                
                local pxname="${fields[0]:-}"
                local svname="${fields[1]:-}"
                local status="${fields[17]:-}"
                local weight="${fields[18]:-}"
                local act="${fields[19]:-}"
                local bck="${fields[20]:-}"
                local chkfail="${fields[21]:-}"
                local chkdown="${fields[22]:-}"
                local lastchg="${fields[23]:-}"
                
                if [[ "$status" == "UP" ]]; then
                    echo -e "  ${GREEN}✓${NC} $svname: $status (weight: $weight, active: $act, backup: $bck)"
                else
                    echo -e "  ${RED}✗${NC} $svname: $status (failures: $chkfail, downtime: $chkdown)"
                fi
            done
        else
            echo -e "  ${RED}✗${NC} Could not retrieve HAProxy statistics"
            log_message "ERROR" "Failed to retrieve HAProxy statistics from $HAPROXY_STATS_URL"
        fi
    else
        echo -e "  ${YELLOW}!${NC} curl not available, skipping HAProxy stats check"
    fi
}

check_galera_cluster() {
    echo -e "\n${BLUE}=== Galera Cluster Status ===${NC}"
    
    local nodes=("galera-node1" "galera-node2" "galera-node3" "galera-node4")
    local ready_nodes=0
    local total_nodes=0
    
    for node in "${nodes[@]}"; do
        if docker compose ps -q "$node" >/dev/null 2>&1 && [ -n "$(docker compose ps -q "$node" 2>/dev/null)" ]; then
            ((total_nodes++))
            echo -e "\n  ${BLUE}Node: $node${NC}"
            
            # Check if MySQL is responsive
            if docker compose exec -T "$node" mysqladmin ping -uroot -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1; then
                
                # Get Galera status
                local wsrep_ready=$(docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | cut -f2)
                local wsrep_cluster_status=$(docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null | cut -f2)
                local wsrep_local_state=$(docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW STATUS LIKE 'wsrep_local_state';" 2>/dev/null | cut -f2)
                local wsrep_cluster_size=$(docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | cut -f2)
                local wsrep_connected=$(docker compose exec -T "$node" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "SHOW STATUS LIKE 'wsrep_connected';" 2>/dev/null | cut -f2)
                
                if [[ "$wsrep_ready" == "ON" && "$wsrep_cluster_status" == "Primary" && "$wsrep_local_state" == "4" ]]; then
                    echo -e "    ${GREEN}✓${NC} Status: Ready and Synced"
                    ((ready_nodes++))
                else
                    echo -e "    ${YELLOW}!${NC} Status: Not Ready"
                fi
                
                echo -e "    - Ready: $wsrep_ready"
                echo -e "    - Cluster Status: $wsrep_cluster_status"
                echo -e "    - Local State: $wsrep_local_state (4=Synced)"
                echo -e "    - Connected: $wsrep_connected"
                echo -e "    - Cluster Size: $wsrep_cluster_size"
                
            else
                echo -e "    ${RED}✗${NC} MySQL not responsive"
                log_message "ERROR" "$node MySQL is not responsive"
            fi
        else
            echo -e "\n  ${RED}✗${NC} Node: $node (not running)"
        fi
    done
    
    echo -e "\n  ${BLUE}Cluster Summary:${NC} $ready_nodes/$total_nodes nodes ready and synced"
    
    if [ $ready_nodes -eq 0 ]; then
        log_message "CRITICAL" "No Galera nodes are ready!"
        return 1
    elif [ $ready_nodes -lt 2 ]; then
        log_message "WARNING" "Only $ready_nodes Galera node(s) ready - cluster may have split-brain risk"
        return 1
    else
        log_message "INFO" "$ready_nodes/$total_nodes Galera nodes are ready and synced"
        return 0
    fi
}

check_connections() {
    echo -e "\n${BLUE}=== Connection Status ===${NC}"
    
    # Test connection through HAProxy
    local haproxy_port="${HAPROXY_MYSQL_PORT:-3306}"
    if command -v mysql >/dev/null 2>&1; then
        if mysql -h localhost -P "$haproxy_port" -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} HAProxy MySQL connection successful"
        else
            echo -e "  ${RED}✗${NC} HAProxy MySQL connection failed"
            log_message "ERROR" "Cannot connect to MySQL through HAProxy"
        fi
    else
        echo -e "  ${YELLOW}!${NC} MySQL client not available for connection test"
    fi
    
    # Check HAProxy web interface
    if command -v curl >/dev/null 2>&1; then
        local stats_port="${HAPROXY_STATS_PORT:-8080}"
        if curl -s "http://localhost:$stats_port/stats" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} HAProxy stats interface accessible"
        else
            echo -e "  ${RED}✗${NC} HAProxy stats interface not accessible"
            log_message "ERROR" "HAProxy stats interface not accessible"
        fi
    fi
}

check_docker_health() {
    echo -e "\n${BLUE}=== Docker Container Health ===${NC}"
    
    local containers=("galera-haproxy" "galera-node1" "galera-node2" "galera-node3" "galera-node4")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
            local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2,$3,$4}')
            if [[ "$status" == *"Up"* ]]; then
                echo -e "  ${GREEN}✓${NC} $container: $status"
            else
                echo -e "  ${YELLOW}!${NC} $container: $status"
            fi
        else
            echo -e "  ${RED}✗${NC} $container: not running"
        fi
    done
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --continuous    Run continuous monitoring (every $CHECK_INTERVAL seconds)"
    echo "  -i, --interval N    Set check interval for continuous mode (default: $CHECK_INTERVAL)"
    echo "  -l, --log FILE      Log file path (default: $LOG_FILE)"
    echo "  -h, --help          Show this help message"
}

# Parse command line arguments
CONTINUOUS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--continuous)
            CONTINUOUS=true
            shift
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main monitoring function
run_checks() {
    print_header
    check_docker_health
    check_haproxy_stats
    check_galera_cluster
    check_connections
    echo -e "\n${BLUE}======================================${NC}\n"
}

# Run monitoring
if [ "$CONTINUOUS" = true ]; then
    echo "Starting continuous monitoring (interval: ${CHECK_INTERVAL}s, log: $LOG_FILE)"
    echo "Press Ctrl+C to stop..."
    
    while true; do
        run_checks
        sleep "$CHECK_INTERVAL"
    done
else
    run_checks
fi
