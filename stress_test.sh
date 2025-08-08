#!/bin/bash

# Galera Cluster Stress Test Script
# Usage: ./stress_test.sh [duration_in_seconds] [concurrent_connections] [operations_per_second]

# Default values
DURATION=${1:-120}  # Default 2 minutes
CONNECTIONS=${2:-20}  # Default 20 concurrent connections
OPS_PER_SEC=${3:-50}  # Operations per second per worker
HOST="127.0.0.1"
PORT="3306"
USER="root"
PASSWORD="root"
DATABASE="galera_stress_test"
MYSQL_OPTS="--protocol=TCP"

# Operation types and weights
declare -A OPERATION_WEIGHTS=(
    ["INSERT"]=40
    ["SELECT"]=35
    ["UPDATE"]=15
    ["DELETE"]=5
    ["TRANSACTION"]=5
)

echo "=== Galera Cluster Stress Test ==="
echo "Host: $HOST:$PORT"
echo "Duration: $DURATION seconds"
echo "Concurrent connections: $CONNECTIONS"
echo "Operations per second per worker: $OPS_PER_SEC"
echo "Total expected operations: $((CONNECTIONS * OPS_PER_SEC * DURATION))"
echo "=========================================="

# Check cluster status first
echo "Checking cluster status..."
mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -e "
SHOW STATUS LIKE 'wsrep_%';
" 2>/dev/null | grep -E "(wsrep_cluster_size|wsrep_local_state_comment|wsrep_ready)" || echo "Could not retrieve cluster status"

echo "Setting up test environment..."

# Create test database and tables
mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -e "
CREATE DATABASE IF NOT EXISTS $DATABASE;
USE $DATABASE;

-- Drop existing tables
DROP TABLE IF EXISTS stress_users, stress_orders, stress_products, stress_logs;

-- Users table
CREATE TABLE stress_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    status ENUM('active', 'inactive', 'banned') DEFAULT 'active',
    balance DECIMAL(10,2) DEFAULT 0.00,
    INDEX idx_username (username),
    INDEX idx_status (status),
    INDEX idx_created (created_at)
);

-- Products table
CREATE TABLE stress_products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(8,2) NOT NULL,
    stock INT DEFAULT 0,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_price (price)
);

-- Orders table
CREATE TABLE stress_orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    product_id INT,
    quantity INT DEFAULT 1,
    total DECIMAL(10,2),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'completed', 'cancelled') DEFAULT 'pending',
    FOREIGN KEY (user_id) REFERENCES stress_users(id),
    FOREIGN KEY (product_id) REFERENCES stress_products(id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_order_date (order_date)
);

-- Activity logs table
CREATE TABLE stress_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(100),
    details TEXT,
    ip_address VARCHAR(45),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_timestamp (timestamp)
);

-- Insert some initial data
INSERT INTO stress_products (name, price, stock, category) VALUES
('Product A', 19.99, 100, 'electronics'),
('Product B', 29.99, 50, 'books'),
('Product C', 9.99, 200, 'toys'),
('Product D', 49.99, 25, 'electronics'),
('Product E', 14.99, 75, 'books');
"

if [ $? -ne 0 ]; then
    echo "Error: Failed to create database/tables"
    exit 1
fi

echo "Database and tables created successfully"

# Function to get random operation based on weights
get_random_operation() {
    local rand=$((RANDOM % 100))
    local cumulative=0
    
    for op in INSERT SELECT UPDATE DELETE TRANSACTION; do
        cumulative=$((cumulative + ${OPERATION_WEIGHTS[$op]}))
        if [ $rand -lt $cumulative ]; then
            echo "$op"
            return
        fi
    done
    echo "SELECT"  # Fallback
}

