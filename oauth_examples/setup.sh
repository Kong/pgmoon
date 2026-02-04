#!/bin/bash

# PostgreSQL 18 + Keycloak OAUTHBEARER Test Setup Script
# This sets up a complete OIDC authentication environment

set -e

PG_VERSION="18"
PG_PORT="${PG_PORT:-5433}"
PG_USER="${PG_USER:-postgres}"
PG_DATABASE="${PG_DATABASE:-testdb}"
KEYCLOAK_PORT="${KEYCLOAK_PORT:-8080}"

# Keycloak configuration
KEYCLOAK_ADMIN="admin"
KEYCLOAK_ADMIN_PASSWORD="admin"
REALM_NAME="pgmoon-test"
CLIENT_ID="pgmoon-client"
TEST_USER="tester"
TEST_PASSWORD="tester123"

echo "=========================================="
echo "PostgreSQL 18 + Keycloak OAUTHBEARER Setup"
echo "=========================================="
echo "PostgreSQL Port: $PG_PORT"
echo "Keycloak Port: $KEYCLOAK_PORT"
echo ""

# Create Docker network
docker network create pgmoon-oauth-network 2>/dev/null || true

# Stop any existing containers
docker stop pgmoon-oauth-test pgmoon-keycloak 2>/dev/null || true
docker rm pgmoon-oauth-test pgmoon-keycloak 2>/dev/null || true

# Start Keycloak
echo "Starting Keycloak..."
docker run -d \
    --name pgmoon-keycloak \
    --network pgmoon-oauth-network \
    -e KEYCLOAK_ADMIN=$KEYCLOAK_ADMIN \
    -e KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD \
    -p $KEYCLOAK_PORT:8080 \
    quay.io/keycloak/keycloak:26.0 \
    start-dev

echo "Waiting for Keycloak to be ready (this may take 30-60 seconds)..."
for i in {1..90}; do
    if curl -s "http://localhost:$KEYCLOAK_PORT/realms/master" > /dev/null 2>&1; then
        echo "Keycloak is ready!"
        break
    fi
    echo "Waiting... ($i/90)"
    sleep 2
done

# Get admin token
echo ""
echo "Configuring Keycloak..."
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:$KEYCLOAK_PORT/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KEYCLOAK_ADMIN" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
    echo "Failed to get admin token. Keycloak may not be ready."
    exit 1
fi

# Create realm
echo "Creating realm: $REALM_NAME"
curl -s -X POST "http://localhost:$KEYCLOAK_PORT/admin/realms" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "realm": "'"$REALM_NAME"'",
        "enabled": true,
        "accessTokenLifespan": 3600
    }' || true

# Create client
echo "Creating client: $CLIENT_ID"
curl -s -X POST "http://localhost:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "clientId": "'"$CLIENT_ID"'",
        "enabled": true,
        "publicClient": true,
        "directAccessGrantsEnabled": true,
        "standardFlowEnabled": true,
        "protocol": "openid-connect",
        "redirectUris": ["*"],
        "webOrigins": ["*"]
    }'

# Create test user
echo "Creating user: $TEST_USER"
curl -s -X POST "http://localhost:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/users" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "'"$TEST_USER"'",
        "email": "'"$TEST_USER"'@example.com",
        "firstName": "Test",
        "lastName": "User",
        "enabled": true,
        "emailVerified": true,
        "requiredActions": [],
        "credentials": [{
            "type": "password",
            "value": "'"$TEST_PASSWORD"'",
            "temporary": false
        }]
    }'

# Get client UUID and add protocol mapper for username as sub claim
CLIENT_UUID=$(curl -s "http://localhost:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

echo "Adding protocol mapper for username as sub claim..."
curl -s -X POST "http://localhost:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/protocol-mappers/models" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "username-sub-mapper",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-usermodel-property-mapper",
        "consentRequired": false,
        "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "username",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "sub",
            "jsonType.label": "String"
        }
    }' || true

echo "✓ Keycloak configured"

# Start PostgreSQL
echo ""
echo "Starting PostgreSQL $PG_VERSION..."
docker run -d \
    --name pgmoon-oauth-test \
    --network pgmoon-oauth-network \
    -e POSTGRES_PASSWORD=pgmoon \
    -e POSTGRES_USER=$PG_USER \
    -e POSTGRES_DB=$PG_DATABASE \
    -p $PG_PORT:5432 \
    postgres:${PG_VERSION}

