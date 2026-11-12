# frozen_string_literal: true

require "openssl"
require "sinatra/base"
require "json"
require "time"
require "digest"
require "http"
require "redis"

begin
  require "honeybadger"
rescue LoadError
  # optional in bare test boots
end

begin
  require "sinatra/reloader"
rescue LoadError
  # optional outside development
end

class AirBack < Sinatra::Base
  MEASUREMENT_FIELDS = "CO2,Humidity,Noise,Temperature".freeze
  TOKEN_KEY = "tokens"

  configure :development do
    register Sinatra::Reloader if defined?(Sinatra::Reloader)
  end

  configure :production, :development, :test do
    enable :logging
    set :protection, except: [:json_csrf]
    set :show_exceptions, false
  end

  error do
    err = env["sinatra.error"]
    Honeybadger.notify(err) if defined?(Honeybadger)
    content_type "application/json"
    status 500
    { error: "Something went wrong" }.to_json
  end

  get "/" do
    content_type "text/plain"
    "AirBack"
  end

  get "/air_quality_data" do
    content_type "application/json"
    key = "airquality"

    if (cached = redis.get(key))
      logger.info "Found cached air quality data"
      remaining = redis.ttl(key)
      expires remaining, :public, :must_revalidate if remaining > 0
      next cached
    end

    logger.info "Fetching new air quality data"
    data = get_airquality_data
    json = data.to_json
    ttl = data["error"] ? 30 : 60
    redis.setex(key, ttl, json)
    expires ttl, :public, :must_revalidate
    status 503 if auth_error?(data)
    json
  end

  get "/measurements" do
    content_type "application/json"
    device_id = params[:device_id]
    halt 400, { error: "No device_id specified" }.to_json unless device_id

    hash = Digest::SHA1.hexdigest(device_id.to_s.downcase)
    key = "measurements_#{hash}"
    response["Measurement-Fields"] = MEASUREMENT_FIELDS

    if (cached = redis.get(key))
      logger.info "Found cached measurements for #{device_id}"
      remaining = redis.ttl(key)
      expires remaining, :public, :must_revalidate if remaining > 0
      next cached
    end

    logger.info "Fetching new measurements for #{device_id}"
    data = get_measurements(device_id: device_id)
    json = data.to_json
    ttl = data["error"] ? 30 : 60
    redis.setex(key, ttl, json)
    expires ttl, :public, :must_revalidate
    status 503 if auth_error?(data)
    json
  end

  helpers do
    def auth_error?(data)
      message = data.is_a?(Hash) ? data["error"].to_s : ""
      message.match?(/refresh|token|grant|Missing Netatmo/i)
    end

    def get_airquality_data
      response = HTTP.post("https://api.netatmo.com/api/gethomecoachsdata", form: {
        access_token: get_tokens.fetch("access_token")
      })
      parse_netatmo_body(response, context_key: :get_airquality_data)
    rescue NetatmoAuthError => error
      { "error" => error.message }
    end

    def get_measurements(device_id:)
      now = Time.now
      response = HTTP.post("https://api.netatmo.com/api/getmeasure", form: {
        access_token: get_tokens.fetch("access_token"),
        date_begin: now.to_i - (60 * 60),
        date_end: now.to_i,
        device_id: device_id,
        limit: 1024,
        optimize: false,
        real_time: false,
        scale: "max",
        type: MEASUREMENT_FIELDS
      })
      parse_netatmo_body(response, context_key: :get_measurements)
    rescue NetatmoAuthError => error
      { "error" => error.message }
    end

    def parse_netatmo_body(response, context_key:)
      Honeybadger.context(context_key => response.headers.to_h)
      parsed = response.parse
      Honeybadger.context(context_key => parsed)

      if parsed["body"]
        body = parsed["body"]
        return { "error" => "No data received" } if body.nil? || body.respond_to?(:empty?) && body.empty?

        body.delete("user") if body.is_a?(Hash)
        body
      elsif (message = parsed.dig("error", "message") || parsed["error"])
        { "error" => message }
      else
        logger.info "Error: #{parsed.inspect}"
        { "error" => "Something went wrong" }
      end
    end

    def get_tokens
      cached = redis.mapped_hmget(TOKEN_KEY, "access_token", "refresh_token", "expires_at")
      if cached && cached["access_token"] && cached["refresh_token"] && cached["expires_at"]
        expires_at = Time.parse(cached.fetch("expires_at"))
        return cached if expires_at >= Time.now

        begin
          return refresh_access_token(refresh_token: cached.fetch("refresh_token"))
        rescue NetatmoAuthError => error
          logger.info "Cached refresh failed: #{error.message}"
          redis.del(TOKEN_KEY)
        end
      end

      bootstrap_access_token
    end

    def bootstrap_access_token
      refresh_token = ENV["NETATMO_REFRESH_TOKEN"].to_s.strip
      raise NetatmoAuthError, "Missing Netatmo refresh token" if refresh_token.empty?

      logger.info "Bootstrapping access token from NETATMO_REFRESH_TOKEN"
      refresh_access_token(refresh_token: refresh_token)
    end

    def refresh_access_token(refresh_token:)
      logger.info "Refreshing access token"
      response = HTTP.post("https://api.netatmo.com/oauth2/token", form: {
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: ENV.fetch("NETATMO_CLIENT_ID"),
        client_secret: ENV.fetch("NETATMO_CLIENT_SECRET")
      })
      handle_token_response(response)
    end

    def handle_token_response(response)
      parsed = response.parse
      if parsed["access_token"]
        expires_at = Time.now + (parsed.fetch("expires_in").to_i * 0.9).to_i
        tokens = {
          "access_token" => parsed.fetch("access_token"),
          "refresh_token" => parsed.fetch("refresh_token"),
          "expires_at" => expires_at.iso8601
        }
        redis.mapped_hmset(TOKEN_KEY, tokens)
        tokens
      elsif parsed["error"]
        raise NetatmoAuthError, "Refresh failure: #{parsed["error"]}"
      else
        raise NetatmoAuthError, "Unknown token response"
      end
    end

    def redis
      Thread.current[:air_back_redis] ||= begin
        if ENV["REDIS_URL"]
          Redis.new(url: ENV["REDIS_URL"], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
        else
          Redis.new
        end
      end
    end
  end
end

class NetatmoAuthError < StandardError; end
