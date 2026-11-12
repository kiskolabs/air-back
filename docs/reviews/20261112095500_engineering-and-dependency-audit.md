# Engineering and dependency audit: air-back / air-api outage

## Participants

- amkisko

## Decisions

- Treat live outage as two stacked faults: Heroku H14 (web=0) then Netatmo `invalid_grant` on stale Redis refresh token.
- Apply smallest restore first (scale web=1), then code changes for refresh-token auth, Ruby 3.3, tests, and JSON failure responses.
- Dependency audit depth for air-back: advisory scan of new lockfile plus freshness against registry; full OSINT on every transitive package not completed this pass.
- air-dash dependency advisory scan deferred until a local Node toolchain matching `.node-version` (or an intentional bump) is available; color-band bugs and API timeout hardening applied from engineering audit.

## Effects

Finding F1
Severity: critical
Confidence: high
Stage: cloud / ingress
Fact: `heroku ps` showed no dynos; router logged H14; `GET /` returned Heroku Application Error 503.
Fix applied: `heroku ps:scale web=1 -a air-dash-api`. `GET /` returned 200 `AirBack`.

Finding F2
Severity: critical
Confidence: high
Stage: external API / auth
Fact: after dyno up, `/air_quality_data` returned 500; logs `Refresh failure: invalid_grant`; Redis `tokens.expires_at` was 2025-02-09; password grant still in code and config but removed by Netatmo since 2022.
Fix in progress: replace password grant with `NETATMO_REFRESH_TOKEN` bootstrap, clear bad cached tokens on invalid grant, return JSON 503 for auth failures. Production still needs a fresh portal/authorization-code refresh token in config.

Finding F3
Severity: high
Confidence: high
Stage: runtime / supply chain
Fact: deployed slug ran Ruby 2.6.5 / Puma 4.3.1 / Sinatra 2.0.7 on heroku-18 while repo Gemfile.lock had drifted; Ruby 2.6 is EOL; heroku-18 is EOL.
Fix in progress: Ruby `~> 3.3.7`, regenerated Gemfile.lock, `.ruby-version`, tests. Stack bump to heroku-24 pending deploy.

Finding F4
Severity: high
Confidence: high
Stage: product surface / keep-the-work
Fact: dashboard showed Loading then Network Error with auto-reload; axios had no timeout; API error JSON was not treated as failure.
Fix applied in air-dash branch: 15s timeout, throw on `data.error`, safer ErrorComponent, initial `loading: true`.

Finding F5
Severity: medium
Confidence: high
Stage: app logic
Fact: `temperatureToColor` treated 27-29 as red because of `celsius < 20`; `noiseToColor` used `dba >= 15` instead of 50 for the blue band.
Fix applied in air-dash with unit tests.

Finding F6
Severity: medium
Confidence: high
Stage: test coverage
Fact: air-back had no executable specs before this work.
Fix applied: rack-test + WebMock specs for bootstrap, invalid-grant recovery, missing token, measurements validation. `bundle exec rake test` -> 5 runs, 0 failures.

Finding F7
Severity: medium
Confidence: medium
Stage: resource and budget
Fact: no named delivery size or build-time budget for Heroku slug or Netlify bundle in either repo.
Not fixed this pass. Check needed: add CI size/timing gates per delivery-budgets.

Finding F8
Severity: low
Confidence: high
Stage: trace and identification
Fact: Honeybadger is enabled; public API has no caller auth; CORS allows `*`. Acceptable for this internal office board only if the Netatmo token stays server-side.
No change this pass beyond keeping tokens server-side.

Dependency notes (air-back, post-upgrade lockfile)
- `bundle-audit check --update`: no vulnerabilities found (ruby-advisory-db commit 4d71b12, 2026-11-11).
- Hot path direct: sinatra, puma, http, redis, rack-cors, rack-rewrite, honeybadger, dotenv.
- Freshness: lock resolves current majors (sinatra 4.2.1, puma 8.0.2, http 6.0.4, redis 6.0.0, honeybadger 6.10.2). `bundle outdated` reported mustermann and redis-client minor lag only.
- Removed runtime dependency on Netatmo password env vars for new auth path; config may still hold legacy username/password until operators delete them.

## Next

- Operator generates Netatmo refresh token, sets `NETATMO_REFRESH_TOKEN` on `air-dash-api`, `DEL tokens` in Redis, deploys air-back branch, sets stack heroku-24.
- Install Node for air-dash (or bump engine), run `npm audit` / `npm test`, deploy Netlify when ready.
- Decide whether zero-dyno scale-downs are intentional cost control; if so, document wake procedure.
- Optional: authorization-code helper script under `usr/scripts` for token bootstrap without portal UI.

## Source

- Live: `https://air.kiskolabs.net/`, `https://air-api.kiskolabs.net/`
- Heroku: https://dashboard.heroku.com/apps/air-dash-api
- Issue: `docs/issues/20261112095300_air-api-h14-and-invalid-grant.md`
- Netatmo OAuth: https://dev.netatmo.com/apidocumentation/oauth
