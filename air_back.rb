require "openssl"
require "sinatra/base"
require "sinatra/reloader"

require "honeybadger"

class AirBack < Sinatra::Base
  MEASUREMENT_FIELDS = "CO2,Humidity,Noise,Temperature".freeze

  configure :development do
    register Sinatra::Reloader
  end

  configure :production, :development do
    enable :logging
    set :protection, except: [:json_csrf]
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
      if remaining > 0
        expires remaining, :public, :must_revalidate
      end

      cached
    else
      logger.info "Fetching new air quality data"
      data = get_airquality_data
      Honeybadger.context(data: data)
      json = data.to_json
      ttl = data["error"] ? 30 : 60
      redis.setex("airquality", ttl, json)
      expires ttl, :public, :must_revalidate
      json
    end
  end

  get "/measurements" do
    content_type "application/json"

    if (device_id = params[:device_id])
      hash = Digest::SHA1.hexdigest(device_id.to_s.downcase)
      key = "measurements_#{hash}"

      response["Measurement-Fields"] = MEASUREMENT_FIELDS

      if (cached = redis.get(key))
        logger.info "Found cached measurements for #{device_id}"

        remaining = redis.ttl(key)
        if remaining > 0
          expires remaining, :public, :must_revalidate
        end

        cached
      else
        logger.info "Fetching new measurements for #{device_id}"
        data = get_measurements(device_id: params[:device_id])
        Honeybadger.context(data: data)
        json = data.to_json
        ttl = data["error"] ? 30 : 60
        redis.setex("measurements_#{hash}", ttl, json)
        expires ttl, :public, :must_revalidate
        json
      end
    else
      { error: "No device_id specified" }.to_json
    end
  end

  def get_airquality_data
    response = HTTP.post("https://api.netatmo.com/api/gethomecoachsdata", form: {
      access_token: get_tokens["access_token"]
    })

    parsed = response.parse

    if parsed["body"]
      body = parsed["body"]
      body.delete("user")
      body
    elsif (message = parsed.dig("error", "message"))
      { "error" => message }
    else
      logger.info "Error: #{parsed.inspect}"
      { "error" => "Something went wrong" }
    end
  end

  def get_measurements(device_id:)
    now = Time.now

    response = HTTP.post("https://api.netatmo.com/api/getmeasure", form: {
      access_token: get_tokens["access_token"],
      date_begin: now.to_i - (60 * 60), # 1 hour ago
      date_end: now.to_i,
      device_id: device_id,
      limit: 1024,
      optimize: false,
      real_time: false,
      scale: "max",
      type: MEASUREMENT_FIELDS
    })

    parsed = response.parse

    pp parsed

    if parsed["body"]
      body = parsed["body"]
      # body.delete("user")
      body
    elsif (message = parsed.dig("error", "message"))
      return { "error" => message }
    else
      logger.info "Error: #{parsed.inspect}"
      return { "error" => "Something went wrong" }
    end
  end

  def get_tokens
    cached = redis.mapped_hmget("tokens", "access_token", "refresh_token", "expires_at")

    if cached && cached["access_token"]
      expires_at = Time.parse(cached.fetch("expires_at"))

      if expires_at < Time.now
        refresh_access_token(refresh_token: cached.fetch("refresh_token"))
      else
        logger.info "Found valid cached tokens"
        cached
      end
    else
      create_access_token
    end
  end

  def create_access_token
    logger.info "Getting new access_token"

    response = HTTP.post("https://api.netatmo.com/oauth2/token", form: {
      grant_type: "password",
      client_id: ENV.fetch("NETATMO_CLIENT_ID"),
      client_secret: ENV.fetch("NETATMO_CLIENT_SECRET"),
      username: ENV.fetch("NETATMO_USERNAME"),
      password: ENV.fetch("NETATMO_PASSWORD"),
      scope: "read_homecoach",
    })

    handle_token_response(response)
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
      # Set the expiry a little sooner than required for some leeway
      expires_at = Time.now + (parsed.fetch("expires_in") * 0.9).to_i

      tokens = {
        "access_token" => parsed.fetch("access_token"),
        "refresh_token" => parsed.fetch("refresh_token"),
        "expires_at" => expires_at.iso8601
      }
      redis.mapped_hmset("tokens", tokens)

      return tokens
    elsif parsed["error"]
      raise "Refresh failure: #{parsed["error"]}"
    else
      raise "Unknown error"
    end
  end

  def redis
    Thread.current[:air_back_redis] ||= if ENV["REDIS_URL"]
      Redis.new(url: ENV["REDIS_URL"])
    else
      Redis.new
    end
  end
end
