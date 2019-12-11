require "rubygems"
require "bundler"

Bundler.require

use Rack::Cors do
  allow do
    origins "*"

    resource "*",
      headers: :any,
      methods: [:get, :options]
  end
end

require "dotenv/load"
require "./air_back"

run AirBack
