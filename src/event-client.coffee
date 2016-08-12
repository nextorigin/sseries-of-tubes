Client       = require "sse-stream/lib/client"


class EventClient extends Client
  nextEvent: (event) ->
    return @_event = event if event
    event = @_event
    delete @_event
    event

  write: (data) ->
    return @nextEvent match[1] if match = data.match? /event: (.+)/
    event = @nextEvent()
    response =
      "id: #{@_id++}\n" +
      (if event then "event: #{event}\n" else "") +
      @data_header +
      (data.split "\n").join("\n"+@data_header)+"\n\n"

    @res.write response


module.exports = EventClient
