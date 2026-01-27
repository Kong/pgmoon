#!/bin/bash
# Cleanup PostgreSQL test instance

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PG_DATA="${PG_DATA:-$SCRIPT_DIR/pg_data}"

echo "=========================================="
echo "PostgreSQL Cleanup"
echo "=========================================="

# Check if running in Docker
if docker ps | grep -q pgmoon-oauth-test; then
    echo "Stopping Docker container..."
    docker stop pgmoon-oauth-test
    docker rm pgmoon-oauth-test
    echo "✓ Docker container removed"
else
    # Stop local PostgreSQL instance
    if [ -d "$PG_DATA" ]; then
        echo "Stopping PostgreSQL server..."
        pg_ctl -D "$PG_DATA" stop -m fast 2>/dev/null || true
        echo "✓ PostgreSQL server stopped"
        
        echo "Removing data directory..."
        rm -rf "$PG_DATA"
        echo "✓ Data directory removed"
    else
        echo "No PostgreSQL data directory found"
    fi
fi

echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
