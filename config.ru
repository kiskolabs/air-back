require "rubygems"
require "bundler"

Bundler.require

require "dotenv"

Dotenv.load(".env.local", ".env")

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


require "./air_back"

run AirBack
