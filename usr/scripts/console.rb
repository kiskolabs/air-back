#!/usr/bin/env ruby
# frozen_string_literal: true

# Open an IRB console with AirBack loaded (Sinatra equivalent of rails console).
#
# Usage:
#   usr/scripts/console.rb
#   usr/scripts/console.rb --remote
#   HEROKU_APP=air-dash-api usr/scripts/console.rb --remote
#
# Heroku dashboard: https://dashboard.heroku.com/apps/air-dash-api

APP = ENV.fetch("HEROKU_APP", "air-dash-api")
ROOT = File.expand_path("../..", __dir__)

def remote?
  ARGV.include?("--remote") || ENV["REMOTE"] == "1"
end

if remote?
  exec(
    "heroku", "run",
    "bundle exec irb -r bundler/setup -I. -r ./air_back",
    "-a", APP
  )
end

Dir.chdir(ROOT)

require "bundler/setup"
Bundler.require(:default)

begin
  require "dotenv"
  Dotenv.load(".env.local", ".env")
rescue LoadError
  # dotenv optional when env is already exported
end

require File.expand_path("air_back.rb", ROOT)

require "irb"
IRB.start(__FILE__)
