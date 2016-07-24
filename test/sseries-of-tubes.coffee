SSEriesOfTubes = require "../src/sseries-of-tubes"
Client         = require "sse-stream/lib/client"


http     = require "http"
util     = require "util"
{expect} = require "chai"
{spy}    = require "sinon"
spy.on   = spy
extend   = util._extend


describe "SSEriesOfTubes", ->
  interval       = 0.01
  originalUrl    = "/test"
  reqMock        = {originalUrl, headers: {}, accepts: (-> true), socket: setNoDelay: ->}
  resMock        = once: (->), on: (->), writeHead: (->), write: (->), end: (->)
  req            = null
  res            = null
  server         = null
  sseriesOfTubes = null

  beforeEach ->
    req            = extend {}, reqMock
    res            = extend {}, resMock
    server         = new http.Server
    sseriesOfTubes = new SSEriesOfTubes server, interval

  afterEach ->
    req            = null
    res            = null
    server         = null
    sseriesOfTubes = null

  describe "#StringTube", ->
    it "should be a export of StringTube class", ->
      expect(SSEriesOfTubes.StringTube).to.be.a "function"
      expect(SSEriesOfTubes.StringTube.name).to.match /StringTube/

  describe "##constructor", ->
    internals = [
      "_paths"
      "_counts"
      "_pollers"
    ]

    for name in internals
      it "should initialize internal object #{name}", ->
        obj = sseriesOfTubes[name]

        expect(obj).to.be.an "object"
        expect(obj).to.be.empty

    it "should initialize internal array _clients", ->
      {_clients} = sseriesOfTubes
      expect(_clients).to.be.an "array"
      expect(_clients).to.be.empty

    it "should bind the keep-alive poller to the server", ->
      fn = spy.on SSEriesOfTubes::, "pollKeepAlive"
      sseriesOfTubes = new SSEriesOfTubes server

      sseriesOfTubes.server.emit "listening"
      expect(fn.called).to.be.true

    it "should bind the poll stopper to the server", ->
      fn = spy.on SSEriesOfTubes::, "stopPollingKeepAlive"
      sseriesOfTubes = new SSEriesOfTubes server

      sseriesOfTubes.server.emit "close"
      expect(fn.called).to.be.true

  describe "##pollKeepAlive", ->
    it "should call keepAlive after an interval", (done) ->
      fn = spy.on sseriesOfTubes, "keepAlive"

      sseriesOfTubes.pollKeepAlive()
      await setTimeout defer(), 0.02 * 1000
      expect(sseriesOfTubes._keepAlivePoller).to.not.be.empty
      expect(fn.called).to.be.true

      sseriesOfTubes.stopPollingKeepAlive()
      done()

  describe "##stopPollingKeepAlive", ->
    it "should stop the poller", (done) ->
      fn = spy.on sseriesOfTubes, "keepAlive"

      sseriesOfTubes.pollKeepAlive()
      sseriesOfTubes.stopPollingKeepAlive()
      await setTimeout defer(), 2 * interval * 1000

      expect(sseriesOfTubes._keepAlivePoller).to.be.empty
      expect(fn.called).to.be.false
      done()

  describe "##keepAlive", ->
    it "should write :keepalive to every client", ->
      blackhat = write: spy()
      whitehat = write: spy()
      sseriesOfTubes._clients = [blackhat, whitehat]

      sseriesOfTubes.keepAlive()

      expect(blackhat.write.called).to.be.true
      expect(blackhat.write.args[0][0]).to.match
      expect(whitehat.write.called).to.be.true
      expect(whitehat.write.args[0][0]).to.match /:keepalive/

  describe "##checkHeaders", ->

  describe "##plumb", ->
    plumbed = null

    beforeEach ->
      plumbed = sseriesOfTubes.plumb (->), interval

    afterEach ->
      plumbed = null

    it "should return a function", ->
      expect(plumbed).to.be.a "function"

    describe "returned function", ->
      it "should call next with 406 error and return if headers not accepted", (done) ->
        nope = accepts: -> false
        next = (err) ->
          expect(err.statusCode).to.equal 406
          expect(err.toString()).to.match /NotAcceptable/
          done()

        result = plumbed nope, null, next
        expect(result).to.be.empty

      it "should create a source if none exists", (done) ->
        {_paths} = sseriesOfTubes

        expect(_paths[originalUrl]).to.be.empty
        plumbed req, res, done
        expect(_paths[originalUrl]).to.respondTo "write"
        done()

      it "should use a source if it exists", (done) ->
        {_paths} = sseriesOfTubes
        plumbed req, res, done
        source = _paths[originalUrl]

        expect(source).to.respondTo "write"
        plumbed req, res, done
        expect(_paths[originalUrl]).to.equal source
        done()

      it "should start polling the fn", (done) ->
        route   = spy()
        plumbed = sseriesOfTubes.plumb route, interval

        plumbed req, res, done
        await setTimeout defer(), 2.5 * interval * 1000

        expect(route.calledTwice).to.be.true
        done()

      it "should emit a poll event with original url", (done) ->
        await
          sseriesOfTubes.once "poll", defer url
          plumbed req, res, done

        expect(url).to.equal originalUrl
        done()

      it "should emit a plumb event with original url", (done) ->
        plumbed = sseriesOfTubes.plumb()

        await
          sseriesOfTubes.once "plumb", defer url
          plumbed req, res, done

        expect(url).to.equal originalUrl
        done()

      it "should emit a connection event with client", (done) ->
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        expect(client).to.be.an.instanceof Client
        done()

      it "should pipe all responses to all the clients", (done) ->
        message    = subliminal: true
        route      = (rreq, rres, rnext) ->
          rres.json message
          rres.text message
          rres.send message
        plumbed         = sseriesOfTubes.plumb route, interval

        await
          res1       = extend {}, res
          defer1     = defer()
          defer2     = defer()
          res1.write = (data) ->
            return if data.match /ok/
            expect(data).to.match /data/
            expect(data).to.match /subliminal/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return if data.match /ok/
            expect(data).to.match /data/
            expect(data).to.match /subliminal/
            defer2()

          plumbed req, res1, done
          plumbed req, res2, done

        sseriesOfTubes.destroy()
        done()

  describe "##source", ->
    it "should return a source for a given path", (done) ->
      plumbed = sseriesOfTubes.plumb()
      plumbed req, res, done

      source = sseriesOfTubes.source originalUrl

      expect(source).to.exist
      done()

  describe "##removeClientAndMaybeStopPolling", ->
    it "should return a function", ->
      remover = sseriesOfTubes.removeClientAndMaybeStopPolling()
      expect(remover).to.be.a "function"

    describe "returned function", ->
      it "should unpipe the client from the source", (done) ->
        plumbed = sseriesOfTubes.plumb (->), interval
        remover = sseriesOfTubes.removeClientAndMaybeStopPolling originalUrl, 0

        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        await
          client.on "unpipe", defer()
          remover()

        done()

      it "should stop polling if no more clients exist", (done) ->
        plumbed = sseriesOfTubes.plumb (->), interval
        remover = sseriesOfTubes.removeClientAndMaybeStopPolling originalUrl, 0
        plumbed req, res, done

        remover()

        expect(sseriesOfTubes._pollers).to.be.empty
        done()

      it "should delete the source if no more clients exist", (done) ->
        plumbed = sseriesOfTubes.plumb()
        remover = sseriesOfTubes.removeClientAndMaybeStopPolling originalUrl, 0
        plumbed req, res, done
        source  = sseriesOfTubes.source originalUrl
        expect(source).to.exist

        remover()

        source2 = sseriesOfTubes.source originalUrl
        expect(source2).to.not.exist
        expect(sseriesOfTubes._counts).to.be.empty
        done()

      it "should emit a stop event with path if source is deleted", (done) ->
        plumbed = sseriesOfTubes.plumb()
        remover = sseriesOfTubes.removeClientAndMaybeStopPolling originalUrl, 0
        plumbed req, res, done

        await
          sseriesOfTubes.once "stop", defer url
          remover()

        expect(url).to.equal originalUrl
        done()

  describe "##destroy", ->
    it "should call end on all clients", (done) ->
      plumbed = sseriesOfTubes.plumb()
      clients = []
      total   = 5
      for _ in [0..total]
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done
        clients.push client

      spies = (spy.on client, "end" for client in clients)

      sseriesOfTubes.destroy()
      expect(doubleoh.called).to.be.true for doubleoh in spies
      done()

    it "should emit 'close' event on all clients", (done) ->
      plumbed = sseriesOfTubes.plumb()
      clients = []
      total   = 5
      for _ in [0..total]
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done
        clients.push client

      spies = for client in clients
        doubleoh = spy()
        client.once "close", doubleoh
        doubleoh

      sseriesOfTubes.destroy()
      expect(doubleoh.called).to.be.true for doubleoh in spies
      done()

  describe "##encode", ->
    it "should stringify the data", ->
      data   = {test: true}
      result = sseriesOfTubes.encode data
      expect(result).to.be.a "string"

