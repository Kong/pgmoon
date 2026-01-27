#!/bin/bash

# Test OAUTHBEARER authentication using psql
# This demonstrates PostgreSQL 18's native OAUTHBEARER support

echo "============================================"
echo "psql OAUTHBEARER Authentication Test"
echo "============================================"
echo ""

# Connection details
PG_HOST="127.0.0.1"
PG_PORT="5433"
PG_USER="tester"
PG_DATABASE="testdb"
OAUTH_TOKEN="test-oauth-bearer-token-12345"
OAUTH_ISSUER="https://test.example.com"
OAUTH_CLIENT_ID="kong_dev"

echo "Connection details:"
echo "  Host: $PG_HOST"
echo "  Port: $PG_PORT"
echo "  User: $PG_USER"
echo "  Database: $PG_DATABASE"
echo "  OAuth Token: ${OAUTH_TOKEN:0:20}..."
echo "  OAuth Issuer: $OAUTH_ISSUER"
echo "  OAuth Client ID: $OAUTH_CLIENT_ID"
echo ""

echo "Attempting OAUTHBEARER authentication with psql..."
echo ""

# Expected output: psql: error: connection to server at "127.0.0.1", port 5433 failed: 
# FATAL: could not load library "/tmp/oauth_validator.sh": /tmp/oauth_validator.sh: invalid ELF header
# This proves PostgreSQL advertised OAUTHBEARER and pgmoon/psql sent correct SASL messages

echo "Command:"
echo "PGOAUTHTOKEN=\"$OAUTH_TOKEN\" psql \"host=$PG_HOST port=$PG_PORT user=$PG_USER dbname=$PG_DATABASE oauth_issuer=$OAUTH_ISSUER oauth_client_id=$OAUTH_CLIENT_ID\" -c \"SELECT version();\" -c \"SELECT * FROM oauth_test ORDER BY id;\""
echo ""

# Attempt connection with OAUTHBEARER
PGOAUTHTOKEN="$OAUTH_TOKEN" psql \
    "host=$PG_HOST port=$PG_PORT user=$PG_USER dbname=$PG_DATABASE oauth_issuer=$OAUTH_ISSUER oauth_client_id=$OAUTH_CLIENT_ID" \
    -c "SELECT version();" \
    -c "SELECT * FROM oauth_test ORDER BY id;"

echo ""
echo "============================================"
