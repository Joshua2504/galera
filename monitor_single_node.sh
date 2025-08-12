#!/bin/bash
# Single MariaDB Node Monitoring Script

set -e

echo "📊 MariaDB Single Node Status Monitor"
echo "======================================"

# Check if container is running
if docker compose ps mariadb | grep -q "Up"; then
    echo "✅ Container Status: Running"
else
    echo "❌ Container Status: Not Running"
    exit 1
fi

echo ""
echo "🔍 Database Status:"
echo "-------------------"

# Get basic database info
docker compose exec mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "
SELECT 
    'Database Server' as Component,
    VERSION() as Version,
    USER() as 'Current User',
    DATABASE() as 'Current Database',
    NOW() as 'Server Time';

SELECT 
    'Connection Info' as Component,
    CONNECTION_ID() as 'Connection ID',
    @@hostname as 'Hostname',
    @@port as 'Port',
    @@socket as 'Socket';

SHOW DATABASES;

SELECT 
    table_schema as 'Database',
    COUNT(*) as 'Tables'
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY table_schema;
" 2>/dev/null || {
    echo "❌ Failed to connect to database. Please check if MariaDB is running and password is correct."
    exit 1
}

echo ""
echo "💾 Container Resources:"
echo "----------------------"
docker stats mariadb --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

echo ""
echo "📈 Recent Logs (last 10 lines):"
echo "--------------------------------"
docker compose logs --tail=10 mariadb

echo ""
echo "🔧 Quick Commands:"
echo "  - Full logs: docker compose logs -f mariadb"
echo "  - MySQL shell: docker compose exec mariadb mysql -uroot -p"
echo "  - Restart: docker compose restart mariadb"
echo ""
