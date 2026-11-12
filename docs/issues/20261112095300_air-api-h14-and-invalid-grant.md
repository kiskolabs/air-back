# air-api down: H14 then Netatmo invalid_grant

## Participants

- amkisko

## Decisions

- Immediate restore: scale `air-dash-api` web dyno back to 1:Basic. Observed cause was Heroku H14 (no web processes), not a code deploy failure.
- Auth path must stop using Netatmo password grant. Bootstrap and recover from `NETATMO_REFRESH_TOKEN` (authorization-code / portal-issued refresh token). Persist the refresh token Netatmo returns on every `/oauth2/token` call.
- Auth and upstream failures on `/air_quality_data` and `/measurements` return JSON with a non-2xx status instead of an uncaught 500 HTML page.
- Runtime must move off Ruby 2.6.5 / heroku-18 so the next deploy can build on a supported stack.
- Target MRI Ruby 4.0.9 (Heroku-supported latest on heroku-22/24/26 as of 2026-10-23 Dev Center; default for new apps remains 3.4.12).

## Effects

- Observed before scale: `https://air-api.kiskolabs.net/` and `/air_quality_data` returned Heroku Application Error 503; router logs `H14 No web processes running`; `heroku ps` showed zero dynos; stack `heroku-18` with next build targeting `heroku-22`.
- Observed after `heroku ps:scale web=1 -a air-dash-api`: `GET /` returned 200 `AirBack`; dyno `web.1` up on Ruby 2.6.5 / Puma 4.3.1 (older slug than current Gemfile.lock).
- Observed data path: `GET /air_quality_data` returned 500; logs `Refresh failure: invalid_grant` while refreshing Redis-cached tokens whose `expires_at` was in the past.
- Dashboard at `https://air.kiskolabs.net/` (Netlify) stayed on Loading then Network Error / auto-reload because the API could not serve data.
- Synced Netatmo access/refresh tokens from 1Password into Heroku config via `usr/scripts/sync-netatmo-tokens-from-1password.rb` (values not recorded here).
- Console check via `usr/support/clear-netatmo-redis-tokens.rb` against Netatmo API succeeded: `refresh_ok=true` (HTTP 200), `homecoach_ok=true` (HTTP 200), `device_count=3`. Redis `tokens` cleared by that script run.
- Heroku dashboard documented at https://dashboard.heroku.com/apps/air-dash-api.

## Next

- Deploy hardened air-back (refresh-token bootstrap, Ruby 4.0.9) to `air-dash-api` and set stack to heroku-24 (or heroku-26). Heroku supports MRI 4.0.9 / 3.4.12; 3.3 is security-only.
- Confirm live `GET /air_quality_data` returns device data and dashboard at `https://air.kiskolabs.net/` leaves Loading.
- Remove or stop relying on `NETATMO_USERNAME` / `NETATMO_PASSWORD` after refresh-token bootstrap is live.
- Keep web dyno at 1 unless intentionally paused; document who may scale to zero.

## Source

- Heroku app `air-dash-api` (team kisko): https://dashboard.heroku.com/apps/air-dash-api
- Custom domain `air-api.kiskolabs.net`
- Netlify site `air.kiskolabs.net` -> `air-dash`
- Scripts: `usr/scripts/sync-netatmo-tokens-from-1password.rb`, `usr/support/clear-netatmo-redis-tokens.rb`, `usr/scripts/console.rb`
- Netatmo Connect OAuth docs: https://dev.netatmo.com/apidocumentation/oauth
- Netatmo community confirmation that username/password grant was removed (Oct 2022+)
