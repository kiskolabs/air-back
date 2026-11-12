# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["NETATMO_CLIENT_ID"] = "test-client-id"
ENV["NETATMO_CLIENT_SECRET"] = "test-client-secret"
ENV["NETATMO_REFRESH_TOKEN"] = "env-refresh-token"
ENV.delete("NETATMO_USERNAME")
ENV.delete("NETATMO_PASSWORD")

require "bundler/setup"
Bundler.require(:default, :test)

require "minitest/autorun"
require "rack/test"
require "json"
require "webmock/minitest"
require_relative "../air_back"

class FakeRedis
  def initialize
    @strings = {}
    @hashes = {}
    @ttls = {}
  end

  def get(key)
    @strings[key]
  end

  def setex(key, ttl, value)
    @strings[key] = value
    @ttls[key] = ttl
  end

  def ttl(key)
    @ttls.fetch(key, -1)
  end

  def mapped_hmget(key, *fields)
    hash = @hashes[key] || {}
    fields.each_with_object({}) { |field, result| result[field] = hash[field] }
  end

  def mapped_hmset(key, values)
    @hashes[key] = values.transform_keys(&:to_s)
  end

  def del(*keys)
    keys.each do |key|
      @strings.delete(key)
      @hashes.delete(key)
      @ttls.delete(key)
    end
  end
end

class AirBackTest < Minitest::Test
  include Rack::Test::Methods

  def app
    AirBack
  end

  def setup
    @redis = FakeRedis.new
    Thread.current[:air_back_redis] = @redis
    WebMock.reset!
  end

  def teardown
    Thread.current[:air_back_redis] = nil
  end

  def test_root_ok
    get "/"
    assert_equal 200, last_response.status
    assert_equal "AirBack", last_response.body
  end

  def test_air_quality_bootstraps_from_env_refresh_token
    stub_request(:post, "https://api.netatmo.com/oauth2/token")
      .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "env-refresh-token"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          access_token: "access-1",
          refresh_token: "refresh-1",
          expires_in: 10_800
        }.to_json
      )

    stub_request(:post, "https://api.netatmo.com/api/gethomecoachsdata")
      .with(body: hash_including("access_token" => "access-1"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          body: {
            devices: [{ "_id" => "device-1", "dashboard_data" => { "Temperature" => 21.5 } }]
          }
        }.to_json
      )

    get "/air_quality_data"
    assert_equal 200, last_response.status
    payload = JSON.parse(last_response.body)
    assert_equal "device-1", payload.dig("devices", 0, "_id")
    stored = @redis.mapped_hmget("tokens", "access_token", "refresh_token")
    assert_equal "access-1", stored["access_token"]
    assert_equal "refresh-1", stored["refresh_token"]
  end

  def test_air_quality_recovers_when_cached_refresh_is_invalid
    @redis.mapped_hmset(
      "tokens",
      "access_token" => "stale-access",
      "refresh_token" => "stale-refresh",
      "expires_at" => (Time.now - 60).iso8601
    )

    stub_request(:post, "https://api.netatmo.com/oauth2/token")
      .with(body: hash_including("refresh_token" => "stale-refresh"))
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: { error: "invalid_grant" }.to_json
      )

    stub_request(:post, "https://api.netatmo.com/oauth2/token")
      .with(body: hash_including("refresh_token" => "env-refresh-token"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          access_token: "access-2",
          refresh_token: "refresh-2",
          expires_in: 10_800
        }.to_json
      )

    stub_request(:post, "https://api.netatmo.com/api/gethomecoachsdata")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { body: { devices: [{ "_id" => "recovered" }] } }.to_json
      )

    get "/air_quality_data"
    assert_equal 200, last_response.status
    payload = JSON.parse(last_response.body)
    assert_equal "recovered", payload.dig("devices", 0, "_id")
    stored = @redis.mapped_hmget("tokens", "refresh_token")
    assert_equal "refresh-2", stored["refresh_token"]
  end

  def test_air_quality_returns_json_when_auth_unavailable
    ENV.delete("NETATMO_REFRESH_TOKEN")

    get "/air_quality_data"
    assert_equal 503, last_response.status
    payload = JSON.parse(last_response.body)
    assert_match(/refresh token/i, payload["error"])
  ensure
    ENV["NETATMO_REFRESH_TOKEN"] = "env-refresh-token"
  end

  def test_measurements_require_device_id
    get "/measurements"
    assert_equal 400, last_response.status
    payload = JSON.parse(last_response.body)
    assert_equal "No device_id specified", payload["error"]
  end
end