# Function to perform different types of operations
perform_operation() {
    local operation=$1
    local worker_id=$2
    
    case $operation in
        "INSERT")
            # Randomly insert users, orders, or logs
            local table_choice=$((RANDOM % 3))
            case $table_choice in
                0)  # Insert user
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        INSERT INTO stress_users (username, email, balance) 
                        VALUES ('user_${worker_id}_${RANDOM}', 'user${RANDOM}@test.com', ROUND(RAND() * 1000, 2));
                    " 2>/dev/null
                    ;;
                1)  # Insert order
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        INSERT INTO stress_orders (user_id, product_id, quantity, total) 
                        SELECT u.id, p.id, FLOOR(RAND() * 5) + 1, p.price * (FLOOR(RAND() * 5) + 1)
                        FROM stress_users u, stress_products p 
                        ORDER BY RAND() LIMIT 1;
                    " 2>/dev/null
                    ;;
                2)  # Insert log
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        INSERT INTO stress_logs (user_id, action, details, ip_address) 
                        VALUES ((SELECT id FROM stress_users ORDER BY RAND() LIMIT 1), 
                                'action_${RANDOM}', 'Worker ${worker_id} activity', 
                                CONCAT(FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255)));
                    " 2>/dev/null
                    ;;
            esac
            ;;
            
        "SELECT")
            # Various complex SELECT queries
            local query_type=$((RANDOM % 5))
            case $query_type in
                0)  # User statistics
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        SELECT status, COUNT(*) as count, AVG(balance) as avg_balance 
                        FROM stress_users 
                        WHERE created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR) 
                        GROUP BY status;
                    " 2>/dev/null >/dev/null
                    ;;
                1)  # Order analysis
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        SELECT p.category, SUM(o.total) as revenue, COUNT(*) as orders
                        FROM stress_orders o 
                        JOIN stress_products p ON o.product_id = p.id 
                        WHERE o.order_date > DATE_SUB(NOW(), INTERVAL 30 MINUTE)
                        GROUP BY p.category 
                        ORDER BY revenue DESC;
                    " 2>/dev/null >/dev/null
                    ;;
                2)  # User activity
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        SELECT u.username, COUNT(l.id) as activity_count
                        FROM stress_users u 
                        LEFT JOIN stress_logs l ON u.id = l.user_id 
                        WHERE l.timestamp > DATE_SUB(NOW(), INTERVAL 15 MINUTE)
                        GROUP BY u.id, u.username 
                        HAVING activity_count > 0 
                        ORDER BY activity_count DESC LIMIT 10;
                    " 2>/dev/null >/dev/null
                    ;;
                3)  # Product performance
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        SELECT p.name, p.stock, COUNT(o.id) as orders, SUM(o.quantity) as sold
                        FROM stress_products p 
                        LEFT JOIN stress_orders o ON p.id = o.product_id
                        GROUP BY p.id 
                        ORDER BY sold DESC;
                    " 2>/dev/null >/dev/null
                    ;;
                4)  # Complex join
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        SELECT DATE(o.order_date) as date, 
                               COUNT(DISTINCT u.id) as active_users,
                               COUNT(o.id) as total_orders,
                               SUM(o.total) as revenue
                        FROM stress_orders o
                        JOIN stress_users u ON o.user_id = u.id
                        WHERE o.order_date > DATE_SUB(NOW(), INTERVAL 2 HOUR)
                        GROUP BY DATE(o.order_date);
                    " 2>/dev/null >/dev/null
                    ;;
            esac
            ;;
            
        "UPDATE")
            # Various UPDATE operations
            local update_type=$((RANDOM % 3))
            case $update_type in
                0)  # Update user balance
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        UPDATE stress_users 
                        SET balance = balance + ROUND((RAND() - 0.5) * 100, 2),
                            last_login = NOW()
                        WHERE id = (SELECT id FROM (SELECT id FROM stress_users ORDER BY RAND() LIMIT 1) as t);
                    " 2>/dev/null
                    ;;
                1)  # Update product stock
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        UPDATE stress_products 
                        SET stock = GREATEST(0, stock + FLOOR((RAND() - 0.5) * 20))
                        WHERE id = (SELECT id FROM (SELECT id FROM stress_products ORDER BY RAND() LIMIT 1) as t);
                    " 2>/dev/null
                    ;;
                2)  # Update order status
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        UPDATE stress_orders 
                        SET status = CASE 
                            WHEN RAND() > 0.8 THEN 'completed'
                            WHEN RAND() > 0.9 THEN 'cancelled'
                            ELSE status
                        END
                        WHERE status = 'pending' AND id = (
                            SELECT id FROM (SELECT id FROM stress_orders WHERE status = 'pending' ORDER BY RAND() LIMIT 1) as t
                        );
                    " 2>/dev/null
                    ;;
            esac
            ;;
            
        "DELETE")
            # Cleanup old data
            local delete_type=$((RANDOM % 2))
            case $delete_type in
                0)  # Delete old logs
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        DELETE FROM stress_logs 
                        WHERE timestamp < DATE_SUB(NOW(), INTERVAL 2 HOUR) 
                        LIMIT 10;
                    " 2>/dev/null
                    ;;
                1)  # Delete cancelled orders
                    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                        DELETE FROM stress_orders 
                        WHERE status = 'cancelled' AND order_date < DATE_SUB(NOW(), INTERVAL 1 HOUR) 
                        LIMIT 5;
                    " 2>/dev/null
                    ;;
            esac
            ;;
            
        "TRANSACTION")
            # Complex transaction
            mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
                START TRANSACTION;
                
                INSERT INTO stress_users (username, email, balance) 
                VALUES ('txn_user_${worker_id}_${RANDOM}', 'txn${RANDOM}@test.com', 100.00);
                
                SET @user_id = LAST_INSERT_ID();
                
                INSERT INTO stress_orders (user_id, product_id, quantity, total) 
                SELECT @user_id, id, 1, price FROM stress_products ORDER BY RAND() LIMIT 1;
                
                INSERT INTO stress_logs (user_id, action, details) 
                VALUES (@user_id, 'account_created', 'New user with first order');
                
                COMMIT;
            " 2>/dev/null
            ;;
    esac
}

