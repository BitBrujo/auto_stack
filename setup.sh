#!/bin/bash

# Setup script for n8n + Caddy + Supabase + DuckDNS
# Make sure to run this script as your regular user (not root) since you're using rootless Docker

set -e

echo "🚀 Setting up n8n + Caddy + Supabase + DuckDNS stack..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to generate random string
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to generate JWT secret
generate_jwt_secret() {
    openssl rand -base64 64 | tr -d "=+/" | cut -c1-43
}

echo -e "${YELLOW}📋 Gathering required information...${NC}"

# Get DuckDNS token
echo -e "${YELLOW}Please visit https://www.duckdns.org/ and create an account to get your token${NC}"
read -p "Enter your DuckDNS token: " DUCKDNS_TOKEN

# Get email configuration
read -p "Enter your email address for SMTP (optional, press enter to skip): " SMTP_EMAIL
if [ ! -z "$SMTP_EMAIL" ]; then
    read -s -p "Enter your email password/app password: " SMTP_PASSWORD
    echo
fi

# Get n8n password
read -s -p "Enter password for n8n admin user: " N8N_PASSWORD
echo

# Generate secrets
POSTGRES_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_jwt_secret)
ANON_KEY=$(generate_jwt_secret)
SERVICE_KEY=$(generate_jwt_secret)

echo -e "${GREEN}🔐 Generated secure passwords and keys${NC}"

# Create directory structure
echo -e "${YELLOW}📁 Creating directory structure...${NC}"
mkdir -p {caddy/{data,config},supabase/{db/{data,init},config,storage},n8n,duckdns}

# Create log directory for Caddy (if it doesn't exist in container)
mkdir -p caddy/logs

echo -e "${GREEN}✅ Directory structure created${NC}"

# Create environment file
echo -e "${YELLOW}⚙️ Creating environment configuration...${NC}"
cat > .env << EOF
# Generated on $(date)

# DuckDNS Configuration
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}

# Database Configuration
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# JWT Configuration
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_KEY=${SERVICE_KEY}

# n8n Configuration
N8N_PASSWORD=${N8N_PASSWORD}

# Email Configuration (optional)
SMTP_EMAIL=${SMTP_EMAIL}
SMTP_PASSWORD=${SMTP_PASSWORD}

# Domain
DOMAIN=humanintheloop.xyz
EOF

echo -e "${GREEN}✅ Environment file created${NC}"

# Update docker-compose.yml with generated values
echo -e "${YELLOW}🔧 Updating docker-compose.yml with generated secrets...${NC}"

# Use sed to replace placeholder values (works on both macOS and Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/your-duckdns-token-here/${DUCKDNS_TOKEN}/g" docker-compose.yml
    sed -i '' "s/your-postgres-password/${POSTGRES_PASSWORD}/g" docker-compose.yml
    sed -i '' "s/your-jwt-secret-here/${JWT_SECRET}/g" docker-compose.yml
    sed -i '' "s/your-anon-key-here/${ANON_KEY}/g" docker-compose.yml
    sed -i '' "s/your-service-key-here/${SERVICE_KEY}/g" docker-compose.yml
    sed -i '' "s/your-n8n-password/${N8N_PASSWORD}/g" docker-compose.yml
    sed -i '' "s/n8n_password/${POSTGRES_PASSWORD}/g" docker-compose.yml
    if [ ! -z "$SMTP_EMAIL" ]; then
        sed -i '' "s/your-email@gmail.com/${SMTP_EMAIL}/g" docker-compose.yml
        sed -i '' "s/your-email-password/${SMTP_PASSWORD}/g" docker-compose.yml
    fi
