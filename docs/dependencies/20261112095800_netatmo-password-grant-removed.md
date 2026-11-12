# Netatmo password / client-credentials grant removed

## Participants

- amkisko

## Dependency

- Name: Netatmo Connect OAuth (`https://api.netatmo.com/oauth2/token`)
- Version constraint: external HTTP API (not a RubyGem)
- Lockfile entry: none

## Symptom

- `air-back` called `grant_type=password` in `create_access_token` and relied on Redis-cached refresh tokens from that era.
- Production logs after dyno restore: `Refresh failure: invalid_grant` on `/air_quality_data`.
- Netatmo removed username/password authentication (announced for October 2022). Authorization-code (or portal-generated) tokens plus rotating refresh tokens are required.

## Evidence

- Heroku `air-dash-api` web logs during this incident showed `Refreshing access token` then `RuntimeError - Refresh failure: invalid_grant`.
- Netatmo community moderator statements that client credentials / username-password auth is gone; authorization-code is mandatory.
- Docs: https://dev.netatmo.com/apidocumentation/oauth
- Home Assistant thread summarizing the 2022 Netatmo security update: https://community.home-assistant.io/t/netatmo-client-credentials-grant-type-method-will-be-completely-removed/446844

## Suggested fix

- Stop using password grant.
- Bootstrap from `NETATMO_REFRESH_TOKEN` (portal Generate Token or one-time authorization-code).
- Persist every new refresh token Netatmo returns.
- On `invalid_grant`, clear Redis `tokens` and retry env bootstrap once; surface JSON error if still failing.

## Next

- Operator must place a fresh refresh token in Heroku config and clear Redis `tokens` after deploy.
- Remove unused `NETATMO_USERNAME` / `NETATMO_PASSWORD` from config when bootstrap is verified.

## Source

- Upstream: Netatmo Connect OAuth documentation and Netatmo community posts linked above
- Downstream: `air_back.rb` token helpers; Heroku `air-dash-api` config keys; issue `docs/issues/20261112095300_air-api-h14-and-invalid-grant.md`
