# frozen_string_literal: true

# Paste or load in the app console after review.
# 1) Checks whether current Netatmo credentials work against the Netatmo API
# 2) Deletes cached Netatmo tokens in Redis
# Does not print token values.
#
#   usr/scripts/console.rb --remote
#   load "usr/support/clear-netatmo-redis-tokens.rb"
#
# On a Heroku one-off dyno the support file is only present if this release includes it;
# otherwise paste the body below into IRB.

require "openssl"
require "redis"
require "json"
require "net/http"
require "uri"

def netatmo_form_post(path, form)
  uri = URI("https://api.netatmo.com#{path}")
  response = Net::HTTP.post_form(uri, form)
  body =
    begin
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end
  [response.code.to_i, body]
end

def check_netatmo_credentials(client_id:, client_secret:, refresh_token:, access_token: nil)
  result = {
    "refresh_ok" => false,
    "refresh_http" => nil,
    "refresh_error" => nil,
    "homecoach_ok" => false,
    "homecoach_http" => nil,
    "homecoach_error" => nil,
    "device_count" => nil
  }

  if client_id.to_s.empty? || client_secret.to_s.empty?
    result["refresh_error"] = "missing_client_credentials"
    return result
  end

  if refresh_token.to_s.empty?
    result["refresh_error"] = "missing_refresh_token"
  else
    code, body = netatmo_form_post(
      "/oauth2/token",
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => client_id,
      "client_secret" => client_secret
    )
    result["refresh_http"] = code
    if code == 200 && body["access_token"]
      result["refresh_ok"] = true
      access_token = body["access_token"]
    else
      result["refresh_error"] = body["error"] || body.dig("error", "message") || "refresh_failed"
    end
  end

  if access_token.to_s.empty?
    result["homecoach_error"] = "missing_access_token"
    return result
  end

  code, body = netatmo_form_post(
    "/api/gethomecoachsdata",
    "access_token" => access_token
  )
  result["homecoach_http"] = code
  if code == 200 && body["body"]
    result["homecoach_ok"] = true
    devices = body.dig("body", "devices")
    result["device_count"] = devices.is_a?(Array) ? devices.length : nil
  else
    result["homecoach_error"] =
      body.dig("error", "message") || body["error"] || "homecoach_failed"
  end

  result
end

redis =
  if ENV["REDIS_URL"]
    Redis.new(url: ENV.fetch("REDIS_URL"), ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
  else
    Redis.new
  end

cached = redis.mapped_hmget("tokens", "access_token", "refresh_token", "expires_at")
puts "had_access=#{!cached["access_token"].to_s.empty?}"
puts "had_refresh=#{!cached["refresh_token"].to_s.empty?}"
puts "expires_at=#{cached["expires_at"].inspect}"
puts "env_refresh=#{!ENV["NETATMO_REFRESH_TOKEN"].to_s.empty?}"
puts "env_access=#{!ENV["NETATMO_ACCESS_TOKEN"].to_s.empty?}"

refresh_source =
  if !cached["refresh_token"].to_s.empty?
    "redis"
  elsif !ENV["NETATMO_REFRESH_TOKEN"].to_s.empty?
    "env"
  else
    "none"
  end
access_source =
  if !cached["access_token"].to_s.empty?
    "redis"
  elsif !ENV["NETATMO_ACCESS_TOKEN"].to_s.empty?
    "env"
  else
    "none"
  end

refresh_token =
  case refresh_source
  when "redis" then cached["refresh_token"]
  when "env" then ENV["NETATMO_REFRESH_TOKEN"]
  end
access_token =
  case access_source
  when "redis" then cached["access_token"]
  when "env" then ENV["NETATMO_ACCESS_TOKEN"]
  end

puts "checking_netatmo refresh_source=#{refresh_source} access_source=#{access_source}"
check = check_netatmo_credentials(
  client_id: ENV["NETATMO_CLIENT_ID"],
  client_secret: ENV["NETATMO_CLIENT_SECRET"],
  refresh_token: refresh_token,
  access_token: access_token
)
puts "netatmo_refresh_ok=#{check["refresh_ok"]} http=#{check["refresh_http"].inspect} error=#{check["refresh_error"].inspect}"
puts "netatmo_homecoach_ok=#{check["homecoach_ok"]} http=#{check["homecoach_http"].inspect} devices=#{check["device_count"].inspect} error=#{check["homecoach_error"].inspect}"

deleted = redis.del("tokens")
puts "deleted=#{deleted}"
