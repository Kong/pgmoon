#!/bin/bash
# Cleanup PostgreSQL and Keycloak test instances

set -e

echo "=========================================="
echo "OAUTHBEARER Test Cleanup"
echo "=========================================="

# Stop and remove Docker containers
for container in pgmoon-oauth-test pgmoon-keycloak; do
    if docker ps -a | grep -q $container; then
        echo "Stopping $container..."
        docker stop $container 2>/dev/null || true
        docker rm $container 2>/dev/null || true
        echo "✓ $container removed"
    fi
done

# Remove Docker network
if docker network ls | grep -q pgmoon-oauth-network; then
    echo "Removing Docker network..."
    docker network rm pgmoon-oauth-network 2>/dev/null || true
    echo "✓ Network removed"
fi

echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