echo "Waiting for PostgreSQL to be ready..."
sleep 5
for i in {1..30}; do
    if docker exec pgmoon-oauth-test pg_isready -U $PG_USER > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
done

# Install pg_oidc_validator
echo ""
echo "Installing pg_oidc_validator..."
docker exec pgmoon-oauth-test bash -c '
apt-get update && apt-get install -y wget curl ca-certificates
wget -q https://github.com/Percona-Lab/pg_oidc_validator/releases/download/latest/pg-oidc-validator-pgdg18.deb -O /tmp/pg-oidc-validator.deb
dpkg -i /tmp/pg-oidc-validator.deb || apt-get install -f -y
rm /tmp/pg-oidc-validator.deb
'
echo "✓ pg_oidc_validator installed"

# Configure PostgreSQL
echo ""
echo "Configuring PostgreSQL for OAUTHBEARER..."

# The issuer URL must be reachable from PostgreSQL container
ISSUER_URL="http://pgmoon-keycloak:8080/realms/$REALM_NAME"

docker exec pgmoon-oauth-test psql -U $PG_USER -c "ALTER SYSTEM SET oauth_validator_libraries TO 'pg_oidc_validator';"

# Configure pg_hba.conf
docker exec pgmoon-oauth-test bash -c "cat > /var/lib/postgresql/18/docker/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD        OPTIONS
local   all             all                                     trust
host    all             all             all                     oauth         issuer=$ISSUER_URL scope=openid
EOF"

docker exec pgmoon-oauth-test psql -U $PG_USER -c "SELECT pg_reload_conf();"
echo "✓ PostgreSQL configured"

# Create test user and table
echo ""
echo "Creating test user and table..."
docker exec -i pgmoon-oauth-test psql -U $PG_USER -d $PG_DATABASE <<EOF
CREATE ROLE $TEST_USER WITH LOGIN;
CREATE TABLE IF NOT EXISTS oauth_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
GRANT ALL PRIVILEGES ON TABLE oauth_test TO $TEST_USER;
GRANT USAGE, SELECT ON SEQUENCE oauth_test_id_seq TO $TEST_USER;
INSERT INTO oauth_test (name) VALUES 
    ('OAUTHBEARER Test'),
    ('pgmoon OAuth'),
    ('RFC 7628 Implementation')
ON CONFLICT DO NOTHING;
EOF
echo "✓ Test user and table created"

# Get a test token
echo ""
echo "Getting test OAuth token..."
TEST_TOKEN=$(curl -s -X POST "http://localhost:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$TEST_USER" \
    -d "password=$TEST_PASSWORD" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "scope=openid" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -n "$TEST_TOKEN" ]; then
    echo "✓ Test token obtained"
    # Save token to file for easy access
    echo "$TEST_TOKEN" > /tmp/pgmoon_oauth_token.txt
else
    echo "⚠ Could not obtain test token"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Keycloak Admin Console:"
echo "  URL: http://localhost:$KEYCLOAK_PORT/admin"
echo "  Username: $KEYCLOAK_ADMIN"
echo "  Password: $KEYCLOAK_ADMIN_PASSWORD"
echo ""
echo "OIDC Endpoints:"
echo "  Issuer: http://localhost:$KEYCLOAK_PORT/realms/$REALM_NAME"
echo "  Token: http://localhost:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token"
echo ""
echo "PostgreSQL:"
echo "  Host: 127.0.0.1"
echo "  Port: $PG_PORT"
echo "  User: $TEST_USER"
echo "  Database: $PG_DATABASE"
echo ""
echo "Test Credentials:"
echo "  Username: $TEST_USER"
echo "  Password: $TEST_PASSWORD"
echo "  Client ID: $CLIENT_ID"
echo ""
echo "Get a fresh token:"
echo "  curl -s -X POST 'http://localhost:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token' \\"
echo "    -d 'username=$TEST_USER&password=$TEST_PASSWORD&grant_type=password&client_id=$CLIENT_ID&scope=openid' | jq -r .access_token"
echo ""
echo "Run Lua test:"
echo "  cd .. && LUA_PATH='./?.lua;./?/init.lua;;' luajit oauth_examples/test_oauthbearer.lua"
echo ""
echo "To stop:"
echo "  ./cleanup.sh"
echo ""
echo "=========================================="
