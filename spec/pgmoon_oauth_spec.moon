
import Postgres from require "pgmoon"
oauth = require "pgmoon.oauth"

-- OAuth test configuration (use environment variables or defaults)
-- When running inside Docker network, use container name; otherwise use localhost
OAUTH_HOST = os.getenv("OAUTH_PG_HOST") or "pgmoon-oauth-test"
OAUTH_PORT = os.getenv("OAUTH_PG_PORT") or "5432"  -- internal port inside container
OAUTH_DB = os.getenv("OAUTH_PG_DATABASE") or "testdb"
OAUTH_USER = os.getenv("OAUTH_TEST_USER") or "tester"

KEYCLOAK_INTERNAL_URL = os.getenv("KEYCLOAK_INTERNAL_URL") or "http://pgmoon-keycloak:8080"
REALM = os.getenv("REALM") or "pgmoon-test"
CLIENT_ID = os.getenv("CLIENT_ID") or "pgmoon-client"
TEST_PASSWORD = os.getenv("TEST_PASSWORD") or "tester123"

-- Helper: check if OAuth environment is available
is_oauth_env_available = ->
  handle = io.popen 'docker exec pgmoon-oauth-test echo ok 2>/dev/null'
  result = handle\read "*a"
  handle\close!
  result\match("ok") != nil

-- Helper: get OAuth token from Keycloak via docker exec
get_oauth_token = ->
  curl_cmd = string.format(
    'docker exec pgmoon-oauth-test curl -s -X POST "%s/realms/%s/protocol/openid-connect/token" ' ..
    '-H "Content-Type: application/x-www-form-urlencoded" ' ..
    '-d "username=%s&password=%s&grant_type=password&client_id=%s&scope=openid"',
    KEYCLOAK_INTERNAL_URL, REALM, OAUTH_USER, TEST_PASSWORD, CLIENT_ID
  )
  handle = io.popen curl_cmd
  response = handle\read "*a"
  handle\close!
  
  -- Extract access_token from JSON response
  token = response\match '"access_token":"([^"]*)"'
  token

describe "pgmoon oauth module", ->
  describe "validate_token", ->
    it "accepts valid token string", ->
      valid, err = oauth.validate_token "valid-token-example"
      assert.is_true valid
      assert.is_nil err

    it "rejects empty string", ->
      valid, err = oauth.validate_token ""
      assert.is_false valid
      assert.is_string err

    it "rejects nil", ->
      valid, err = oauth.validate_token nil
      assert.is_false valid
      assert.is_string err

    it "rejects non-string types", ->
      valid, err = oauth.validate_token 12345
      assert.is_false valid
      assert.is_string err

      valid, err = oauth.validate_token {}
      assert.is_false valid
      assert.is_string err

  describe "create_client_first", ->
    it "creates message with correct gs2-header", ->
      msg = oauth.create_client_first "test-token"
      assert.is_string msg
      assert.equals "n,,", msg\sub(1, 3)

    it "includes auth=Bearer in message", ->
      msg = oauth.create_client_first "test-token"
      assert.truthy msg\match "auth=Bearer"

    it "includes the token in message", ->
      token = "myspecialtoken12345"
      msg = oauth.create_client_first token
      assert.truthy msg\match token

    it "ends with double \\x01", ->
      msg = oauth.create_client_first "test-token"
      assert.equals "\1\1", msg\sub(-2)

    it "includes extra parameters when provided", ->
      msg_without = oauth.create_client_first "token"
      msg_with = oauth.create_client_first "token", {host: "localhost", port: "5432"}
      assert.is_true #msg_with > #msg_without

    it "formats extra parameters correctly", ->
      msg = oauth.create_client_first "token", {host: "localhost"}
      assert.truthy msg\match "host=localhost"


describe "pgmoon OAUTHBEARER integration #oauth", ->
  local pg, access_token, oauth_available

  setup ->
    oauth_available = is_oauth_env_available!
    if oauth_available
      access_token = get_oauth_token!

  before_each ->
    return unless access_token
    pg = Postgres {
      host: OAUTH_HOST
      port: OAUTH_PORT
      database: OAUTH_DB
      user: OAUTH_USER
      oauth_token: access_token
    }

  after_each ->
    if pg
      pcall -> pg\disconnect!

  it "connects with OAUTHBEARER authentication", ->
    pending "OAuth environment not available (run oauth_examples/setup.sh)" unless oauth_available
    pending "Failed to obtain OAuth token from Keycloak" unless access_token
    success, err = pg\connect!
    assert.is_true success, err

  it "executes queries after OAUTHBEARER auth", ->
    pending "OAuth environment not available" unless oauth_available
    pending "Failed to obtain OAuth token" unless access_token
    success, err = pg\connect!
    assert.is_true success, err

    result = pg\query "SELECT 1 as num"
    assert.is_table result
    assert.equals 1, #result
    -- num could be string "1" or number 1 depending on Lua version
    assert.truthy result[1].num == "1" or result[1].num == 1

  it "verifies authenticated user matches token subject", ->
    pending "OAuth environment not available" unless oauth_available
    pending "Failed to obtain OAuth token" unless access_token
    success, err = pg\connect!
    assert.is_true success, err

    result = pg\query "SELECT current_user"
    assert.equals OAUTH_USER, result[1].current_user

  it "can query test table", ->
    pending "OAuth environment not available" unless oauth_available
    pending "Failed to obtain OAuth token" unless access_token
    success, err = pg\connect!
    assert.is_true success, err

    result = pg\query "SELECT * FROM oauth_test ORDER BY id LIMIT 3"
    assert.is_table result
    assert.is_true #result > 0

  it "fails with invalid token", ->
    pending "OAuth environment not available" unless oauth_available
    pending "Failed to obtain OAuth token" unless access_token
    bad_pg = Postgres {
      host: OAUTH_HOST
      port: OAUTH_PORT
      database: OAUTH_DB
      user: OAUTH_USER
      oauth_token: "invalid-token-that-should-fail"
    }
    success, err = bad_pg\connect!
    assert.is_falsy success
    assert.is_truthy err

  it "raises error when oauth_token is missing but OAUTHBEARER required", ->
    pending "OAuth environment not available" unless oauth_available
    pending "Failed to obtain OAuth token" unless access_token
    no_token_pg = Postgres {
      host: OAUTH_HOST
      port: OAUTH_PORT
      database: OAUTH_DB
      user: OAUTH_USER
      -- no oauth_token, server will request OAUTHBEARER but we can't provide it
    }
    -- This should raise an assertion error because oauth_token is required
    assert.has_error ->
      no_token_pg\connect!
