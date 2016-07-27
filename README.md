# sseries-of-tubes
Takes Express/Connect routes and creates stream.Writable endpoints for Server Sent Events

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
source.on "data", (data) -> console.log data

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

#### sseriesOfTubes.plumb()
```coffee
sseriesOfTubes.plumb()
```
returns Function route

Creates a new StringTube source which writes to all clients for an endpoint.

#### sseriesOfTubes.source(originalUrl)
```coffee
sseriesOfTubes.source String originalUrl
```
returns StringTube source

Retrieves the StringTube source for an endpoint.

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
sseriesOfTubes.on "poll", (originalUrl) ->
```
On route start poll, calls bound function with the url endpoint.

#### plumb
```coffee
sseriesOfTubes.on "plumb", (originalUrl) ->
```
On route start plumb (creates StringTube source), calls bound function with the url endpoint.

#### stop
```coffee
sseriesOfTubes.on "stop", (originalUrl) ->
```
On last client disconnect, calls bound function with the url endpoint.

# License

MIT
