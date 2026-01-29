# OAUTHBEARER Testing

Test OAUTHBEARER SASL authentication (RFC 7628) with PostgreSQL 18 and Keycloak.

## Quick Start

```bash
# Start Keycloak + PostgreSQL 18 with pg_oidc_validator
./setup.sh

# Run the test
cd ..
LUA_PATH="./?.lua;./?/init.lua;;" luajit oauth_examples/test_oauthbearer.lua

# Cleanup
./oauth_examples/cleanup.sh
```

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Start Keycloak + PostgreSQL 18 environment |
| `test_oauthbearer.lua` | Complete test suite (unit + integration) |
| `cleanup.sh` | Stop and remove all containers |

## Test Structure

The test has two parts:

1. **Unit Tests** (no external dependencies)
   - Token validation
   - OAUTHBEARER message generation

2. **Integration Tests** (requires Docker)
   - Get OAuth token from Keycloak
   - Connect to PostgreSQL with OAUTHBEARER
   - Execute queries
   - Verify authenticated user

## GitHub CI

Add this to your workflow:

```yaml
- name: OAUTHBEARER Test
  run: |
    cd oauth_examples
    ./setup.sh
    cd ..
    LUA_PATH="./?.lua;./?/init.lua;;" luajit oauth_examples/test_oauthbearer.lua
    ./oauth_examples/cleanup.sh
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────────┐
│   pgmoon    │────▶│ PostgreSQL  │────▶│ pg_oidc_validator│
│  (Client)   │     │     18      │     │   (Validator)    │
└─────────────┘     └─────────────┘     └────────┬─────────┘
      │                                          │
      │         ┌─────────────┐                  │
      └────────▶│  Keycloak   │◀─────────────────┘
                │   (OIDC)    │
                └─────────────┘
```
