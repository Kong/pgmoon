#!/bin/bash

# PostgreSQL 18 OAUTHBEARER Test Setup Script
# This configures PostgreSQL 18 to advertise OAUTHBEARER in its SASL mechanism list
# so we can test the pgmoon OAUTHBEARER implementation (RFC 7628)

set -e

PG_VERSION="18"
PG_PORT="${PG_PORT:-5433}"
PG_USER="${PG_USER:-postgres}"
PG_DATABASE="${PG_DATABASE:-testdb}"

echo "=========================================="
echo "PostgreSQL 18 OAUTHBEARER Setup"
echo "=========================================="
echo "Port: $PG_PORT"
echo "User: $PG_USER"
echo "Database: $PG_DATABASE"
echo ""

# Stop any existing container
docker stop pgmoon-oauth-test 2>/dev/null || true
docker rm pgmoon-oauth-test 2>/dev/null || true

# Start PostgreSQL container
docker run -d \
    --name pgmoon-oauth-test \
    -e POSTGRES_PASSWORD=pgmoon \
    -e POSTGRES_USER=$PG_USER \
    -e POSTGRES_DB=$PG_DATABASE \
    -p $PG_PORT:5432 \
    postgres:${PG_VERSION}

echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if docker exec pgmoon-oauth-test pg_isready -U $PG_USER > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
done

echo ""
echo "Configuring PostgreSQL 18 to advertise OAUTHBEARER..."

# Create a simple OAuth validator stub (for testing only)
# Note: PostgreSQL expects a shared library (.so), not a bash script
# This will cause auth to fail, but PostgreSQL will still advertise OAUTHBEARER
docker exec pgmoon-oauth-test bash -c 'cat > /tmp/oauth_validator.sh <<'\''VALIDATOR'\''
#!/bin/bash
# Simple OAuth validator stub for testing
# In production, use a proper shared library that validates OAuth tokens
exit 0
VALIDATOR
chmod +x /tmp/oauth_validator.sh'

# Configure OAuth validator library
docker exec pgmoon-oauth-test psql -U $PG_USER -c "ALTER SYSTEM SET oauth_validator_libraries TO '/tmp/oauth_validator.sh';"

# Configure pg_hba.conf to use 'oauth' method
# This forces PostgreSQL to advertise OAUTHBEARER in SASL mechanism list
docker exec pgmoon-oauth-test bash -c 'cat > /var/lib/postgresql/18/docker/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD        OPTIONS
local   all             all                                     trust
host    all             all             all                     oauth         scope=openid issuer=https://test.example.com
EOF'

# Reload configuration
docker exec pgmoon-oauth-test psql -U $PG_USER -c "SELECT pg_reload_conf();"

echo "✓ PostgreSQL configured to advertise OAUTHBEARER"
echo "  Note: Using test validator stub (auth will fail, but demonstrates SASL flow)"
sleep 2

# Create test user and database
echo ""
echo "Creating test user and table..."
docker exec -i pgmoon-oauth-test psql -U $PG_USER -d $PG_DATABASE <<EOF
-- Create a test role that matches OAuth token subject
CREATE ROLE tester WITH LOGIN;

-- Create test table
CREATE TABLE IF NOT EXISTS oauth_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Grant access to tester role
GRANT ALL PRIVILEGES ON TABLE oauth_test TO tester;
GRANT USAGE, SELECT ON SEQUENCE oauth_test_id_seq TO tester;

-- Insert test data
INSERT INTO oauth_test (name) VALUES 
    ('OAUTHBEARER Test'),
    ('pgmoon OAuth'),
    ('RFC 7628 Implementation')
ON CONFLICT DO NOTHING;
EOF

echo "✓ Test user and table created"

echo ""
echo "=========================================="
echo "PostgreSQL 18 is ready for OAUTHBEARER!"
echo "=========================================="
echo ""
echo "Connection details:"
echo "  Host: 127.0.0.1"
echo "  Port: $PG_PORT"
echo "  User: tester"
echo "  Database: $PG_DATABASE"
echo "  Auth Method: oauth (advertises OAUTHBEARER)"
echo ""
echo "PostgreSQL will advertise OAUTHBEARER in its SASL"
echo "mechanism list, allowing pgmoon to send RFC 7628"
echo "compliant OAUTHBEARER messages."
echo ""
echo "Note: Authentication will fail (invalid ELF header)"
echo "because we use a bash script instead of a proper"
echo "validator library, but this successfully demonstrates"
echo "that pgmoon sends correct OAUTHBEARER SASL messages."
echo ""
echo "To stop the container:"
echo "  docker stop pgmoon-oauth-test"
echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
