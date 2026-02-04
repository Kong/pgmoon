# OAUTHBEARER Support for pgmoon

## Overview
OAUTHBEARER SASL authentication support for pgmoon, enabling PostgreSQL authentication using OAuth 2.0 bearer tokens as specified in RFC 7628.

## Usage

Provide an `oauth_token` when creating a connection:

```lua
local pgmoon = require("pgmoon")

local pg = pgmoon.new({
  host = "127.0.0.1",
  port = "5432",
  database = "mydb",
  user = "postgres",
  oauth_token = "your-oauth-bearer-token"  -- OAuth 2.0 bearer token
})

local success, err = pg:connect()
if not success then
  print("Connection failed:", err)
  return
end

local result = pg:query("SELECT current_user")
print("Connected as:", result[1].current_user)

pg:disconnect()
```

## Authentication Flow

1. Client initiates connection with PostgreSQL
2. Server responds with SASL authentication request (auth_type 10)
3. Server includes "OAUTHBEARER" in list of supported mechanisms
4. Client detects OAUTHBEARER in the `auth` function
5. Client validates the OAuth token
6. Client generates client-first message with bearer token
7. Client sends SASL initial response
8. Server may send challenge (AuthenticationSASLContinue)
9. Client sends empty response if challenged
10. Server sends final authentication status
11. Client verifies authentication succeeded

## References

- RFC 7628: A Set of Simple Authentication and Security Layer (SASL) Mechanisms for OAuth
- PostgreSQL SASL Authentication: https://www.postgresql.org/docs/current/sasl-authentication.html
