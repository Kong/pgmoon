-- pgmoon OAUTHBEARER test with Keycloak OIDC provider
-- This test requires the Keycloak environment to be running
-- Start it with: ./setup_keycloak_oauth.sh

local pgmoon = require("pgmoon")
local oauth = require("pgmoon.oauth")

-- Configuration
local KEYCLOAK_INTERNAL_URL = os.getenv("KEYCLOAK_INTERNAL_URL") or "http://pgmoon-keycloak:8080"
local REALM = os.getenv("REALM") or "pgmoon-test"
local CLIENT_ID = os.getenv("CLIENT_ID") or "pgmoon-client"
local TEST_USER = os.getenv("TEST_USER") or "tester"
local TEST_PASSWORD = os.getenv("TEST_PASSWORD") or "tester123"

-- PostgreSQL configuration
local PG_HOST = os.getenv("PG_HOST") or "127.0.0.1"
local PG_PORT = os.getenv("PG_PORT") or "5433"
local PG_DATABASE = os.getenv("PG_DATABASE") or "testdb"

local exit_code = 0

print("============================================")
print("pgmoon OAUTHBEARER Test Suite")
print("============================================")
print()

-- ===========================================
-- Part 1: Unit Tests (no external dependencies)
-- ===========================================
print("Part 1: Unit Tests")
print("------------------------------------------")

-- Test 1: Token validation
print("Test 1.1: Token validation...")
local valid, err = oauth.validate_token("valid-token-example")
if valid then
    print("  ✓ Valid token accepted")
else
    print("  ✗ Error: " .. tostring(err))
    exit_code = 1
end

valid, err = oauth.validate_token("")
if not valid then
    print("  ✓ Empty token rejected")
else
    print("  ✗ Empty token should be rejected")
    exit_code = 1
end

valid, err = oauth.validate_token(nil)
if not valid then
    print("  ✓ Nil token rejected")
else
    print("  ✗ Nil token should be rejected")
    exit_code = 1
end

-- Test 2: Client-first message generation
print("Test 1.2: OAUTHBEARER message generation...")
local token = "test-bearer-token-12345"
local msg = oauth.create_client_first(token)

if msg:sub(1, 3) == "n,," then
    print("  ✓ Message starts with 'n,,'")
else
    print("  ✗ Message should start with 'n,,'")
    exit_code = 1
end

if msg:match("auth=Bearer") then
    print("  ✓ Message contains 'auth=Bearer'")
else
    print("  ✗ Message should contain 'auth=Bearer'")
    exit_code = 1
end

-- Test 3: Message with extra parameters
print("Test 1.3: Message with extra parameters...")
local msg_with_params = oauth.create_client_first(token, {host = "localhost", port = "5432"})
if #msg_with_params > #msg then
    print("  ✓ Extra parameters increase message length")
else
    print("  ✗ Extra parameters should increase message length")
    exit_code = 1
end

print()

-- ===========================================
-- Part 2: Integration Tests (requires Keycloak + PostgreSQL)
-- ===========================================
print("Part 2: Integration Tests")
print("------------------------------------------")
print()

-- Helper function to run docker command
local function docker_exec(cmd)
    local full_cmd = 'docker exec pgmoon-oauth-test ' .. cmd .. ' 2>/dev/null'
    local handle = io.popen(full_cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Helper function to extract JSON value
local function extract_json_value(json, key)
    local pattern = '"' .. key .. '":"([^"]*)"'
    return json:match(pattern)
end

-- Check if Docker containers are running
local check_result = docker_exec("echo ok")
if check_result:match("ok") == nil then
    print("⚠ Docker containers not running. Skipping integration tests.")
    print("  Run ./setup_keycloak_oauth.sh first")
    print()
    os.exit(exit_code)
end

-- Test 2.1: Get OAuth token from Keycloak
print("Test 2.1: Obtaining OAuth token from Keycloak...")
local curl_cmd = string.format(
    'curl -s -X POST "%s/realms/%s/protocol/openid-connect/token" -H "Content-Type: application/x-www-form-urlencoded" -d "username=%s&password=%s&grant_type=password&client_id=%s&scope=openid"',
    KEYCLOAK_INTERNAL_URL, REALM, TEST_USER, TEST_PASSWORD, CLIENT_ID
)
local token_response = docker_exec(curl_cmd)
local access_token = extract_json_value(token_response, "access_token")

if not access_token then
    print("  ✗ Failed to obtain OAuth token")
    print("    Response: " .. (token_response or "nil"):sub(1, 100))
    os.exit(1)
end

print("  ✓ OAuth token obtained (length: " .. #access_token .. ")")

-- Decode and display token claims
local function decode_base64(data)
    local padding = 4 - (#data % 4)
    if padding ~= 4 then
        data = data .. string.rep("=", padding)
    end
    data = data:gsub("-", "+"):gsub("_", "/")
    local ok, mime = pcall(require, "mime")
    if ok then
        return mime.unb64(data)
    end
    return nil
end

local parts = {}
for part in access_token:gmatch("[^.]+") do
    table.insert(parts, part)
end

if #parts >= 2 then
    local payload = decode_base64(parts[2])
    if payload then
        local sub = payload:match('"sub":"([^"]*)"')
        local iss = payload:match('"iss":"([^"]*)"')
        if sub then print("    sub: " .. sub) end
        if iss then print("    iss: " .. iss) end
    end
end

-- Test 2.2: Connect to PostgreSQL with OAuth token
print("Test 2.2: Connecting to PostgreSQL with OAUTHBEARER...")
local pg = pgmoon.new({
    host = PG_HOST,
    port = PG_PORT,
    database = PG_DATABASE,
    user = TEST_USER,
    oauth_token = access_token
})

local success, connect_err = pg:connect()

if success then
    print("  ✓ OAUTHBEARER authentication succeeded")
    
    -- Test 2.3: Execute query
    print("Test 2.3: Executing test query...")
    local result = pg:query("SELECT * FROM oauth_test ORDER BY id LIMIT 3")
    
    if result and #result > 0 then
        print("  ✓ Query executed successfully (" .. #result .. " rows)")
    else
        print("  ✗ Query returned no results")
        exit_code = 1
    end
    
    -- Test 2.4: Verify authenticated user
    print("Test 2.4: Verifying authenticated user...")
    local user_result = pg:query("SELECT current_user")
    if user_result and user_result[1] and user_result[1].current_user == TEST_USER then
        print("  ✓ Authenticated as: " .. user_result[1].current_user)
    else
        print("  ✗ User verification failed")
        exit_code = 1
    end
    
    pg:disconnect()
    print("  ✓ Disconnected")
else
    print("  ✗ OAUTHBEARER authentication failed: " .. tostring(connect_err))
    exit_code = 1
end

print()
print("============================================")
if exit_code == 0 then
    print("All tests passed!")
else
    print("Some tests failed!")
end
print("============================================")

os.exit(exit_code)
