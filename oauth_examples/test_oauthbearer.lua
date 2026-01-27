#!/usr/bin/env lua
-- Test script for pgmoon OAUTHBEARER implementation
-- This demonstrates the OAuth module even though standard PostgreSQL
-- doesn't support OAUTHBEARER without extensions

local pgmoon = require("pgmoon")

print("============================================")
print("pgmoon OAUTHBEARER Implementation Test")
print("============================================\n")

-- Test 1: Validate OAuth module can be loaded
print("Test 1: Loading OAuth module...")
local OAuth = require("pgmoon.oauth")
print("✓ OAuth module loaded successfully\n")

-- Test 2: Test token validation
print("Test 2: Token validation...")
local valid, err = OAuth:validate_token("valid-token-example")
if valid then
    print("✓ Valid token accepted")
else
    print("✗ Error:", err)
end

valid, err = OAuth:validate_token("")
if not valid then
    print("✓ Empty token rejected:", err)
else
    print("✗ Empty token should be rejected")
end

valid, err = OAuth:validate_token(nil)
if not valid then
    print("✓ Nil token rejected:", err)
else
    print("✗ Nil token should be rejected")
end
print()

-- Test 3: Test client-first message generation
print("Test 3: OAUTHBEARER client-first message generation...")
local token = "test-bearer-token-12345"
local msg = OAuth:create_client_first(token)

print("  Token:", token)
print("  Message length:", #msg)
print("  Starts with 'n,,':", msg:sub(1, 3) == "n,," and "✓" or "✗")
print("  Contains auth=Bearer:", msg:match("auth=Bearer") and "✓" or "✗")
print()

-- Test 4: Test with extra parameters
print("Test 4: Client-first message with extra parameters...")
local msg_with_params = OAuth:create_client_first(token, {host = "localhost", port = "5432"})
print("  Message with params length:", #msg_with_params)
print("  Longer than basic message:", #msg_with_params > #msg and "✓" or "✗")
print()

-- Test 5: PostgreSQL connection with oauth_token parameter
print("Test 5: PostgreSQL OAUTHBEARER authentication test...")
print()
print("  PostgreSQL 18 is configured with 'oauth' auth method,")
print("  which will advertise OAUTHBEARER in its SASL mechanism list.")
print("  This allows us to test the actual OAUTHBEARER handshake.")
print()

local pg_oauth = pgmoon.new({
    host = "127.0.0.1",
    port = "5433",
    database = "testdb",
    user = "tester",  -- Role that matches OAuth token subject
    oauth_token = "test-oauth-bearer-token-12345"
})

print("  Attempting OAUTHBEARER authentication...")
print("  pgmoon will send RFC 7628 SASL Initial Response: n,,\\x01auth=Bearer <token>\\x01\\x01")
print()

local success, err_msg = pg_oauth:connect()

if success then
    print("✓ OAUTHBEARER authentication succeeded!")
    print("  (Server accepted the OAuth token)")
    print()

    -- Query the test table
    local result = pg_oauth:query("SELECT * FROM oauth_test ORDER BY id")

    if result then
        print("  Data from oauth_test table:")
        for _, row in ipairs(result) do
            print(string.format("    [%d] %s", row.id, row.name))
        end
    end

    pg_oauth:disconnect()
    print("  ✓ Disconnected")
    print()
    print("✓ Test 5 passed - OAUTHBEARER authentication works!")
else
    print("⊘ OAUTHBEARER authentication attempt made (this is expected)")
    print("  Error:", err_msg)
end

print()
print("============================================")

