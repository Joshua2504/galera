#!/bin/bash
# Single MariaDB Node Startup Script

set -e

echo "🚀 Starting Single MariaDB Node..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Stop any existing containers
echo "🛑 Stopping existing containers..."
docker compose down --remove-orphans

# Start the single MariaDB node
echo "📦 Starting MariaDB and phpMyAdmin..."
docker compose up -d

echo "⏳ Waiting for MariaDB to be ready..."
sleep 10

# Check if MariaDB is ready
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if docker compose exec mariadb mysqladmin ping -h localhost --silent; then
        echo "✅ MariaDB is ready!"
        break
    fi
    echo "⏳ Attempt $attempt/$max_attempts - MariaDB not ready yet..."
    sleep 2
    ((attempt++))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ MariaDB failed to start within expected time"
    exit 1
fi

# Display connection information
echo ""
echo "🎉 Single MariaDB Node is ready!"
echo ""
echo "📊 Connection Details:"
echo "  - MySQL/MariaDB: localhost:3306"
echo "  - phpMyAdmin: http://localhost:22211"
echo ""
echo "🔍 Useful commands:"
echo "  - Check status: docker compose ps"
echo "  - View logs: docker compose logs -f mariadb"
echo "  - Connect to MySQL: docker compose exec mariadb mysql -uroot -p"
echo "  - Stop services: docker compose down"
echo ""
