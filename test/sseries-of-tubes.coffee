SSEriesOfTubes = require "../src/sseries-of-tubes"
EventClient    = require "../src/event-client"
express        = require "express"


http     = require "http"
util     = require "util"
{expect} = require "chai"
{spy}    = require "sinon"
spy.on   = spy
extend   = util._extend


describe "SSEriesOfTubes", ->
  interval       = 0.01
  originalUrl    = url = "/test"
  reqMock        = {originalUrl, url, headers: {}, accepts: (-> true), method: "GET", socket: setNoDelay: ->}
  resMock        = once: (->), on: (->), writeHead: (->), write: (->), end: (->)
  req            = null
  res            = null
  server         = null
  router         = null
  sseriesOfTubes = null

  beforeEach ->
    req            = extend {}, reqMock
    res            = extend {}, resMock
    server         = new http.Server
    router         = new express.Router
    sseriesOfTubes = new SSEriesOfTubes server, interval

  afterEach ->
    req            = null
    res            = null
    server         = null
    router         = null
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
    it "should write :keepalive to every client response object", ->
      blackhat = res: write: spy()
      whitehat = res: write: spy()
      sseriesOfTubes._clients = [blackhat, whitehat]

      sseriesOfTubes.keepAlive()

      expect(blackhat.res.write.called).to.be.true
      expect(blackhat.res.write.args[0][0]).to.match
      expect(whitehat.res.write.called).to.be.true
      expect(whitehat.res.write.args[0][0]).to.match /:keepalive/

    it "should flush if response object has flush method", ->
      doubleoh = res: write: (->), flush: spy()
      sseriesOfTubes._clients = [doubleoh]

      sseriesOfTubes.keepAlive()

      expect(doubleoh.res.flush.called).to.be.true

  describe "##checkHeaders", ->

  describe "##plumb", ->
    plumbed = null

    beforeEach ->
      plumbed = sseriesOfTubes.plumb (->), interval

    afterEach ->
      plumbed = null
      sseriesOfTubes.destroy()

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

        expect(_paths[url]).to.be.empty
        plumbed req, res, done
        expect(_paths[url]).to.respondTo "write"
        done()

      it "should use a source if it exists", (done) ->
        {_paths} = sseriesOfTubes
        plumbed req, res, done
        source = _paths[url]

        expect(source).to.respondTo "write"
        plumbed req, res, done
        expect(_paths[url]).to.equal source
        done()

      it "should start polling the fn", (done) ->
        route   = spy()
        plumbed = sseriesOfTubes.plumb route, interval

        plumbed req, res, done
        await setTimeout defer(), 1.5 * interval * 1000

        expect(route.calledTwice).to.be.true
        done()

      it "should emit a poll event with original url", (done) ->
        await
          sseriesOfTubes.once "poll", defer url
          plumbed req, res, done

        expect(url).to.equal url
        done()

      it "should emit a plumb event with original url", (done) ->
        plumbed = sseriesOfTubes.plumb()

        await
          sseriesOfTubes.once "plumb", defer url
          plumbed req, res, done

        expect(url).to.equal url
        done()

      it "should emit a connection event with client", (done) ->
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        expect(client).to.be.an.instanceof EventClient
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
            return unless data.match /data/
            expect(data).to.match /subliminal/
            expect(data).to.match /true/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return unless data.match /data/
            expect(data).to.match /subliminal/
            expect(data).to.match /true/
            defer2()

          plumbed req, res1, done
          plumbed req, res2, done

        sseriesOfTubes.destroy()
        done()

  describe "##source", ->
    it "should return a source for a given path", (done) ->
      plumbed = sseriesOfTubes.plumb()
      plumbed req, res, done

      source = sseriesOfTubes.source url

      expect(source).to.exist
      done()

  describe "##combine", ->
    combined = null

    beforeEach ->
      router.get "/route1", sseriesOfTubes.plumb (->), interval
      router.get "/route2", sseriesOfTubes.plumb (->), interval
      combined = sseriesOfTubes.combine router, "/route1", "/route2"

    afterEach ->
      combined = null
      sseriesOfTubes.destroy()

    it "should return a function", ->
      expect(combined).to.be.a "function"

    describe "returned function", ->
      it "should call next with 406 error and return if headers not accepted", (done) ->
        nope = accepts: -> false
        next = (err) ->
          expect(err.statusCode).to.equal 406
          expect(err.toString()).to.match /NotAcceptable/
          done()

        result = combined nope, null, next
        expect(result).to.be.empty

      it "should create a source if none exists", (done) ->
        {_paths} = sseriesOfTubes

        expect(_paths[url]).to.be.empty
        combined req, res, done
        expect(_paths[url]).to.respondTo "write"
        done()

      it "should use a source if it exists", (done) ->
        {_paths} = sseriesOfTubes
        combined req, res, done
        source = _paths[url]

        expect(source).to.respondTo "write"
        combined req, res, done
        expect(_paths[url]).to.equal source
        done()

      it "should start polling the routes", (done) ->
        blackhat = spy()
        whitehat = spy()
        router.get "/route3", sseriesOfTubes.plumb blackhat, interval
        router.get "/route4", sseriesOfTubes.plumb whitehat, interval
        combined = sseriesOfTubes.combine router, "/route3", "/route4"

        combined req, res, done
        await setTimeout defer(), 1.5 * interval * 1000

        expect(blackhat.calledTwice).to.be.true
        expect(whitehat.calledTwice).to.be.true
        done()

      it "should emit a plumb event with original url", (done) ->
        combined = sseriesOfTubes.plumb()

        await
          sseriesOfTubes.once "plumb", defer url
          combined req, res, done

        expect(url).to.equal url
        done()

      it "should emit a connection event with client", (done) ->
        await
          sseriesOfTubes.once "connection", defer client
          combined req, res, done

        expect(client).to.be.an.instanceof EventClient
        done()

      it "should pipe all responses to all the clients", (done) ->
        message    = subliminal: true
        twice      = hasrun:     "twice"
        route3     = (rreq, rres, rnext) ->
          rres.json message
          rres.text message
          rres.send message
        route4     = (rreq, rres, rnext) ->
          await setTimeout defer(), 3 * interval
          rres.json twice
          rres.text twice
          rres.send twice
        router.get "/route3", sseriesOfTubes.plumb route3, interval
        router.get "/route4", sseriesOfTubes.plumb route4, interval
        combined = sseriesOfTubes.combine router, "/route3", "/route4"

        await
          res1       = extend {}, res
          defer1     = defer()
          defer2     = defer()
          res1.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
            return unless data.match /twice/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
            return unless data.match /twice/
            defer2()

          combined req, res1, done
          combined req, res2, done

        sseriesOfTubes.destroy()
        done()

      it "should pipe all responses to all the clients with event tags", (done) ->
        message    = subliminal: true
        twice      = hasrun:     "twice"
        route3     = (rreq, rres, rnext) ->
          rres.json message
          rres.text message
          rres.send message
        route4     = (rreq, rres, rnext) ->
          await setTimeout defer(), 3 * interval
          rres.json twice
          rres.text twice
          rres.send twice
        router.get "/route3", sseriesOfTubes.plumb route3, interval, "route-3"
        router.get "/route4", sseriesOfTubes.plumb route4, interval, "route-4"
        combined = sseriesOfTubes.combine router, "/route3", "/route4"

        await
          res1       = extend {}, res
          defer1     = defer()
          defer2     = defer()
          res1.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
              expect(data).to.match /event: route-3/
            return unless data.match /twice/
            expect(data).to.match /event: route-4/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
              expect(data).to.match /event: route-3/
            return unless data.match /twice/
            expect(data).to.match /event: route-4/
            defer2()

          combined req, res1, done
          combined req, res2, done

        sseriesOfTubes.destroy()
        done()

  describe "##multiplex", ->
    route1   = null
    route2   = null
    plexed   = null

    beforeEach ->
      router.get "/route1", sseriesOfTubes.plumb (->), interval
      router.get "/route2", sseriesOfTubes.plumb (->), interval

      plexed = sseriesOfTubes.multiplex router
      router.get "/plexed", plexed
      extend req, query: streams: "/route1,/route2"

    afterEach ->
      route1   = null
      route2   = null
      plexed   = null
      sseriesOfTubes.destroy()

    it "should return a function", ->
      expect(plexed).to.be.a "function"

    describe "returned function", ->
      it "should call next with 400 error and return if parameter missing", (done) ->
        nope = {}
        next = (err) ->
          expect(err.statusCode).to.equal 400
          expect(err.toString()).to.match /parameter required/
          expect(err.toString()).to.match /streams/
          done()

        result = plexed nope, null, next
        expect(result).to.be.empty

      it "should accept a custom parameter for streams", (done) ->
        plexed = sseriesOfTubes.multiplex router, "rivers"
        _req   = extend reqMock, query: rivers: "/route1,/route2"

        plexed _req, res, done
        done()

      it "should create a source if none exists", (done) ->
        {_paths} = sseriesOfTubes
        req.url  = "/plexed?streams=/route1,/route2"

        expect(_paths[req.url]).to.be.empty
        router.handle req, res, done
        expect(_paths[req.url]).to.respondTo "write"
        done()

      it "should use a source if it exists, even if streams are sorted differently", (done) ->
        {_paths} = sseriesOfTubes
        req.url  = "/plexed?streams=/route1,/route2"
        errIfErr = (err) -> done err if err

        router.handle req, res, done
        source = _paths[req.url]

        expect(source).to.respondTo "write"
        req.url  = "/plexed?streams=/route2,/route1"
        router.handle req, res, errIfErr
        expect(_paths[req.url]).to.equal source
        done()

      it "should start polling the routes", (done) ->
        blackhat = spy()
        whitehat = spy()
        req.url  = "/plexed?streams=/route3,/route4"
        req.query = streams: "/route3,/route4"
        router.get "/route3", sseriesOfTubes.plumb blackhat, interval
        router.get "/route4", sseriesOfTubes.plumb whitehat, interval

        router.handle req, res, done
        await setTimeout defer(), 1.5 * interval * 1000

        expect(blackhat.calledTwice).to.be.true
        expect(whitehat.calledTwice).to.be.true
        done()

      it "should start polling the routes from an array of streams", (done) ->
        blackhat = spy()
        whitehat = spy()
        req.url  = "/plexed?streams=/route3,/route4"
        req.query = streams: ["/route3", "/route4"]
        router.get "/route3", sseriesOfTubes.plumb blackhat, interval
        router.get "/route4", sseriesOfTubes.plumb whitehat, interval

        router.handle req, res, done
        await setTimeout defer(), 1.5 * interval * 1000

        expect(blackhat.calledTwice).to.be.true
        expect(whitehat.calledTwice).to.be.true
        done()

      it "should emit a plumb event with original url", (done) ->
        plexed = sseriesOfTubes.plumb()

        await
          sseriesOfTubes.once "plumb", defer url
          plexed req, res, done

        expect(url).to.equal url
        done()

      it "should emit a connection event with client", (done) ->
        await
          sseriesOfTubes.once "connection", defer client
          plexed req, res, done

        expect(client).to.be.an.instanceof EventClient
        done()

      it "should pipe all responses to all the clients", (done) ->
        message    = subliminal: true
        twice      = hasrun:     "twice"
        req.url    = "/plexed?streams=/route3,/route4"
        route3     = (rreq, rres, rnext) ->
          rres.json message
          rres.text message
          rres.send message
        route4     = (rreq, rres, rnext) ->
          await setTimeout defer(), 3 * interval
          rres.json twice
          rres.text twice
          rres.send twice
        router.get "/route3", sseriesOfTubes.plumb route3, interval
        router.get "/route4", sseriesOfTubes.plumb route4, interval
        plexed = sseriesOfTubes.multiplex router

        await
          res1       = extend {}, res
          defer1     = defer()
          defer2     = defer()
          res1.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
            return unless data.match /twice/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
            return unless data.match /twice/
            defer2()

          router.handle req, res1, done
          router.handle req, res2, done

        sseriesOfTubes.destroy()
        done()

      it "should pipe all responses to all the clients with event tags", (done) ->
        message    = subliminal: true
        twice      = hasrun:     "twice"
        req.url    = "/plexed?streams=/route3,/route4"
        route3     = (rreq, rres, rnext) ->
          rres.json message
          rres.text message
          rres.send message
        route4     = (rreq, rres, rnext) ->
          await setTimeout defer(), 3 * interval
          rres.json twice
          rres.text twice
          rres.send twice
        router.get "/route3", sseriesOfTubes.plumb route3, interval, "route-3"
        router.get "/route4", sseriesOfTubes.plumb route4, interval, "route-4"
        plexed = sseriesOfTubes.multiplex router

        await
          res1       = extend {}, res
          defer1     = defer()
          defer2     = defer()
          res1.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
              expect(data).to.match /event: route-3/
            return unless data.match /twice/
            expect(data).to.match /event: route-4/
            defer1()

          res2       = extend {}, res
          res2.write = (data) ->
            return unless data.match /data/
            if data.match /subliminal/
              expect(data).to.match /true/
              expect(data).to.match /event: route-3/
            return unless data.match /twice/
            expect(data).to.match /event: route-4/
            defer2()

          router.handle req, res1, done
          router.handle req, res2, done

        sseriesOfTubes.destroy()
        done()

  describe "##removeClientAndMaybeStopPolling", ->
    it "should return a function", ->
      remover = sseriesOfTubes.removeClientAndMaybeStopPolling()
      expect(remover).to.be.a "function"

    describe "returned function", ->
      it "should unpipe the client from the source", (done) ->
        plumbed = sseriesOfTubes.plumb (->), interval
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        remover = sseriesOfTubes.removeClientAndMaybeStopPolling url, client.id
        await
          client.on "unpipe", defer()
          remover()

        done()

      it "should stop polling if no more clients exist", (done) ->
        plumbed = sseriesOfTubes.plumb (->), interval
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        remover = sseriesOfTubes.removeClientAndMaybeStopPolling url, client.id
        remover()

        expect(sseriesOfTubes._pollers).to.be.empty
        done()

      it "should delete the source if no more clients exist", (done) ->
        plumbed = sseriesOfTubes.plumb (->), interval
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        remover = sseriesOfTubes.removeClientAndMaybeStopPolling url, client.id
        source  = sseriesOfTubes.source url
        expect(source).to.exist

        remover()

        source2 = sseriesOfTubes.source url
        expect(source2).to.not.exist
        expect(sseriesOfTubes._counts).to.be.empty
        done()

      it "should emit a stop event with path if source is deleted", (done) ->
        plumbed = sseriesOfTubes.plumb()
        await
          sseriesOfTubes.once "connection", defer client
          plumbed req, res, done

        remover = sseriesOfTubes.removeClientAndMaybeStopPolling url, client.id

        await
          sseriesOfTubes.once "stop", defer url
          remover()

        expect(url).to.equal url
        done()

  describe "##removeClientAndMaybeStopMultiplePolling", ->
    it "should return a function", ->
      remover = sseriesOfTubes.removeClientAndMaybeStopMultiplePolling null, null, []
      expect(remover).to.be.a "function"

    describe "returned function", ->
      it "should remove all pollers", (done) ->
        router.get "/route1", sseriesOfTubes.plumb (->), interval
        router.get "/route2", sseriesOfTubes.plumb (->), interval
        paths    = ["/route1", "/route2"]
        combined = sseriesOfTubes.combine router, paths...

        await
          sseriesOfTubes.once "connection", defer client
          combined req, res, done

        source   = sseriesOfTubes.source url
        doubleoh = spy.on source, "unwrap"
        remover = sseriesOfTubes.removeClientAndMaybeStopMultiplePolling url, client.id, paths
        i = 0
        sseriesOfTubes.on "stop", (url) ->
          switch ++i
            when 1 then expect(url).to.equal url
            when 2 then expect(url).to.equal "/route1"
            when 3
              expect(url).to.equal "/route2"
              expect(doubleoh.called).to.be.true
              done()

        remover()

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