# High-intensity stress worker
stress_worker() {
    local worker_id=$1
    local end_time=$(($(date +%s) + DURATION))
    local operations=0
    local sleep_interval=$(echo "scale=3; 1.0 / $OPS_PER_SEC" | bc -l)
    
    echo "Worker $worker_id started (target: $OPS_PER_SEC ops/sec, sleep: ${sleep_interval}s)"
    
    while [ $(date +%s) -lt $end_time ]; do
        local operation=$(get_random_operation)
        perform_operation "$operation" "$worker_id"
        operations=$((operations + 1))
        
        # Adaptive sleep to maintain target ops/sec
        if [ $(echo "$sleep_interval > 0" | bc -l) -eq 1 ]; then
            sleep "$sleep_interval"
        fi
    done
    
    echo "Worker $worker_id completed $operations operations"
}

# Start worker processes
echo "Starting $CONNECTIONS worker processes..."
pids=()
for i in $(seq 1 $CONNECTIONS); do
    stress_worker $i &
    pids+=($!)
    echo "Started worker $i (PID: $!)"
done

# Monitor progress with detailed metrics
start_time=$(date +%s)
monitor_interval=10

while [ $(($(date +%s) - start_time)) -lt $DURATION ]; do
    current_time=$(date)
    elapsed=$(($(date +%s) - start_time))
    
    # Get table counts
    users=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_users;" 2>/dev/null)
    orders=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_orders;" 2>/dev/null)
    products=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_products;" 2>/dev/null)
    logs=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_logs;" 2>/dev/null)
    
    # Get cluster status
    cluster_size=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -se "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')
    cluster_status=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -se "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print $2}')
    
    # Get connection count
    connections=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -se "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
    
    echo "[$elapsed/${DURATION}s] Users:$users Orders:$orders Logs:$logs | Cluster:$cluster_size($cluster_status) Conns:$connections"
    
    sleep $monitor_interval
done

# Wait for all workers to complete
echo "Waiting for workers to complete..."
for pid in "${pids[@]}"; do
    wait $pid
done

# Final comprehensive statistics
echo "=== Final Comprehensive Statistics ==="
echo "Test Duration: $DURATION seconds with $CONNECTIONS concurrent workers"

# Table counts
users=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_users;" 2>/dev/null)
orders=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_orders;" 2>/dev/null)
products=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_products;" 2>/dev/null)
logs=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -se "SELECT COUNT(*) FROM stress_logs;" 2>/dev/null)

echo "Final Record Counts:"
echo "  Users: $users"
echo "  Orders: $orders"
echo "  Products: $products"
echo "  Logs: $logs"
echo "  Total Records: $((users + orders + products + logs))"

# Performance metrics
echo ""
echo "=== Performance Analysis ==="
mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" "$DATABASE" -e "
SELECT 
    'Order Statistics' as metric,
    COUNT(*) as total_orders,
    AVG(total) as avg_order_value,
    SUM(total) as total_revenue,
    COUNT(DISTINCT user_id) as unique_customers
FROM stress_orders
UNION ALL
SELECT 
    'User Activity' as metric,
    COUNT(DISTINCT l.user_id) as active_users,
    COUNT(l.id) as total_actions,
    AVG(u.balance) as avg_balance,
    COUNT(CASE WHEN u.status = 'active' THEN 1 END) as active_accounts
FROM stress_users u 
LEFT JOIN stress_logs l ON u.id = l.user_id;
" 2>/dev/null

# Cluster health and load balancing test
echo ""
echo "=== Cluster Health & Load Balancing Test ==="
declare -A node_connections

for i in {1..30}; do
    result=$(mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -e "SELECT @@hostname;" 2>/dev/null | tail -n 1)
    if [[ -n "$result" ]]; then
        node_connections["$result"]=$((${node_connections["$result"]} + 1))
    fi
    sleep 0.1
done

echo "Connection distribution across nodes:"
for node in "${!node_connections[@]}"; do
    echo "  $node: ${node_connections[$node]} connections"
done

# Final cluster status
echo ""
echo "=== Final Cluster Status ==="
mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -e "
SHOW STATUS WHERE Variable_name IN (
    'wsrep_cluster_size',
    'wsrep_local_state_comment', 
    'wsrep_ready',
    'wsrep_cluster_status',
    'wsrep_local_recv_queue_avg',
    'wsrep_local_send_queue_avg',
    'wsrep_flow_control_paused_ns',
    'wsrep_cert_deps_distance'
);
" 2>/dev/null

echo ""
echo "Galera cluster stress test completed!"
echo "Check HAProxy stats: http://localhost:8080/stats"
echo "=========================================="

# Cleanup option
read -p "Do you want to drop the test database? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mysql -h "$HOST" -P "$PORT" $MYSQL_OPTS -u "$USER" -p"$PASSWORD" -e "DROP DATABASE IF EXISTS $DATABASE;"
    echo "Test database dropped"
fi
