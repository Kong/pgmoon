# pgmoon OAUTHBEARER Testing

This directory contains test scripts for the OAUTHBEARER authentication implementation in pgmoon.

## Files

### Test Scripts

- **`test_oauthbearer.lua`** - Comprehensive test script that validates the OAUTHBEARER implementation

### Setup Scripts

- **`setup_pg18_oauth.sh`** - Sets up a PostgreSQL instance for testing (supports both Docker and local installation)
- **`cleanup_pg18.sh`** - Cleans up the PostgreSQL test instance

## Quick Start

### Run the OAuth Module Tests

The OAuth tests can run **without** a PostgreSQL instance since they only test the OAuth module functionality:

```bash
# From the pgmoon root directory:
cd /Users/xc/work/dev/pgmoon
LUA_PATH="./?.lua;./?/init.lua;;" lua examples/test_oauthbearer.lua
```

Or if you have pgmoon installed via luarocks:

```bash
lua examples/test_oauthbearer.lua
```

This will test:
- ✓ OAuth module loading
- ✓ Token validation (valid, empty, nil tokens)
- ✓ Client-first message generation
- ✓ Message format per RFC 7628
- ✓ Extra parameters handling

### Optional: PostgreSQL Test Instance Setup

If you want to test full PostgreSQL integration (not just OAuth module):

```bash
cd examples
./setup_pg18_oauth.sh
```

This will:
- Start a PostgreSQL instance on port 5433
- Create a test database named `testdb`
- Configure authentication for local connections

**Note:** Standard PostgreSQL doesn't support OAUTHBEARER by default. The test script focuses on OAuth module validation only.

### Cleanup

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
✓ Empty token rejected: Invalid OAuth token: token must be a non-empty string
✓ Nil token rejected:   Invalid OAuth token: token must be a non-empty string

Test 3: OAUTHBEARER client-first message generation...
  Token:        test-bearer-token-12345
  Message length:       41
  Starts with 'n,,':    ✓
  Contains auth=Bearer: ✓

Test 4: Client-first message with extra parameters...
  Message with params length:   66
  Longer than basic message:    ✓

============================================
All OAuth module tests completed!
============================================

Summary:
  ✓ OAuth module loads correctly
  ✓ Token validation works
  ✓ Client-first message generation works
  ✓ OAUTHBEARER messages formatted per RFC 7628
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

## What the Tests Validate

The test script validates the **OAuth module implementation** without requiring a database:
- OAuth module can be loaded and used correctly
- Token validation logic works (accepts valid tokens, rejects invalid ones)
- OAUTHBEARER client-first message generation follows RFC 7628
- Message format includes proper gs2-header, auth parameter, and encoding
- Extra parameters can be included in the message

**Note:** For full end-to-end OAUTHBEARER authentication testing, you'll need a PostgreSQL instance with OAUTHBEARER SASL support (requires extensions or cloud provider support like AWS RDS, Azure, Google Cloud SQL).

## Troubleshooting

### Module 'pgmoon' not found
The most common issue is Lua not finding the pgmoon modules. Solutions:

**Option 1:** Set LUA_PATH when running (recommended for development):
```bash
cd /Users/xc/work/dev/pgmoon
LUA_PATH="./?.lua;./?/init.lua;;" lua examples/test_oauthbearer.lua
```

**Option 2:** Install pgmoon locally with luarocks:
```bash
cd /Users/xc/work/dev/pgmoon
make local
# or
luarocks make --local
# Then run from anywhere:
lua examples/test_oauthbearer.lua
```

**Option 3:** Add to your shell profile (~/.bashrc or ~/.zshrc):
```bash
export LUA_PATH="/path/to/pgmoon/?.lua;/path/to/pgmoon/?/init.lua;;"
```

### PostgreSQL won't start (if using setup script)
- Check if port 5433 is already in use: `lsof -i :5433`
- Try a different port: `PG_PORT=5434 ./setup_pg18_oauth.sh`

### PostgreSQL connection fails (if testing with database)
- Verify PostgreSQL is running: `psql -p 5433 -U postgres -d testdb`
- Check logs: `tail -f examples/pg_data/logfile`
- Ensure pg_hba.conf has correct authentication method

## References

- [RFC 7628 - OAUTHBEARER SASL Mechanism](https://datatracker.ietf.org/doc/html/rfc7628)
- [PostgreSQL SASL Authentication](https://www.postgresql.org/docs/current/sasl-authentication.html)
- [pgmoon Documentation](../README.md)
