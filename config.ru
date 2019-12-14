require "rubygems"
require "bundler"

Bundler.require

if ENV["FORCE_SSL"] == "true"
  use Rack::Rewrite do
    r301 %r{(.*)}, lambda { |match, rack_env|
      "https://#{rack_env["SERVER_NAME"]}#{match[1]}"
    }, scheme: :http
  end
end

use Rack::Cors do
  allow do
    origins "*"

    resource "*",
      headers: :any,
      methods: [:get, :options]
  end
end

use Rack::Deflater

require "dotenv/load"
require "./air_back"

run AirBack