else
    # Linux
    sed -i "s/your-duckdns-token-here/${DUCKDNS_TOKEN}/g" docker-compose.yml
    sed -i "s/your-postgres-password/${POSTGRES_PASSWORD}/g" docker-compose.yml
    sed -i "s/your-jwt-secret-here/${JWT_SECRET}/g" docker-compose.yml
    sed -i "s/your-anon-key-here/${ANON_KEY}/g" docker-compose.yml
    sed -i "s/your-service-key-here/${SERVICE_KEY}/g" docker-compose.yml
    sed -i "s/your-n8n-password/${N8N_PASSWORD}/g" docker-compose.yml
    sed -i "s/n8n_password/${POSTGRES_PASSWORD}/g" docker-compose.yml
    if [ ! -z "$SMTP_EMAIL" ]; then
        sed -i "s/your-email@gmail.com/${SMTP_EMAIL}/g" docker-compose.yml
        sed -i "s/your-email-password/${SMTP_PASSWORD}/g" docker-compose.yml
    fi
fi

# Update Kong configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/your-anon-key-here/${ANON_KEY}/g" supabase/config/kong.yml
    sed -i '' "s/your-service-key-here/${SERVICE_KEY}/g" supabase/config/kong.yml
else
    sed -i "s/your-anon-key-here/${ANON_KEY}/g" supabase/config/kong.yml
    sed -i "s/your-service-key-here/${SERVICE_KEY}/g" supabase/config/kong.yml
fi

echo -e "${GREEN}✅ Configuration files updated${NC}"

# Create database initialization script
echo -e "${YELLOW}🗄️ Creating database initialization script...${NC}"
cat > supabase/db/init/01-init.sql << EOF
-- Create n8n database and user
CREATE DATABASE n8n;
CREATE USER n8n_user WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;

-- Create Supabase auth schema
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Create users for different Supabase services
CREATE USER supabase_auth_admin WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';
CREATE USER supabase_storage_admin WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';
CREATE USER supabase_read_only_user WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}';
CREATE USER authenticator WITH ENCRYPTED PASSWORD '${POSTGRES_PASSWORD}' NOINHERIT;

-- Grant necessary permissions
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON SCHEMA realtime TO supabase_auth_admin;
GRANT ALL ON SCHEMA _realtime TO supabase_auth_admin;
GRANT USAGE ON SCHEMA public TO authenticator;
GRANT USAGE ON SCHEMA auth TO authenticator;
GRANT USAGE ON SCHEMA storage TO authenticator;

-- Create anon and authenticated roles
CREATE ROLE anon NOLOGIN NOINHERIT;
CREATE ROLE authenticated NOLOGIN NOINHERIT;
CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;

GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- Grant permissions to anon and authenticated roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT USAGE ON SCHEMA storage TO anon, authenticated;
EOF

echo -e "${GREEN}✅ Database initialization script created${NC}"

# Set proper permissions for rootless Docker
echo -e "${YELLOW}🔐 Setting proper permissions for rootless Docker...${NC}"
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
chmod 755 setup.sh

echo -e "${GREEN}✅ Permissions set${NC}"

# Display final information
echo -e "${GREEN}🎉 Setup complete!${NC}"
echo -e "${YELLOW}📝 Important information:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🌐 Main domain: ${GREEN}https://humanintheloop.xyz${NC} (n8n)"
echo -e "🔧 Supabase Studio: ${GREEN}https://studio.humanintheloop.xyz${NC}"
echo -e "🔌 Supabase API: ${GREEN}https://api.humanintheloop.xyz${NC}"
echo -e "👤 n8n login: ${GREEN}admin${NC} / ${GREEN}${N8N_PASSWORD}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔑 Your Supabase keys:"
echo -e "   Anon key: ${GREEN}${ANON_KEY}${NC}"
echo -e "   Service key: ${GREEN}${SERVICE_KEY}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}🚀 Next steps:${NC}"
echo "1. Make sure your domain humanintheloop.xyz points to humanintheloop.duckdns.org"
echo "2. Create CNAME records:"
echo "   - humanintheloop.xyz → humanintheloop.duckdns.org"
echo "   - api.humanintheloop.xyz → humanintheloop.duckdns.org"
echo "   - studio.humanintheloop.xyz → humanintheloop.duckdns.org"
echo "3. Start the stack: docker compose up -d"
echo "4. Check logs: docker compose logs -f"
echo ""
echo -e "${RED}⚠️ Important:${NC} Save the keys above securely. You'll need them for your applications!"
echo ""
echo -e "${GREEN}💡 The .env file contains all your secrets. Keep it secure!${NC}"
EOF
