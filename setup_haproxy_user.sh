#!/bin/bash

# Setup HAProxy health check user
# This script should be run after the Galera cluster is up and running

echo "Setting up HAProxy health check user..."

# Connect to the cluster via HAProxy (after it's running) or directly to node1
mysql -h 127.0.0.1 -P 3307 -u root -proot -e "
CREATE USER IF NOT EXISTS 'haproxy_check'@'%';
FLUSH PRIVILEGES;
"

echo "HAProxy health check user created successfully!"
