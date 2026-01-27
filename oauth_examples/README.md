# OAUTHBEARER Testing Examples

## Goal

Test OAUTHBEARER SASL authentication (RFC 7628) with PostgreSQL 18.

## Start PostgreSQL Server

```bash
# Start PostgreSQL 18 with OAUTHBEARER support
./setup_pg18_oauth.sh

# Stop PostgreSQL
./cleanup_pg18.sh
```

## Run Client Tests

### Lua (pgmoon)
```bash
cd ..
LUA_PATH="./?.lua;./?/init.lua;;" lua oauth_examples/test_oauthbearer.lua
```

### Shell (psql)
```bash
./test_oauthbearer.sh
```

### Python
```bash
./test_oauthbearer.py
```

## Expected Result

**Shell (psql) and Python:**
```
FATAL: could not load library "/tmp/oauth_validator.sh": invalid ELF header
```

**Lua (pgmoon):**
```
Error: receive_message: failed to get type: closed
```
(Connection closes before full error received - same underlying cause)

This proves OAUTHBEARER SASL messages were sent correctly.
