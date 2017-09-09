# sseries-of-tubes

[![Greenkeeper badge](https://badges.greenkeeper.io/nextorigin/sseries-of-tubes.svg)](https://greenkeeper.io/)

[![Build Status][ci-master]][travis-ci]
[![Coverage Status][coverage-master]][coveralls]
[![Dependency Status][dependency]][david]
[![devDependency Status][dev-dependency]][david]
[![Downloads][downloads]][npm]

Takes Express/Connect routes and creates stream.Writable endpoints for Server Sent Events.

[![NPM][npm-stats]][npm]

# Introduction

SSEriesOfTubes attaches to an http.Server and efficiently manages each endpoint for Server Sent Events by creating a writeable `StringTube` Stream that is piped to every http.Response.  `StringTube` is a utf8 String Stream subclassed from Through2.

Additionally, SSEriesOfTubes can wrap a standard Express/Connect route controller (a `function` that takes arguments `(req, res, next)`), poll that controller for data, and push that data to the SSE stream.

This way, any API can easily support REST/polling and Server Sent Events with the same route controller.

SSEriesOfTubes is an EventEmitter based on [chrisdickinson/sse-stream](https://github.com/chrisdickinson/sse-stream), so it handles SSE headers, keep-alive messaging, and emits events around the connection and polling lifecycle.

# Installation
```sh
npm install --save sseries-of-tubes
```

# Usage

## Example

```coffee
# on server
http           = require "http"
express        = require "express"
SSEriesOfTubes = require "sseries-of-tubes"

server         = new http.Server
app            = express()
sseriesOfTubes = new SSEriesOfTubes server

sendHello = (req, res, next) ->
    res.json hello: "world"

# Sends {"hello": "world"} every 3s to every client connected to /sse/hello
app.get "/sse/hello", sseriesOfTubes.plumb sendHello, 3

...

# on client
source = new EventSource "/sse/hello"
# log {"hello": "world"} as received every 3s
source.onmessage = (data) -> console.log data

```

## Interface

#### SSEriesOfTubes.StringTube

Pointer to class StringTube, a [Through2](https://github.com/rvagg/through2) Readable/Writable stream.

#### SSEriesOfTubes::constructor(server, keepAliveInterval)
```coffee
new SSEriesOfTubes http.Server server, int keepAliveInterval
```
returns sseriesOfTubes instance

Creates a new SSEriesOfTubes instance that reacts to http.Server "listening" and "close" events.

#### sseriesOfTubes.plumb(fn, interval)
```coffee
sseriesOfTubes.plumb Function route, int interval
```
returns Function route

Creates a new StringTube source which polls a route to write to all clients for an endpoint.

#### sseriesOfTubes.plumb(fn, interval, event)
```coffee
sseriesOfTubes.plumb Function route, int interval, String event
```
returns Function route

Creates a new StringTube source which polls a route to write to all clients for an endpoint, and will send the event `event` (in EventSource syntax) before sending data.

#### sseriesOfTubes.plumb()
```coffee
sseriesOfTubes.plumb()
```
returns Function route

Creates a new StringTube source which writes to all clients for an endpoint.

#### sseriesOfTubes.source(url)
```coffee
sseriesOfTubes.source String url
```
returns StringTube source

Retrieves the StringTube source for an endpoint.

#### sseriesOfTubes.combine(router, paths...)
```coffee
sseriesOfTubes.combine express.Router router, String paths...
```
returns Function route

Creates a new StringTube source by combining existing StringTube sources referenced by their `path`.  This way different combinations of streams can be provided without duplicating pollers.  Requires a `router` conforming to the express.Router interface for method `handle`.

#### sseriesOfTubes.multiplex(router, param = "streams")
```coffee
sseriesOfTubes.multiplex express.Router router, String param
```
returns Function route

Creates new StringTube sources by dynamically combining existing StringTube sources, referenced by their `path` in an comma-separated list provided by the client in the query or body as parameter `param`.  This method is similar to `combine`, but works with paths that have route parameters.  Requires a `router` conforming to the express.Router interface for method `handle`.

#### sseriesOfTubes.destroy()
```coffee
sseriesOfTubes.destroy()
```
Ends all SSE client connections and destroys all clients.

## Events

#### connection
```coffee
sseriesOfTubes.on "connection", (client) ->
```
On client connection, calls bound function with an instance of Client.

#### poll
```coffee
sseriesOfTubes.on "poll", (url) ->
```
On route start poll, calls bound function with the url endpoint.

#### plumb
```coffee
sseriesOfTubes.on "plumb", (url) ->
```
On route start plumb (creates StringTube source), calls bound function with the url endpoint.

#### stop
```coffee
sseriesOfTubes.on "stop", (url) ->
```
On last client disconnect, calls bound function with the url endpoint.

# License

MIT

  [ci-master]: https://img.shields.io/travis/nextorigin/sseries-of-tubes/master.svg?style=flat-square
  [travis-ci]: https://travis-ci.org/nextorigin/sseries-of-tubes
  [coverage-master]: https://img.shields.io/coveralls/nextorigin/sseries-of-tubes/master.svg?style=flat-square
  [coveralls]: https://coveralls.io/r/nextorigin/sseries-of-tubes
  [dependency]: https://img.shields.io/david/nextorigin/sseries-of-tubes.svg?style=flat-square
  [david]: https://david-dm.org/nextorigin/sseries-of-tubes
  [dev-dependency]: https://img.shields.io/david/dev/nextorigin/sseries-of-tubes.svg?style=flat-square
  [david-dev]: https://david-dm.org/nextorigin/sseries-of-tubes#info=devDependencies
  [downloads]: https://img.shields.io/npm/dm/sseries-of-tubes.svg?style=flat-square
  [npm]: https://www.npmjs.org/package/sseries-of-tubes
  [npm-stats]: https://nodei.co/npm/sseries-of-tubes.png?downloads=true&downloadRank=true&stars=true
