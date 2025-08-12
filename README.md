# Single MariaDB Node with phpMyAdmin

Docker Compose setup for a single MariaDB node with phpMyAdmin for database management.

## Quick Start

1. **Copy environment file**: Copy `.env.example` to `.env` and adjust values as needed:
   ```bash
   cp .env.example .env
   ```

2. **Configure environment**: Edit `.env` to set your desired configuration:
   - **Required**: Set a secure `MYSQL_ROOT_PASSWORD` 
   - **Optional**: Set `DATABASE_HOST_PORT` if you want a custom host port (leave blank for default port 3306)
   - **Optional**: Adjust resource limits and other settings

3. **Start the database** (recommended):
   ```bash
   ./startup_single_node.sh
   ```
   
   Or use basic Docker Compose:
   ```bash
   docker compose up -d
   ```

4. **Access points**:
   - **MySQL/MariaDB**: `localhost:3306` (or custom port if set)
   - **phpMyAdmin**: `http://localhost:${PHPMYADMIN_HOST_PORT:-22211}`

## Environment Variables

**Core Settings**:
- `MYSQL_ROOT_PASSWORD` - Root password (⚠️ **REQUIRED** - change from default!)
- `MYSQL_DATABASE` - Optional initial database to create

**Container Images**:
- `MARIADB_IMAGE` - MariaDB Docker image (default: `mariadb:10.11`) 
- `PHPMYADMIN_IMAGE` - phpMyAdmin Docker image (default: `phpmyadmin/phpmyadmin`)

**Port Configuration**:
- `PHPMYADMIN_HOST_PORT` - Host port for phpMyAdmin (default: `22211`)
- `DATABASE_HOST_PORT` - Direct database access port (leave blank for default 3306)

**phpMyAdmin Settings**:
- `UPLOAD_LIMIT` - File upload size limit (default: `300M`)

**Resource Limits** (Docker Compose deploy section):
- `DATABASE_CPUS` / `DATABASE_MEMORY` - MariaDB database resource limits  
- `PHPMYADMIN_CPUS` / `PHPMYADMIN_MEMORY` - phpMyAdmin resource limits

**phpMyAdmin**: Web-based MySQL administration interface
- Connects directly to the MariaDB node
- Provides easy database management through a web UI

## Management Scripts

**🚀 Start Single Node**:
```bash
./startup_single_node.sh
```

**📊 Monitor Node Status**:
```bash
./monitor_single_node.sh
```

**Basic Docker Commands**:
```bash
# Start services
docker compose up -d

# Stop services  
docker compose down

# View logs
docker compose logs -f mariadb

# Connect to MySQL
docker compose exec mariadb mysql -uroot -p
```

## Security Considerations

**🔐 Essential Security Steps**:

1. **Change Default Password**: Always modify `MYSQL_ROOT_PASSWORD` in `.env` before deployment
2. **Limit Exposure**: Use firewall rules to restrict database access beyond local development  
3. **User Management**: Create dedicated application users instead of using root

**⚠️ Production Hardening**:
- Create dedicated application users with limited privileges
- Disable root remote login if not needed
- Use strong, rotated passwords with proper secrets management
- Enable SSL/TLS for MySQL connections
- Consider network-level encryption (VPN, service mesh)

## Common Operations

### Basic Database Operations

**Check database status**:
```bash
docker compose exec mariadb mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION(), USER(), NOW();"
```

**List databases**:
```bash
docker compose exec mariadb mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"
```

**Connect to MySQL shell**:
```bash
docker compose exec mariadb mysql -uroot -p"$MYSQL_ROOT_PASSWORD"
```

**Run SQL commands**:
```bash
docker compose exec mariadb mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE myapp; SHOW DATABASES;"
```

### Container Management

**Update images and restart**:
```bash
docker compose pull
docker compose up -d --remove-orphans
```

**View container status**:
```bash
docker compose ps
```

**View logs** (specific service):
```bash
docker compose logs -f mariadb
docker compose logs -f phpmyadmin
```

## Troubleshooting

### Common Issues & Solutions

**❌ Database won't start**:
```bash
# Check logs for specific error
docker compose logs mariadb

# Common fix: ensure proper permissions on data directory
sudo chown -R 999:999 ./mariadb/data
```

**❌ Can't connect to database**:
- Verify `MYSQL_ROOT_PASSWORD` in `.env` matches what was used during initialization
- Check if container is running: `docker compose ps mariadb`
- Test connection: `docker compose exec mariadb mysqladmin ping -h localhost`

**❌ phpMyAdmin connection errors**:
- Ensure MariaDB is running first
- Check phpMyAdmin logs: `docker compose logs phpmyadmin`
- Verify network connectivity: `docker compose exec phpmyadmin ping mariadb`

**❌ Port not accessible from host**:
- Check if port is exposed: `docker compose port mariadb 3306`
- Verify no port conflicts: `netstat -ln | grep :3306`
- Ensure firewall allows connections

**❌ Permission denied / authentication errors**:
- Verify `MYSQL_ROOT_PASSWORD` matches initialized data
- For complete reset (⚠️ **DATA LOSS**): Remove `./mariadb/data/` directory

### Reset Database (Development Only)

**⚠️ WARNING**: This destroys all data!
```bash
docker compose down
sudo rm -rf ./mariadb/data/
docker compose up -d
```

## Performance Benefits of Single Node

Compared to a traditional multi-node cluster setup, this single node configuration provides:

- **Reduced Latency**: No proxy overhead or cluster synchronization delays
- **Simplified Troubleshooting**: Single point of failure makes debugging easier  
- **Lower Resource Usage**: Eliminates HAProxy (0.5 CPU, 512MB RAM) and 3 extra database nodes
- **Faster Writes**: No need to synchronize across multiple nodes
- **Simpler Backup/Recovery**: Single data directory to manage

## Development vs Production

This setup is optimized for **development and testing**. For production use:

- [ ] Enable SSL/TLS for MySQL connections
- [ ] Implement proper secrets management (not `.env` files)
- [ ] Add comprehensive monitoring (Prometheus, Grafana)
- [ ] Configure log aggregation and rotation  
- [ ] Set up automated backups with point-in-time recovery
- [ ] Implement network security (firewalls, VPNs)
- [ ] Use dedicated servers with proper resource allocation
- [ ] Enable audit logging for compliance
- [ ] Consider read replicas for read-heavy workloads
- [ ] Test disaster recovery procedures

**Maintained for development & testing scenarios. Thoroughly test and harden before production use.**
