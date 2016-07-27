EventEmitter = require "events"
util         = require "util"
Through      = require "through2"
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
    @_clients = []

    @server.once "listening", @pollKeepAlive
    @server.once "close",     @stopPollingKeepAlive

  pollKeepAlive: =>
    @_keepAlivePoller = setInterval @keepAlive, @keepAliveInterval * 1000

  stopPollingKeepAlive: =>
    clearInterval @_keepAlivePoller
    delete @_keepAlivePoller

  keepAlive: =>
    client.write ":keepalive #{Date.now()}\n\n" for client in @_clients

  checkHeaders: (req) ->
    req.accepts ["text/event-stream", "text/x-dom-event-stream"]

  plumb: (fn, interval) -> (req, res, next) =>
    return next new Errors.NotAcceptableError unless @checkHeaders req

    {originalUrl}  = req
    source         = @_paths[originalUrl]
    unless source
      source = @_paths[originalUrl] = new StringTube
      @_counts[originalUrl] = 0

      if fn and interval
        res.json = (data) => source.write @encode data
        res.text = res.send = res.json
        poll     = -> fn req, res, next
        @_pollers[originalUrl] = setInterval poll, interval * 1000

        @emit "poll", originalUrl
      else
        @emit "plumb", originalUrl

    client = new Client req, res
    client.id = uuid.v4()
    @_clients.push client
    @_counts[originalUrl]++

    @emit "connection", client

    client.once "close", @removeClientAndMaybeStopPolling originalUrl, client.id
    source.pipe client

  source: (originalUrl) ->
    @_paths[originalUrl]

  removeClientAndMaybeStopPolling: (originalUrl, id) -> =>
    source          = @_paths[originalUrl]
    [client, index] = do => return [_client, i] for _client, i in @_clients when _client.id is id

    source.unpipe client
    @_clients.splice index, 1
    remaining = --@_counts[originalUrl]

    if remaining < 1
      if @_pollers[originalUrl]
        clearInterval @_pollers[originalUrl]
        delete @_pollers[originalUrl]
      delete @_paths[originalUrl]
      delete @_counts[originalUrl]
      @emit "stop", originalUrl

  destroy: ->
    while @_clients.length
      client = @_clients[0]
      client.end()
      client.emit "close"

  encode: (data) ->
    JSON.stringify data


module.exports = SSEriesOfTubes
