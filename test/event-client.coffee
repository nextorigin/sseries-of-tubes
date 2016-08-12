Client       = require "sse-stream/lib/client"
EventClient  = require "../src/event-client"

util     = require "util"
{expect} = require "chai"
{spy}    = require "sinon"
spy.on   = spy
extend   = util._extend


describe "EventClient", ->
  reqMock        = {headers: {}, accepts: (-> true), socket: setNoDelay: ->}
  resMock        = once: (->), on: (->), writeHead: (->), write: (->), end: (->)
  req            = null
  res            = null
  client         = null


  beforeEach ->
    req            = extend {}, reqMock
    res            = extend {}, resMock
    client         = new EventClient req, res

  afterEach ->
    client = null

  it "should be an extension of Client", ->
    expect(client).to.be.an.instanceof Client

  describe "##nextEvent", ->
    it "should set the next event if provided", ->
      event = "horizon"
      client.nextEvent event
      expect(client._event).to.equal event

    it "should return the next event if no arguments provided", ->
      event = "horizon"
      client.nextEvent event

      nextEvent = client.nextEvent()
      expect(nextEvent).to.equal event

  describe "##write", ->
    it "should set the next event and return if string matches Event prefix", ->
      client.res = write: spy()
      event      = "horizon"
      data       = "event: #{event}"

      client.write data

      nextEvent = client.nextEvent()
      expect(nextEvent).to.equal event
      expect(client.res.write.called).to.be.false

    it "should write to the response object with the next event", ->
      client.res = write: spy()
      event      = "horizon"
      data       = "event: #{event}"
      data2      = {hello: "world"}

      client.write data
      client.write JSON.stringify data2

      expect(client.res.write.called).to.be.true
      expect(client.res.write.args[0][0]).to.match new RegExp data
      expect(client.res.write.args[0][0]).to.match new RegExp data2.hello

    it "should write to the response object with no event", ->
      client.res = write: spy()
      event      = "horizon"
      data       = {hello: "world"}

      client.write JSON.stringify data

      expect(client.res.write.called).to.be.true
      expect(client.res.write.args[0][0]).to.not.match /event: /
      expect(client.res.write.args[0][0]).to.match new RegExp data.hello

