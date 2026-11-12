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
2. Use Ruby 4.0.9 (`rbenv install` / `.ruby-version`)
3. Install dependencies with `bundle install`
4. Create a `.env.local` file in the root of the project:

  ```sh
  export NETATMO_CLIENT_ID="your-client-id"
  export NETATMO_CLIENT_SECRET="your-client-secret"
  export NETATMO_REFRESH_TOKEN="your-refresh-token"
  ```

  Netatmo removed the username/password grant. Create an authorization-code
  token once in the [Netatmo developer portal](https://dev.netatmo.com/)
  (Generate a Token with `read_homecoach`) or complete the OAuth redirect flow,
  then store the latest refresh token. Every successful `/oauth2/token` call
  returns a new refresh token; this app persists it in Redis.

5. Start Redis locally, then run `bundle exec rackup`
6. Run tests with `bundle exec rake test`

## Production notes

- Heroku app: [`air-dash-api`](https://dashboard.heroku.com/apps/air-dash-api) (custom domain `air-api.kiskolabs.net`)
- Required config: `NETATMO_CLIENT_ID`, `NETATMO_CLIENT_SECRET`, `NETATMO_REFRESH_TOKEN`, `REDIS_URL`
- Optional config: `NETATMO_ACCESS_TOKEN` (synced for ops; runtime bootstraps from refresh token)
- Keep at least one `web` dyno running; H14 means the process formation is zero
- Sync tokens from 1Password (does not print values): `usr/scripts/sync-netatmo-tokens-from-1password.rb`
- App console (local / Heroku): `usr/scripts/console.rb` or `usr/scripts/console.rb --remote`
- After rotating tokens, clear Redis cache in console via `usr/support/clear-netatmo-redis-tokens.rb` (or `DEL tokens` in `heroku redis:cli`)
