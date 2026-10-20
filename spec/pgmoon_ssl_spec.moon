import Postgres from require "pgmoon"

import psql, HOST, PORT, USER, PASSWORD, DB from require "spec.util"

describe "pgmoon with server", ->
  local pg

  setup ->
    os.execute "spec/postgres.sh start ssl"

    r = { psql "drop database if exists #{DB}" }
    assert 0 == r[#r], "failed to execute psql: drop database"

    r = { psql "create database #{DB}" }
    assert 0 == r[#r], "failed to execute psql: create database"

  teardown ->
    os.execute "spec/postgres.sh stop"

  describe "nginx", ->
    unless ngx
      it "(disabled)", -> pending "Skipping nginx tests, no ngx global available"
      return

    it "connects with ssl", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "nginx"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      pg\disconnect!


  describe "luasocket", ->
    if ngx
      it "(disabled)", -> pending "skipping luasocket in nginx testing mode"
      return

    it "connects without ssl on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        socket_type: "luasocket"
      }
      assert pg\connect!
      assert pg\query "select * from information_schema.tables"
      pg\disconnect!

    it "connects with ssl on ssl server (defaults to highest available, TLSv1.3)", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.3', res[1].version
      pg\disconnect!

    it "connects with TLSv1.2 on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        ssl_version: "tlsv1_2"
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.2', res[1].version
      pg\disconnect!

    it "connects with TLSv1.3 on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        ssl_version: "tlsv1_3"
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.3', res[1].version
      pg\disconnect!

  describe "cqueues", ->
    if ngx
      it "(disabled)", -> pending "skipping cqueues in nginx testing mode"
      return

    it "connects with ssl", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "cqueues"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      pg\disconnect!


    it "connects with ssl with context options", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "cqueues"
        ssl_version: "TLSv1_2"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.2', res[1].version

      pg\disconnect!


-- SCRAM-SHA-256-PLUS hashes the server certificate with the digest of the
-- algorithm it was signed with, so every digest needs a server of its own.
-- A wrong digest is not silently ignored: the server rejects the exchange with
-- "authentication exchange unsuccessful"
certificates = {
  {"rsa", "sha256"}, {"rsa", "sha384"}, {"rsa", "sha512"}
  {"ec", "sha256"}, {"ec", "sha384"}, {"ec", "sha512"}
}

for {cert_type, cert_digest} in *certificates
  describe "pgmoon with #{cert_type} #{cert_digest} signed server certificate", ->
    setup ->
      os.execute "PGMOON_TEST_CERT_TYPE=#{cert_type} PGMOON_TEST_CERT_DIGEST=#{cert_digest} spec/postgres.sh start ssl"

      r = { psql "drop database if exists #{DB}" }
      assert 0 == r[#r], "failed to execute psql: drop database"

      r = { psql "create database #{DB}" }
      assert 0 == r[#r], "failed to execute psql: create database"

    teardown ->
      os.execute "spec/postgres.sh stop"

    socket_types = if ngx
      {"nginx"}
    else
      {"luasocket", "cqueues"}

    for socket_type in *socket_types
      it "authenticates with channel binding over #{socket_type}", ->
        pg = Postgres {
          database: DB
          port: PORT
          user: USER
          password: PASSWORD
          host: HOST
          ssl: true
          :socket_type
        }

        assert pg\connect!
        assert pg\query "select 1"

        pg\disconnect!



DIRECT_SSL_UNSUPPORTED = "direct SSL negotiation requires ALPN support in tcpsock:sslhandshake"

direct_socket_types = if ngx
  {"nginx"}
else
  {"luasocket", "cqueues"}

new_direct = (socket_type, opts={}) ->
  config = {
    database: DB
    port: PORT
    user: USER
    password: PASSWORD
    host: HOST
    ssl: true
    ssl_negotiation: "direct"
    :socket_type
  }

  for k, v in pairs opts
    config[k] = v

  Postgres config

-- a stock OpenResty cannot send ALPN from a cosocket, so the nginx tests
-- check for the clear error there instead of the handshake
connect_direct = (pg, socket_type) ->
  ok, err = pg\connect!
  if not ok and socket_type == "nginx" and err == DIRECT_SSL_UNSUPPORTED
    pending "this OpenResty has no ALPN support in tcpsock:sslhandshake"

  ok, err

describe "pgmoon direct ssl negotiation", ->
  setup ->
    -- direct negotiation needs PostgreSQL 17 or newer, whatever the matrix runs
    os.execute "DOCKER_POSTGRES_VERSION=17 spec/postgres.sh start ssl"

    r = { psql "drop database if exists #{DB}" }
    assert 0 == r[#r], "failed to execute psql: drop database"

    r = { psql "create database #{DB}" }
    assert 0 == r[#r], "failed to execute psql: create database"

  teardown ->
    os.execute "spec/postgres.sh stop"

  for socket_type in *direct_socket_types
    describe socket_type, ->
      it "connects and authenticates", ->
        pg = new_direct socket_type
        assert connect_direct pg, socket_type

        res = assert pg\query [[SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()]]
        assert.same true, res[1].ssl
        assert.same "TLSv1.3", res[1].version

        pg\disconnect!

      -- ngx cosockets take the TLS version from lua_ssl_protocols instead
      tls12 = switch socket_type
        when "luasocket" then "tlsv1_2"
        when "cqueues" then "TLSv1_2"

      it "keeps the configured TLS version", ->
        pending "ssl_version does not apply to ngx cosockets" unless tls12
        pg = new_direct socket_type, ssl_version: tls12
        assert connect_direct pg, socket_type

        res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid = pg_backend_pid()]]
        assert.same "TLSv1.2", res[1].version

        pg\disconnect!

  describe "configuration", ->
    it "requires ssl", ->
      pg = new_direct direct_socket_types[1], ssl: false
      assert.same {nil, 'ssl_negotiation "direct" requires ssl'}, {pg\connect!}


describe "pgmoon direct ssl negotiation against a server older than 17", ->
  setup ->
    os.execute "DOCKER_POSTGRES_VERSION=16 spec/postgres.sh start ssl"

  teardown ->
    os.execute "spec/postgres.sh stop"

  for socket_type in *direct_socket_types
    it "fails over #{socket_type} with no fallback", ->
      pg = new_direct socket_type, database: "postgres"
      ok, err = connect_direct pg, socket_type
      assert.falsy ok
      assert.truthy err


-- a TLS server that is not PostgreSQL and selects no ALPN protocol, on a
-- free port. It logs the ClientHello extensions.
start_tls_server = ->
  socket = require "socket"

  probe = assert socket.bind "127.0.0.1", 0
  _, port = probe\getsockname!
  probe\close!

  base = os.tmpname!
  assert os.execute "openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -keyout #{base}.key -out #{base}.crt > /dev/null 2>&1"

  -- s_server quits when its stdin reaches EOF, so keep stdin open
  f = assert io.popen "(sleep 600 | openssl s_server -tlsextdebug -accept #{port} -cert #{base}.crt -key #{base}.key > #{base}.log 2>&1) > /dev/null 2>&1 & echo $!"
  pid = f\read "*l"
  f\close!

  read_log = ->
    lf = io.open "#{base}.log"
    return "" unless lf
    data = lf\read "*a"
    lf\close!
    data

  -- s_server writes its log asynchronously, so poll for the text
  wait_log = (text) ->
    for _ = 1, 50
      return true if read_log!\find text, 1, true
      socket.sleep 0.1
    false

  assert wait_log("ACCEPT"), "openssl s_server did not start"

  {
    port: tostring port
    :read_log
    :wait_log

    stop: ->
      os.execute "pkill -P #{pid} 2> /dev/null; kill #{pid} 2> /dev/null"
      os.remove "#{base}.#{ext}" for ext in *{"crt", "key", "log"}
      os.remove base
  }


describe "pgmoon direct ssl negotiation against a server without ALPN", ->
  local server

  before_each ->
    server = start_tls_server!

  after_each ->
    server.stop!

  connect_to = (socket_type, host) ->
    connect_direct new_direct(socket_type, :host, port: server.port), socket_type

  for socket_type in *direct_socket_types
    -- libpq refuses such a server, pgmoon must too
    it "refuses the connection over #{socket_type}", ->
      assert.same {
        nil
        'server did not select ALPN protocol "postgresql" in direct SSL negotiation'
      }, {connect_to socket_type, "127.0.0.1"}

    it "sends the host name as SNI over #{socket_type}", ->
      connect_to socket_type, "localhost"
      assert.truthy server.wait_log 'TLS client extension "server name"'

    it "does not send an IP address as SNI over #{socket_type}", ->
      connect_to socket_type, "127.0.0.1"
      assert.truthy server.wait_log "TLS client extension"
      assert.falsy server.read_log!\find 'TLS client extension "server name"', 1, true
