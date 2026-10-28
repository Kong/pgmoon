local sockets = require 'pgmoon.socket'
local Postgres = require('pgmoon').Postgres
local socket = require 'socket'

describe('LuaSocket address family selection', function()
  local original_socket = package.loaded.socket
  local created, lookups

  before_each(function()
    created, lookups = {}, 0
    local function tcp(family)
      local sock = {
        getfamily = function() return family end,
        settimeout = function(self, value) self.timeout = value; return 1 end,
        connect = function() return nil, 'connection refused' end,
      }
      created[#created + 1] = sock
      return sock
    end
    local records = {
      ['127.0.0.1'] = {{ family = 'inet', addr = '127.0.0.1' }},
      ['::1'] = {{ family = 'inet6', addr = '::1' }},
      ['ipv6.test'] = {{ family = 'inet6', addr = '::1' }},
      ['dual.test'] = {
        { family = 'inet6', addr = '::1' },
        { family = 'inet', addr = '127.0.0.1' },
      },
    }
    package.loaded.socket = {
      tcp = function() return tcp('inet4') end,
      tcp6 = function() return tcp('inet6') end,
      dns = {
        getaddrinfo = function(host)
          lookups = lookups + 1
          return records[host], records[host] and nil or 'name not found'
        end,
      },
    }
  end)

  after_each(function()
    package.loaded.socket = original_socket
  end)

  for _, case in ipairs({
    { host = '127.0.0.1', family = 'inet4' },
    { host = '::1', family = 'inet6' },
    { host = 'ipv6.test', family = 'inet6' },
    { host = 'dual.test', family = 'inet4' },
  }) do
    it('creates one ' .. case.family .. ' socket for ' .. case.host, function()
      local pg = Postgres({ socket_type = 'luasocket', host = case.host })
      assert.equal(case.family, pg.sock:getfamily())
      assert.equal(1, #created)
      assert.equal(1, lookups)
    end)
  end

  it('keeps the IPv4 default when no host is supplied', function()
    local sock = sockets.create_luasocket()
    assert.equal('inet4', sock:getfamily())
    assert.equal(0, lookups)
  end)

  it('keeps the original constructor when new receives no host', function()
    local tcp_calls = 0
    local original_tcp = package.loaded.socket.tcp
    package.loaded.socket.tcp = function(...)
      tcp_calls = tcp_calls + 1
      return original_tcp(...)
    end
    package.loaded.socket.tcp4 = function()
      error('tcp4 must not replace the original constructor without a host')
    end
    local sock, socket_type = sockets.new('luasocket')
    assert.equal('inet4', sock:getfamily())
    assert.equal('luasocket', socket_type)
    assert.equal(1, tcp_calls)
    assert.equal(0, lookups)
  end)

  it('uses tcp4 for an IPv4 host when available', function()
    local tcp4_calls = 0
    local original_tcp = package.loaded.socket.tcp
    package.loaded.socket.tcp4 = function()
      tcp4_calls = tcp4_calls + 1
      return original_tcp()
    end
    package.loaded.socket.tcp = function()
      error('the default constructor must not replace tcp4 for an IPv4 host')
    end
    local pg = Postgres({ socket_type = 'luasocket', host = '127.0.0.1' })
    assert.equal('inet4', pg.sock:getfamily())
    assert.equal(1, tcp4_calls)
  end)

  it('keeps create_luasocket arguments out of address resolution', function()
    local sock = sockets.create_luasocket('::1')
    assert.equal('inet4', sock:getfamily())
    assert.equal(0, lookups)
  end)

  it('reports DNS errors before creating a socket', function()
    local sock, err = sockets.new('luasocket', 'missing.test')
    assert.is_nil(sock)
    assert.equal('name not found', err)
    assert.equal(0, #created)
  end)

  it('returns DNS errors from Postgres methods without throwing', function()
    local pg = Postgres({ socket_type = 'luasocket', host = 'missing.test' })
    assert.is_nil(pg.sock)
    assert.equal(1, pg:settimeout(1000))
    for _, method in ipairs({ 'connect', 'disconnect', 'keepalive' }) do
      local ok, err = pg[method](pg)
      assert.is_nil(ok)
      assert.equal('name not found', err)
    end
    assert.equal(0, #created)
  end)

  it('retries IPv6 socket creation after a temporary DNS failure', function()
    local lookup = package.loaded.socket.dns.getaddrinfo
    package.loaded.socket.dns.getaddrinfo = function()
      return nil, 'temporary resolver failure'
    end
    local failed = Postgres({ socket_type = 'luasocket', host = 'ipv6.test' })
    assert.equal(1, failed:settimeout(250))
    local ok, err = failed:connect()
    assert.is_nil(ok)
    assert.equal('temporary resolver failure', err)
    assert.equal(0, #created)
    package.loaded.socket.dns.getaddrinfo = lookup
    ok, err = failed:connect()
    assert.is_nil(ok)
    assert.equal('connection refused', err)
    assert.equal('inet6', failed.sock:getfamily())
    assert.equal(0.25, created[1].timeout)
    assert.is_nil(failed.socket_error)
    assert.equal(1, #created)
  end)

  it('returns socket creation errors without wrapping a nil socket', function()
    package.loaded.socket.tcp6 = function()
      return nil, 'address family not supported'
    end
    local pg = Postgres({ socket_type = 'luasocket', host = '::1' })
    local ok, err = pg:connect()
    assert.is_nil(ok)
    assert.equal('address family not supported', err)
    assert.equal(0, #created)
  end)

  it('does not resolve or replace an nginx socket', function()
    local old_ngx = ngx
    local native = {}
    rawset(_G, 'ngx', { socket = { tcp = function() return native end } })
    finally(function() rawset(_G, 'ngx', old_ngx) end)
    local sock, socket_type = sockets.new('nginx', '::1')
    assert.equal(native, sock)
    assert.equal('nginx', socket_type)
    assert.equal(0, lookups)
  end)
end)

describe('LuaSocket loopback connections', function()
  local cases = {
    { host = '127.0.0.1', address = '127.0.0.1', family = 'inet4' },
    { host = '::1', address = '::1', family = 'inet6' },
  }
  local hostname = os.getenv('KONG_TEST_IPV6_ONLY_HOSTNAME')
  if hostname then
    cases[#cases + 1] = { host = hostname, family = 'inet6' }
  else
    it('connects through an IPv6-only hostname', function()
      pending('set KONG_TEST_IPV6_ONLY_HOSTNAME to enable the resolver test')
    end)
  end

  for _, case in ipairs(cases) do
    it('creates the correct fd before setting options for ' .. case.host, function()
      local address = case.address
      if not address then
        local addresses = assert(socket.dns.getaddrinfo(case.host))
        assert.is_true(#addresses > 0)
        for _, entry in ipairs(addresses) do
          assert.equal('inet6', entry.family)
        end
        address = addresses[1].addr
      end
      local server = assert(case.family == 'inet6' and socket.tcp6() or socket.tcp())
      local client, peer
      finally(function()
        if peer then peer:close() end
        if client then client:close() end
        server:close()
      end)
      assert(server:settimeout(1))
      assert(server:bind(address, 0))
      assert(server:listen())
      local _, port = server:getsockname()
      client = assert(sockets.new('luasocket', case.host))
      local fd = client:getfd()
      assert.is_true(fd >= 0)
      assert.equal(case.family, client:getfamily())
      client:settimeout(1000)
      assert(client:setoption('keepalive', true))
      assert(client:setoption('tcp-nodelay', true))
      assert(client:connect(case.host, port))
      assert.equal(fd, client:getfd())
      assert.is_true(client:getoption('keepalive'))
      assert.is_true(client:getoption('tcp-nodelay'))
      peer = assert(server:accept())
      assert(client:send('ping\n'))
      assert.equal('ping', peer:receive())
      assert(peer:send('pong\n'))
      assert.equal('pong', client:receive())
    end)
  end
end)
