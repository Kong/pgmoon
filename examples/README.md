# pgmoon OAUTHBEARER Examples

This directory contains examples and test scripts for the OAUTHBEARER authentication implementation in pgmoon.

## Files

### Test Scripts

- **`test_oauthbearer.lua`** - Comprehensive test script that validates the OAUTHBEARER implementation
- **`oauthbearer_example.lua`** - Usage examples demonstrating OAUTHBEARER authentication

### Setup Scripts

- **`setup_pg18_oauth.sh`** - Sets up a PostgreSQL instance for testing (supports both Docker and local installation)
- **`cleanup_pg18.sh`** - Cleans up the PostgreSQL test instance

## Quick Start

### 1. Setup PostgreSQL Test Instance

```bash
cd examples
./setup_pg18_oauth.sh
```

This will:
- Start a PostgreSQL instance on port 5433
- Create a test database named `testdb`
- Configure trust authentication for local connections

### 2. Run the Tests

```bash
lua test_oauthbearer.lua
```

This will test:
- ✓ OAuth module loading
- ✓ Token validation
- ✓ Client-first message generation
- ✓ PostgreSQL connection
- ✓ OAUTHBEARER configuration

### 3. Cleanup

```bash
./cleanup_pg18.sh
```

This will stop and remove the test PostgreSQL instance.

## Test Output

Expected output from `test_oauthbearer.lua`:

```
============================================
pgmoon OAUTHBEARER Implementation Test
============================================

Test 1: Loading OAuth module...
✓ OAuth module loaded successfully

Test 2: Token validation...
✓ Valid token accepted
✓ Empty token rejected
✓ Nil token rejected

Test 3: OAUTHBEARER client-first message generation...
  Token: test-bearer-token-12345
  Message length: 41
  Starts with 'n,,': ✓
  Contains auth=Bearer: ✓

Test 4: Client-first message with extra parameters...
  Message with params length: 66
  Longer than basic message: ✓

Test 5: Standard PostgreSQL connection (trust auth)...
✓ Connected to PostgreSQL successfully!
  PostgreSQL version: PostgreSQL 14.x
  Current user: postgres
  
✓ Disconnected successfully

Test 6: OAUTHBEARER configuration test...
  Configuration created with oauth_token parameter
  
============================================
All OAuth module tests completed!
============================================
```

## Using OAUTHBEARER in Production

### Important Notes

1. **Standard PostgreSQL doesn't support OAUTHBEARER by default**
   - Requires PostgreSQL with SASL OAUTHBEARER support
   - May need custom extensions or cloud provider support
   - Examples: AWS RDS, Azure Database for PostgreSQL, Google Cloud SQL

2. **Requirements for Production OAUTHBEARER**:
   - PostgreSQL server with OAUTHBEARER SASL mechanism
   - OAuth 2.0 provider for token issuance
   - Valid OAuth bearer tokens
   - Proper `pg_hba.conf` configuration

### Example Configuration

```lua
local pgmoon = require("pgmoon")

-- Obtain OAuth token from your OAuth provider
local oauth_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

-- Create connection with OAUTHBEARER
local pg = pgmoon.new({
  host = "your-postgres-server.example.com",
  port = "5432",
  database = "mydb",
  user = "oauth-user",
  oauth_token = oauth_token
})

-- Connect (will use OAUTHBEARER if server supports it)
local success, err = pg:connect()
if not success then
  print("Connection failed:", err)
  return
end

-- Execute queries
local result = pg:query("SELECT current_user")
print("Connected as:", result[1].current_user)

pg:disconnect()
```

## Testing with Mock OAUTHBEARER

Since standard PostgreSQL doesn't support OAUTHBEARER, the test script validates:
- The OAuth module implementation
- Token validation logic
- Message generation according to RFC 7628
- Configuration handling

For full end-to-end OAUTHBEARER testing, you'll need a PostgreSQL instance with OAUTHBEARER support.

## Troubleshooting

### PostgreSQL won't start
- Check if port 5433 is already in use: `lsof -i :5433`
- Try a different port: `PG_PORT=5434 ./setup_pg18_oauth.sh`

### Connection fails
- Verify PostgreSQL is running: `psql -p 5433 -U postgres -d testdb`
- Check logs: `tail -f examples/pg_data/logfile`

### Tests fail
- Ensure pgmoon is built: `cd .. && make build`
- Check Lua path includes pgmoon modules
- Verify all dependencies are installed

## References

- [RFC 7628 - OAUTHBEARER SASL Mechanism](https://datatracker.ietf.org/doc/html/rfc7628)
- [PostgreSQL SASL Authentication](https://www.postgresql.org/docs/current/sasl-authentication.html)
- [pgmoon Documentation](../README.md)
