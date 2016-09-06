EventEmitter = require "events"
util         = require "util"
Through      = require "through2"
{Merge}      = require "stream-combiner2-withopts"
EventClient  = require "./event-client"
Errors       = require "restify-errors"
uuid         = require "node-uuid"
extend       = util._extend


Proxy = Through.ctor {encoding: "utf8", decodeStrings: false}
class StringTube extends Proxy


class SSEriesOfTubes extends EventEmitter
  @StringTube: StringTube
  @EventClient: EventClient

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
    for client in @_clients
      client.res.write ":keepalive #{Date.now()}\n\n"
      client.res.flush?()

  checkHeaders: (req) ->
    req.accepts ["text/event-stream", "text/x-dom-event-stream"]

  plumb: (fn, interval, event) -> (req, res, next) =>
    return next new Errors.NotAcceptableError unless @checkHeaders req

    {url}  = req
    source = @_paths[url]
    unless source
      source = @_paths[url] = new @constructor.StringTube
      @_counts[url] = 0

      if fn and interval
        res.json = (data) =>
          source.write "event: #{event}" if event
          source.write @encode data
          res.flush?()
        res.text = res.send = res.json
        poll     = -> fn req, res, next
        @_pollers[url] = setInterval poll, interval * 1000

        @emit "poll", url
        process.nextTick poll
      else
        @emit "plumb", url

    return if req.noClient
    client = new @constructor.EventClient req, res
    client.id = uuid.v4()
    @_clients.push client
    @_counts[url]++

    @emit "connection", client

    client.once "close", @removeClientAndMaybeStopPolling url, client.id
    source.pipe client

  source: (url) ->
    @_paths[url]

  combine: (router, paths...) -> (req, res, next) =>
    return next new Errors.NotAcceptableError unless @checkHeaders req

    for path in paths when not @_pollers[path]
      _req = Object.create req
      _res = Object.create res
      extend _req, noClient: true, url: path
      router.handle _req, _res, next

    {url}  = req
    source = @_paths[url]
    unless source
      sources = (@_paths[path] for path in paths)
      source  = @_paths[url] = Merge sources, encoding: "utf8", decodeStrings: false
      @_counts[url] = 0
      @emit "plumb", url

    client = new @constructor.EventClient req, res
    client.id = uuid.v4()
    @_clients.push client
    @_counts[url]++
    @_counts[path]++ for path in paths

    @emit "connection", client

    client.once "close", @removeClientAndMaybeStopMultiplePolling url, client.id, paths
    source.pipe client

  removeClientAndMaybeStopPolling: (url, id) -> =>
    source          = @_paths[url]
    result          = do => return [_client, i] for _client, i in @_clients when _client.id is id
    [client, index] = result if result?

    if client
      source.unpipe client
      @_clients.splice index, 1

    remaining = --@_counts[url]
    if remaining < 1
      if @_pollers[url]
        clearInterval @_pollers[url]
        delete @_pollers[url]
      source.unwrap?()
      delete @_paths[url]
      delete @_counts[url]
      @emit "stop", url

  removeClientAndMaybeStopMultiplePolling: (url, id, paths) ->
    removers = (@removeClientAndMaybeStopPolling path, id for path in paths)
    removers.unshift @removeClientAndMaybeStopPolling url, id
    -> remover() for remover in removers

  destroy: ->
    while @_clients.length
      client = @_clients[0]
      client.end()
      client.emit "close"

  encode: (data) ->
    JSON.stringify data


module.exports = SSEriesOfTubes
