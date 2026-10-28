
-- reads the protocol the server selected on an ngx cosocket: a string,
-- false when none, or nil and an error
local alpn_buf
nginx_getalpnselected = =>
  unless @getsslpointer
    return nil, "tcpsock:getsslpointer is required to read the negotiated ALPN protocol"

  ssl, err = @getsslpointer!
  return nil, err unless ssl

  ffi = require "ffi"

  unless alpn_buf
    -- another library may have declared it already, a second cdef raises
    pcall ffi.cdef, [[
      void SSL_get0_alpn_selected(const void *ssl, const unsigned char **data,
                                  unsigned int *len);
    ]]

    alpn_buf = {
      data: ffi.new "const unsigned char *[1]"
      len: ffi.new "unsigned int[1]"
    }

  ffi.C.SSL_get0_alpn_selected ssl, alpn_buf.data, alpn_buf.len

  len = alpn_buf.len[0]
  return false if len == 0

  ffi.string alpn_buf.data[0], len

wrap_luasocket = do
  import flatten from require "pgmoon.util"

  proxy_mt = {
    __index: (key) =>
      sock = @sock
      original = sock[key]
      if type(original) == "function"
        fn = (_, ...) ->
          original sock, ...
        @[key] = fn
        fn
      else
        original
  }

  -- these methods are overidden from the default socket implementation
  -- all other methods/properties are carried over via the __index metamethod above
  local method_overrides
  method_overrides = {
    send: (...) => @sock\send flatten ...

    -- luasocket takes SECONDS while ngx takes MILLISECONDS
    settimeout: (t) =>
      if t
        t = t/1000

      @sock\settimeout t

    setkeepalive: =>
      error "You attempted to call setkeepalive on a LuaSocket socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool"

    -- there is no compatible interface here, always return 0 to suggest the
    -- socket is connecting for the first time
    getreusedtimes: (t) => 0

    -- sni is only for direct SSL negotiation, so luasec_opts work as before
    sslhandshake: (opts={}, sni) =>
      ssl = require "ssl"
      params = {
        mode: "client"
        protocol: "any"
        verify: "none"
        options: { "all", "no_sslv2", "no_sslv3", "no_tlsv1" }
      }

      for k,v in pairs opts
        params[k] = v

      sec_sock, err = ssl.wrap @sock, params
      return false, err unless sec_sock

      sec_sock\sni sni if sni

      success, err = sec_sock\dohandshake!
      return false, err unless success

      -- purge memoized socket closures (created by proxy_mt)
      for k, v in pairs @
        if not method_overrides[k] and type(v) == "function"
          @[k] = nil

      @sock = sec_sock

      true

    getalpnselected: => @sock\getalpn!
  }

  (sock) ->
    proxy = {
      :sock
    }
    for k,v in pairs method_overrides
      proxy[k] = v

    setmetatable proxy, proxy_mt

-- creates a luasocket socket proxy to make it behave like ngx.socket.tcp
create_luasocket = (...) ->
  socket = require("socket")
  wrap_luasocket socket.tcp ...

create_host_luasocket = (host) ->
  return create_luasocket! unless host

  socket = require("socket")
  create_ipv4 = socket.tcp4 or socket.tcp
  create = create_ipv4
  addresses, err = socket.dns.getaddrinfo host
  return nil, err unless addresses
  for address in *addresses
    -- Keep the existing IPv4 preference for dual-stack hosts.
    if address.family == "inet"
      create = create_ipv4
      break
    elseif address.family == "inet6"
      create = socket.tcp6

  sock, err = create!
  return nil, err unless sock
  wrap_luasocket sock

{
  :create_luasocket

  new: (socket_type, host) ->
    if socket_type == nil
      -- TODO: this should not be the responsibility of this library
      -- TODO: write out a warning for some versions, then throw error when socket type is missing
      -- choose the default socket, try to use nginx, otherwise default to
      -- luasocket
      socket_type = if ngx and ngx.get_phase! != "init"
        "nginx"
      else
        "luasocket"

    socket = switch socket_type
      when "nginx"
        sock = ngx.socket.tcp!
        sock.getalpnselected = nginx_getalpnselected
        sock
      when "luasocket"
        sock, err = create_host_luasocket host
        return nil, err unless sock
        sock
      when "cqueues"
        require("pgmoon.cqueues").CqueuesSocket!
      else
        error "got unknown or unset socket type: #{socket_type}"

    socket, socket_type
}

