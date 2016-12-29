HTTPS          = require 'https'
HTTP           = require 'http'
{EventEmitter} = require 'events'
URL           = require 'url'
Robot         = (require 'hubot').Robot
Adapter       = (require 'hubot').Adapter
TextMessage   = (require 'hubot').TextMessage

class Chiwawa extends Adapter
  send: (envelope, strings...) ->
    for str in strings
      @bot.Groups(envelope.room).Messages().create str, (err, data) =>
        @robot.logger.error "Chiwawa send error: #{err}" if err?

  run: ->
    self = @

    options =
      apiToken:   process.env.HUBOT_CHIWAWA_API_TOKEN
      webhookToken:   process.env.HUBOT_CHIWAWA_WEBHOOK_TOKEN
      botid:   process.env.HUBOT_CHIWAWA_BOTID
      account: process.env.HUBOT_CHIWAWA_ACCOUNT

    bot = new ChiwawaStreaming(options, @robot)

    bot.on "message", (message) =>
      user = @robot.brain.userForId message.createdBy,
        user: message.createdUserName
        room: message.groupId
      unless message.createdBy is options.botid
        switch message.type
          when "text"
            @robot.logger.debug "handle text message"
            @receive new TextMessage user, message.text, message.messageId
          when "image"
            @receive new TextMessage user, "", message.messageId
          else
            @robot.logger.error "Chiwawa unknown message type [#{message.type}]"

    bot.listen()

    @bot = bot

    self.emit "connected"

exports.use = (robot) ->
  new Chiwawa robot

class ChiwawaStreaming extends EventEmitter
  constructor: (options, @robot) ->
    unless options.apiToken? and options.webhookToken?  and options.botid? and options.account?
      @robot.logger.error \
        "Not enough parameters provided. I need a api token, webhook token, botid and account"
      process.exit(1)

    @apiToken      = options.apiToken
    @webhookToken  = options.webhookToken
    @botid         = options.botid
    @account       = options.account
    @host          = @account + ".chiwawa.one"

  Groups: (groupId) ->
    self = @
    logger = @robot.logger
    baseUrl = "/groups/#{groupId}"

    Messages: ->
      path = "#{baseUrl}/messages"
      create: (text, callback) ->
        body =
          text: text
        self.post path, body, callback

      list: (callback) ->
        self.get path, "", callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  get: (path, body, callback) ->
    @request "GET", path, body, callback

  request: (method, path, body, callback) ->
    logger = @robot.logger

    headers =
      "X-Chiwawa-API-Token" : @apiToken
      "Host"          : @host
      "Content-Type"  : "application/json"

    options =
      "agent"  : false
      "host"   : @host
      "port"   : 443
      "path"   : "/api/public/v1#{path}"
      "method" : method
      "headers": headers

    if method is "POST" || method is "PUT"
      if typeof(body) isnt "string"
        body = JSON.stringify body

      body = new Buffer(body)
      options.headers["Content-Length"] = body.length

    request = HTTPS.request options, (response) ->
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", ->
        if response.statusCode >= 400
          switch response.statusCode
            when 401
              throw new Error "Invalid access token provided"
            else
              logger.error "Chiwawa HTTPS status code: #{response.statusCode}"
              logger.error "Chiwawa HTTPS response data: #{data}"

        if callback
          try
            callback null, JSON.parse(data)
          catch error
            callback null, data or { }

      response.on "error", (err) ->
        logger.error "Chiwawa HTTPS response error: #{err}"
        callback err, { }

    if method is "POST" || method is "PUT"
      request.end(body, 'binary')
    else
      request.end()

    request.on "error", (err) ->
      logger.error "Chiwawa request error: #{err}"

  listen: ->
    @robot.router.post "/", (request, response) =>
      verifyToken = request.headers['x-chiwawa-webhook-token']

      if verifyToken is @webhookToken
        @robot.logger.debug "Chiwawa listen [#{JSON.stringify(request.body)}]"
        event = request.body
        switch event.type
          when 'message'
            @emit 'message', event.message
          else
            @robot.logger.warn "unknown event type [#{event.type}]"
        response.send 'OK'
      else
        response.statusCode = 401
        response.send 'Invalid webhook token provided'
