# n8n + Caddy + Supabase + DuckDNS Stack

This is a complete self-hosted stack with automatic HTTPS, dynamic DNS, and authentication.

## 🏗️ Architecture

```
Internet → DuckDNS → Your Router → Caddy (Reverse Proxy) → Services
                                         ├── n8n (Main App)
                                         ├── Supabase API
                                         └── Supabase Studio
```

### Services Overview

- **DuckDNS**: Updates your dynamic IP automatically
- **Caddy**: Reverse proxy with automatic HTTPS certificates
- **n8n**: Workflow automation platform with PostgreSQL backend
- **Supabase**: Complete backend-as-a-service with PostgreSQL
- **PostgreSQL**: Shared database for both n8n and Supabase

## 🚀 Quick Start

1. **Clone/Download the files** and navigate to the directory
2. **Run the setup script**: `chmod +x setup.sh && ./setup.sh`
3. **Configure DNS** (see DNS Setup section below)
4. **Start the stack**: `docker compose up -d`

## 🌐 DNS Setup

### Step 1: DuckDNS Setup
1. Go to [duckdns.org](https://www.duckdns.org/) and sign up
2. Create a subdomain: `humanintheloop`
3. Your DuckDNS URL will be: `humanintheloop.duckdns.org`

### Step 2: Domain DNS Records
Create these CNAME records in your domain registrar's DNS settings:

```
humanintheloop.xyz → humanintheloop.duckdns.org
api.humanintheloop.xyz → humanintheloop.duckdns.org
studio.humanintheloop.xyz → humanintheloop.duckdns.org
www.humanintheloop.xyz → humanintheloop.duckdns.org
```

### Step 3: Router Port Forwarding
Forward these ports to your server's local IP:
- Port 80 (HTTP) → Your server IP:80
- Port 443 (HTTPS) → Your server IP:443

## 🔧 Management Commands

### Basic Operations
```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f

# View logs for specific service
docker compose logs -f n8n
docker compose logs -f caddy

# Restart a service
docker compose restart n8n

# Update services
docker compose pull
docker compose up -d
```

### Database Operations
```bash
# Connect to PostgreSQL
docker compose exec db psql -U supabase_admin -d postgres

# Backup database
docker compose exec db pg_dump -U supabase_admin postgres > backup.sql

# Restore database
cat backup.sql | docker compose exec -T db psql -U supabase_admin -d postgres
```

### Health Checks
```bash
# Check service status
docker compose ps

# Check disk usage
docker system df

# Clean up unused images
docker system prune -a
```

## 🔑 Access Information

| Service | URL | Credentials |
|---------|-----|-------------|
| n8n | https://humanintheloop.xyz | admin / [your-password] |
| Supabase Studio | https://studio.humanintheloop.xyz | Use your Supabase keys |
| Supabase API | https://api.humanintheloop.xyz | Use your Supabase keys |

## 🔐 Security Features

- **Automatic HTTPS**: Caddy handles SSL/TLS certificates via Let's Encrypt
- **Basic Auth**: n8n protected with username/password
- **JWT Authentication**: Supabase uses JWT tokens
- **Security Headers**: Caddy adds security headers automatically
- **Database Isolation**: Separate users and permissions for each service

## 🛠️ Configuration Files

### Key Files
- `docker-compose.yml`: Main service definitions
- `caddy/Caddyfile`: Reverse proxy configuration
- `supabase/config/kong.yml`: API gateway configuration
- `.env`: Environment variables and secrets

### Important Directories
```
├── caddy/
│   ├── Caddyfile
│   ├── data/          # SSL certificates
│   └── config/        # Caddy config
├── supabase/
│   ├── config/
│   │   └── kong.yml
│   ├── db/
│   │   ├── data/      # PostgreSQL data
│   │   └── init/      # Initialization scripts
│   └── storage/       # File storage
├── n8n/               # n8n workflows and data
└── duckdns/           # DuckDNS logs
```

## 🔧 Troubleshooting

### Common Issues

**Services won't start**
```bash
# Check logs
docker compose logs

# Check disk space
df -h

# Check Docker daemon
systemctl status docker
```

**SSL Certificate Issues**
```bash
# Check Caddy logs
docker compose logs caddy

# Restart Caddy
docker compose restart caddy

# Clear SSL data (will regenerate)
sudo rm -rf caddy/data/caddy/certificates
docker compose restart caddy
```

**Database Connection Issues**
```bash
# Check database logs
docker compose logs db

# Test database connection
docker compose exec db psql -U supabase_admin -d postgres -c "SELECT version();"
```

**DuckDNS Not Updating**
```bash
# Check DuckDNS logs
docker compose logs duckdns

# Manually trigger update
curl "https://www.duckdns.org/update?domains=humanintheloop&token=YOUR_TOKEN&ip="
```

### Performance Optimization

**For Low-Memory Systems**
```yaml
# Add to services that need less memory
deploy:
  resources:
    limits:
      memory: 512M
```

**Database Tuning**
Edit `supabase/db/init/02-tuning.sql`:
```sql
-- Optimize for small systems
ALTER SYSTEM SET shared_buffers = '128MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
```

## 🔄 Backup Strategy

### Automated Backup Script
Create `backup.sh`:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"

mkdir -p $BACKUP_DIR

# Database backup
docker compose exec -T db pg_dump -U supabase_admin postgres > $BACKUP_DIR/db_$DATE.sql

# n8n data backup
tar -czf $BACKUP_DIR/n8n_$DATE.tar.gz n8n/

# Supabase storage backup
tar -czf $BACKUP_DIR/storage_$DATE.tar.gz supabase/storage/

# Keep only last 7 days
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

### Restore Process
```bash
# Restore database
cat backups/db_YYYYMMDD_HHMMSS.sql | docker compose exec -T db psql -U supabase_admin -d postgres

# Restore n8n data
docker compose down
tar -xzf backups/n8n_YYYYMMDD_HHMMSS.tar.gz
docker compose up -d
```

## 🚀 Advanced Usage

### Custom n8n Nodes
```bash
# Add custom nodes to n8n
docker compose exec n8n npm install n8n-nodes-[package-name]
docker compose restart n8n
```

### Supabase Edge Functions
```bash
# Install Supabase CLI
npm install -g supabase

# Initialize project
supabase init

# Deploy edge functions
supabase functions deploy [function-name]
```

### Monitoring Setup
Add to `docker-compose.yml`:
```yaml
  # Optional: Add monitoring
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
```

## 📱 Mobile Access

Your services are accessible from anywhere:
- **n8n Mobile**: Use the web interface on mobile browsers
- **Supabase**: Full API access from mobile apps
- **Progressive Web App**: n8n can be installed as a PWA

## 🔗 Integration Examples

### Connect n8n to Supabase
1. In n8n, use HTTP Request node
2. URL: `https://api.humanintheloop.xyz/rest/v1/[table]`
3. Headers: `Authorization: Bearer [your-service-key]`

### Webhook Setup
- n8n webhooks: `https://humanintheloop.xyz/webhook/[webhook-id]`
- Supabase webhooks: Configure in Supabase Studio

## 📞 Support

- **n8n Docs**: [docs.n8n.io](https://docs.n8n.io)
- **Supabase Docs**: [supabase.com/docs](https://supabase.com/docs)
- **Caddy Docs**: [caddyserver.com/docs](https://caddyserver.com/docs)
- **Docker Compose**: [docs.docker.com](https://docs.docker.com/compose/)

---

**⚠️ Security Note**: Keep your `.env` file secure and never commit it to version control. All passwords and keys are randomly generated during setup.
