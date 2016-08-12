EventEmitter = require "events"
util         = require "util"
Through      = require "through2"
Combine      = require "stream-combiner2-withopts"
Client       = require "sse-stream/lib/client"
Errors       = require "restify-errors"
uuid         = require "node-uuid"
extend       = util._extend


Proxy = Through.ctor {encoding: "utf8", decodeStrings: false}
class StringTube extends Proxy


class SSEriesOfTubes extends EventEmitter
  @StringTube: StringTube

  constructor: (@server, @keepAliveInterval = 5) ->
    @_paths   = {}
    @_counts  = {}
    @_pollers = {}
    @_routes  = {}
    @_clients = []

    @server.once "listening", @pollKeepAlive
    @server.once "close",     @stopPollingKeepAlive

  pollKeepAlive: =>
    @_keepAlivePoller = setInterval @keepAlive, @keepAliveInterval * 1000

  stopPollingKeepAlive: =>
    clearInterval @_keepAlivePoller
    delete @_keepAlivePoller

  keepAlive: =>
    for client in @_clients
      client.res.write ":keepalive #{Date.now()}\n\n"
      client.res.flush?()

  checkHeaders: (req) ->
    req.accepts ["text/event-stream", "text/x-dom-event-stream"]

  plumb: (fn, interval, path) -> @_routes[path] = (req, res, next) =>
    return next new Errors.NotAcceptableError unless @checkHeaders req

    {originalUrl}  = req
    source         = @_paths[originalUrl]
    unless source
      source = @_paths[originalUrl] = new @constructor.StringTube
      @_counts[originalUrl] = 0

      if fn and interval
        res.json = (data) =>
          source.write @encode data
          res.flush?()
        res.text = res.send = res.json
        poll     = -> fn req, res, next
        @_pollers[originalUrl] = setInterval poll, interval * 1000

        @emit "poll", originalUrl
      else
        @emit "plumb", originalUrl

    return if req.noClient
    client = new Client req, res
    client.id = uuid.v4()
    @_clients.push client
    @_counts[originalUrl]++

    @emit "connection", client

    client.once "close", @removeClientAndMaybeStopPolling originalUrl, client.id
    source.pipe client

  source: (originalUrl) ->
    @_paths[originalUrl]

  combine: (paths...) -> (req, res, next) =>
    return next new Errors.NotAcceptableError unless @checkHeaders req

    for path in paths when not @_pollers[path]
      _req = Object.create req
      _res = Object.create res
      extend _req, noClient: true, originalUrl: path
      @_routes[path] _req, _res, next

    {originalUrl}  = req
    source         = @_paths[originalUrl]
    unless source
      sources = (@_paths[path] for path in paths)
      source  = @_paths[originalUrl] = Combine sources, encoding: "utf8", decodeStrings: false
      @_counts[originalUrl] = 0
      @emit "plumb", originalUrl

    client = new Client req, res
    client.id = uuid.v4()
    @_clients.push client
    @_counts[originalUrl]++
    @_counts[path]++ for path in paths

    @emit "connection", client

    client.once "close", @removeClientAndMaybeStopMultiplePolling originalUrl, client.id, paths
    source.pipe client

  removeClientAndMaybeStopPolling: (originalUrl, id) -> =>
    source          = @_paths[originalUrl]
    result          = do => return [_client, i] for _client, i in @_clients when _client.id is id
    [client, index] = result if result?

    if client
      source.unpipe client
      @_clients.splice index, 1

    remaining = --@_counts[originalUrl]
    if remaining < 1
      if @_pollers[originalUrl]
        clearInterval @_pollers[originalUrl]
        delete @_pollers[originalUrl]
      source.unwrap?()
      delete @_paths[originalUrl]
      delete @_counts[originalUrl]
      @emit "stop", originalUrl

  removeClientAndMaybeStopMultiplePolling: (originalUrl, id, paths) ->
    removers = (@removeClientAndMaybeStopPolling path, id for path in paths)
    removers.unshift @removeClientAndMaybeStopPolling originalUrl, id
    -> remover() for remover in removers

  destroy: ->
    while @_clients.length
      client = @_clients[0]
      client.end()
      client.emit "close"

  encode: (data) ->
    JSON.stringify data


module.exports = SSEriesOfTubes
