# AirBack

A simple Sinatra backend for fetching air quality data from the [Netatmo API](https://dev.netatmo.com/apidocumentation/).

## Features

* Exchange a username & password for an access token
* Refreshes the access token before it expires
* Caches the tokens in Redis
* Fetch current air quality data for all registered devices
* Fetch data for the past hour for the given device ID
* Measurement responses are automatically cached in Redis

## Requirements

* Hardware
  * One or more [Netatmo air quality monitors](https://www.netatmo.com/en-eu/aircare/homecoach)
  * [Netatmo API ID and secret](https://dev.netatmo.com/apidocumentation/oauth)
* Dependencies
  * Redis
  * Ruby
  * Bundler

## Developing

1. Clone the repo
2. Install dependencies with `bundle install`
3. Create a `.env.local` file in the root of the project:

  ```sh
  export NETATMO_CLIENT_ID="IDIDIDIDIDIDIDIDID"
  export NETATMO_CLIENT_SECRET="SECRETSECRETSECRET"
  export NETATMO_USERNAME="you@example.com"
  export NETATMO_PASSWORD="superpassword"
  ```

4. Start the Sinatra app: `rackup`
