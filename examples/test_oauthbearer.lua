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

print("============================================")
