#!/bin/bash
# Setup PostgreSQL 18 instance for OAUTHBEARER testing

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PG_VERSION="${PG_VERSION:-18}"
PG_PORT="${PG_PORT:-5433}"
PG_DATA="${PG_DATA:-$SCRIPT_DIR/pg_data}"
PG_USER="${PG_USER:-postgres}"
PG_DATABASE="${PG_DATABASE:-testdb}"

echo "=========================================="
echo "PostgreSQL ${PG_VERSION} OAUTHBEARER Setup"
echo "=========================================="
echo "Port: $PG_PORT"
echo "Data Dir: $PG_DATA"
echo "User: $PG_USER"
echo "Database: $PG_DATABASE"
echo ""

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL is not installed. Installing via Docker..."
    USE_DOCKER=true
else
    echo "PostgreSQL found: $(psql --version)"
    USE_DOCKER=false
fi

if [ "$USE_DOCKER" = true ]; then
    echo ""
    echo "Starting PostgreSQL ${PG_VERSION} in Docker..."
    
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
    
    PGHOST="127.0.0.1"
    PGPORT=$PG_PORT
    PGUSER=$PG_USER
    PGPASSWORD="pgmoon"
    PGDATABASE=$PG_DATABASE
    
    echo ""
    echo "PostgreSQL is running in Docker!"
    echo ""
    echo "Connection details:"
    echo "  Host: $PGHOST"
    echo "  Port: $PGPORT"
    echo "  User: $PGUSER"
    echo "  Password: $PGPASSWORD"
    echo "  Database: $PGDATABASE"
    echo ""
    echo "To connect manually:"
    echo "  PGPASSWORD=$PGPASSWORD psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE"
    echo ""
    echo "To stop the container:"
    echo "  docker stop pgmoon-oauth-test"
    echo ""
    echo "Note: Standard PostgreSQL doesn't support OAUTHBEARER by default."
    echo "This setup provides a basic PostgreSQL instance for testing other auth methods."
    echo "For full OAUTHBEARER testing, you would need a PostgreSQL instance with"
    echo "OAUTHBEARER support (requires custom extensions or cloud provider support)."
    
else
    # Local PostgreSQL installation
    echo ""
    echo "Setting up local PostgreSQL instance..."
    
    # Initialize data directory if it doesn't exist
    if [ ! -d "$PG_DATA" ]; then
        echo "Initializing PostgreSQL data directory..."
        initdb -D "$PG_DATA" -U "$PG_USER"
    fi
    
    # Configure PostgreSQL
    cat >> "$PG_DATA/postgresql.conf" <<EOF

# Custom configuration for testing
port = $PG_PORT
listen_addresses = 'localhost'
max_connections = 100
shared_buffers = 128MB
EOF
    
    # Configure authentication
    cat > "$PG_DATA/pg_hba.conf" <<EOF
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
# IPv6 local connections:
host    all             all             ::1/128                 md5
EOF
    
    echo "Starting PostgreSQL server..."
    pg_ctl -D "$PG_DATA" -l "$PG_DATA/logfile" start
    
    # Wait for server to start
    sleep 2
    
    # Create database
    createdb -p $PG_PORT -U $PG_USER $PG_DATABASE 2>/dev/null || echo "Database already exists"
    
    echo ""
    echo "PostgreSQL is running!"
    echo ""
    echo "Connection details:"
    echo "  Host: localhost"
    echo "  Port: $PG_PORT"
    echo "  User: $PG_USER"
    echo "  Database: $PG_DATABASE"
    echo ""
    echo "To connect manually:"
    echo "  psql -p $PG_PORT -U $PG_USER -d $PG_DATABASE"
    echo ""
    echo "To stop the server:"
    echo "  pg_ctl -D $PG_DATA stop"
fi

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
