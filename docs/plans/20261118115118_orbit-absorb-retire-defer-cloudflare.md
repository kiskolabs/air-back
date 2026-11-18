# Orbit absorbs AirBack; retire Heroku; defer Cloudflare

Design decision for this API repo. Product delivery lives in Orbit.

## Participants

- amkisko

## Decisions

- Prefer Orbit absorb over keeping or rewriting this Sinatra API. Do not move air-back to Cloudflare Workers in this pass.
- Orbit owns Netatmo Home Coach: dashboard entry, private Slack `/orbit air`, 60-second shared cache, rotated OAuth credentials encrypted in PostgreSQL. Bootstrap secrets on `kisko-orbit`: `NETATMO_CLIENT_ID`, `NETATMO_CLIENT_SECRET`, `NETATMO_REFRESH_TOKEN`.
- After Orbit cutover is verified, retire Heroku app `air-dash-api`, Heroku Redis mini, and hostname `air-api.kiskolabs.net` through Kiriki / kisko-infra. Stop legacy token refreshes before Orbit uses the same Netatmo grant so one service owns rotation.
- Keep this repository as a historical contract and ops reference. Revisit a dedicated Cloudflare wallboard or API only if a separate wall display is needed again.

## Effects

- Orbit live work already implements air quality (Search / HQ browser surface and Slack). Cutover steps and verification commands are tracked there, not re-executed from this note alone.
- This repo remains the prior Heroku + Redis implementation until destroy. No Cloudflare provider work for air-back in this pass.

## Next

- Complete Orbit air-quality cutover (secrets on `kisko-orbit`, deploy, HQ and Slack verify) per Orbit absorb live-work.
- Destroy `air-dash-api`, Redis, and API DNS via infrastructure workflow after verify.
- Close or update related Linear / Redis maintenance notes that assumed a long-lived Heroku API.

## Source

- Sibling dashboard plan: air-dash `docs/plans/20261118115118_orbit-absorb-retire-defer-cloudflare.md`
- Orbit absorb live work: orbit `docs/issues/20261117181812_absorb-legacy-kisko-apps.md` (air quality cutover)
- Orbit absorb plan: orbit `docs/plans/20261117181811_absorb-legacy-kisko-apps.md`
- Orbit changelog slice: orbit `docs/changelogs/20261117184500_absorb-legacy-kisko-apps.md`
- Prior API outage note: `docs/issues/20261112095300_air-api-h14-and-invalid-grant.md`
- Kiriki workspace: kisko-infra `kiriki/workspaces/air_dash_api/`
- Netatmo Aircare API: https://dev.netatmo.com/apidocumentation/aircare
