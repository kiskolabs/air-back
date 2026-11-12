#!/usr/bin/env ruby
# frozen_string_literal: true

# Sync Netatmo access/refresh tokens from 1Password into Heroku config vars.
# Verifies the 1Password refresh token against Netatmo before writing Heroku.
# Does not print secret values. Uses Platform API JSON body (not config:set argv).
#
# Usage:
#   usr/scripts/sync-netatmo-tokens-from-1password.rb
#   HEROKU_APP=air-dash-api usr/scripts/sync-netatmo-tokens-from-1password.rb
#
# Heroku dashboard: https://dashboard.heroku.com/apps/air-dash-api
# Requires: op (signed in), heroku (signed in), curl

require "json"
require "tmpdir"
require "open3"
require "shellwords"
require "net/http"
require "uri"

APP = ENV.fetch("HEROKU_APP", "air-dash-api")
ACCESS_REF = ENV.fetch("NETATMO_ACCESS_TOKEN_OP_REF", "op://Shared/Netatmo/access_token")
REFRESH_REF = ENV.fetch("NETATMO_REFRESH_TOKEN_OP_REF", "op://Shared/Netatmo/refresh_token")

def need!(command)
  _stdout, _stderr, status = Open3.capture3("sh", "-c", "command -v #{Shellwords.escape(command)}")
  return if status.success?

  warn "missing required command: #{command}"
  exit 1
end

def capture!(*command)
  stdout, stderr, status = Open3.capture3(*command)
  unless status.success?
    warn "command failed: #{command.join(" ")}"
    warn stderr unless stderr.strip.empty?
    exit status.exitstatus.nonzero? || 1
  end
  stdout
end

def heroku_headers(auth_path)
  [
    "-H", "@#{auth_path}",
    "-H", "Accept: application/vnd.heroku+json; version=3",
    "-H", "Content-Type: application/json"
  ]
end

def verify_netatmo_refresh!(client_id:, client_secret:, refresh_token:)
  uri = URI("https://api.netatmo.com/oauth2/token")
  response = Net::HTTP.post_form(
    uri,
    "grant_type" => "refresh_token",
    "refresh_token" => refresh_token,
    "client_id" => client_id,
    "client_secret" => client_secret
  )
  body =
    begin
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

  unless response.code.to_i == 200 && body["access_token"]
    error = body["error"] || body.dig("error", "message") || "unknown"
    warn "Netatmo refresh check failed (HTTP #{response.code}, error=#{error})"
    exit 1
  end

  device_count = nil
  if body["access_token"]
    home_uri = URI("https://api.netatmo.com/api/gethomecoachsdata")
    home_response = Net::HTTP.post_form(home_uri, "access_token" => body["access_token"])
    home_body =
      begin
        JSON.parse(home_response.body.to_s)
      rescue JSON::ParserError
        {}
      end
    if home_response.code.to_i == 200 && home_body["body"]
      devices = home_body.dig("body", "devices")
      device_count = devices.is_a?(Array) ? devices.length : nil
      warn "Netatmo check ok (refresh + homecoach, devices=#{device_count.inspect})"
    else
      home_error = home_body.dig("error", "message") || home_body["error"] || "unknown"
      warn "Netatmo refresh ok but homecoach failed (HTTP #{home_response.code}, error=#{home_error})"
      exit 1
    end
  end

  # Prefer the rotated refresh token Netatmo returned for Heroku storage.
  {
    "access_token" => body.fetch("access_token"),
    "refresh_token" => body.fetch("refresh_token")
  }
end

need!("op")
need!("heroku")
need!("curl")

Dir.mktmpdir("air-back-netatmo-sync-") do |dir|
  body_path = File.join(dir, "body.json")
  auth_path = File.join(dir, "auth.header")
  response_path = File.join(dir, "response.json")
  config_path = File.join(dir, "config.json")
  File.chmod(0o700, dir)

  warn "Fetching Heroku API credentials (not printed)..."
  heroku_api_key = capture!("heroku", "auth:token").strip
  File.write(auth_path, "Authorization: Bearer #{heroku_api_key}\n")
  File.chmod(0o600, auth_path)
  heroku_api_key = nil

  warn "Reading Heroku client credentials (values not printed)..."
  http_code = capture!(
    "curl", "-sS",
    "-o", config_path,
    "-w", "%{http_code}",
    "https://api.heroku.com/apps/#{APP}/config-vars",
    *heroku_headers(auth_path)
  ).strip
  unless http_code == "200"
    warn "Heroku config read failed (HTTP #{http_code})"
    exit 1
  end
  config = JSON.parse(File.read(config_path))
  client_id = config["NETATMO_CLIENT_ID"].to_s
  client_secret = config["NETATMO_CLIENT_SECRET"].to_s
  if client_id.empty? || client_secret.empty?
    warn "Heroku app is missing NETATMO_CLIENT_ID or NETATMO_CLIENT_SECRET"
    exit 1
  end

  warn "Reading Netatmo tokens from 1Password (values not printed)..."
  access_token = capture!("op", "read", ACCESS_REF).strip
  refresh_token = capture!("op", "read", REFRESH_REF).strip

  if access_token.empty? || refresh_token.empty?
    warn "one or both 1Password fields were empty"
    exit 1
  end

  warn "Checking 1Password refresh token against Netatmo API..."
  verified = verify_netatmo_refresh!(
    client_id: client_id,
    client_secret: client_secret,
    refresh_token: refresh_token
  )
  access_token = verified.fetch("access_token")
  refresh_token = verified.fetch("refresh_token")

  File.write(
    body_path,
    JSON.generate(
      "NETATMO_ACCESS_TOKEN" => access_token,
      "NETATMO_REFRESH_TOKEN" => refresh_token
    )
  )
  File.chmod(0o600, body_path)
  access_token = nil
  refresh_token = nil
  verified = nil

  warn "Patching config vars on Heroku app #{APP} via Platform API..."
  http_code = capture!(
    "curl", "-sS",
    "-o", response_path,
    "-w", "%{http_code}",
    "-X", "PATCH", "https://api.heroku.com/apps/#{APP}/config-vars",
    *heroku_headers(auth_path),
    "--data-binary", "@#{body_path}"
  ).strip

  unless http_code == "200"
    warn "Heroku config patch failed (HTTP #{http_code})"
    exit 1
  end

  data = JSON.parse(File.read(response_path))
  %w[NETATMO_ACCESS_TOKEN NETATMO_REFRESH_TOKEN].each do |key|
    value = data[key]
    if value.nil? || value.empty?
      warn "response missing #{key}"
      exit 1
    end
    puts "#{key}=set len=#{value.length}"
  end
end

puts "Done. Deploy the refresh-token air-back build if it is not live yet."
puts "Then clear Redis tokens via usr/support/clear-netatmo-redis-tokens.rb in console,"
puts "or: heroku redis:cli -a #{APP} --confirm #{APP}  ->  DEL tokens"
