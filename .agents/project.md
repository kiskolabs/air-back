## Additional instructions

### .agents/project.md
AirBack Sinatra API (`kiskolabs/air-back`). Default branch is `master`.

Fetches Netatmo Home Coach air quality and measurement data, caches responses and OAuth tokens in Redis, and exposes JSON over Rack/Puma.

GitHub: https://github.com/kiskolabs/air-back

Evidence: git, `docs/`, `usr/`, PRs, GitHub. Reads from those sources are allowed. Writes are not implied by listing them.

## Credentials and env

Env names only (never commit values):

- `NETATMO_CLIENT_ID`, `NETATMO_CLIENT_SECRET`, `NETATMO_USERNAME`, `NETATMO_PASSWORD`
- `REDIS_URL` (optional; defaults to local Redis)
- `FORCE_SSL` (optional; redirects HTTP to HTTPS via rack-rewrite)
- Honeybadger via its usual env when enabled

Local dotenv files: `.env.local`, `.env` (loaded from `config.ru`). Do not commit them.

## Product boundaries

- Stack: Ruby / Sinatra / Puma / Redis / HTTP gem; entrypoints `config.ru`, `air_back.rb`, `Procfile`.
- Public routes: `GET /`, `GET /air_quality_data`, `GET /measurements?device_id=…`.
- Netatmo is an external dependency; treat token refresh and API errors as first-class paths.
- Redis holds rebuildable cache and token state, not durable product truth.

## External service writes

- Read GitHub and similar tools when they help the task.
- Do not create, update, comment, post, or otherwise write to those services unless this turn names that destination and the write.
- Repo work is not that request. Drafts stay in the reply or in `docs/` until the user says to send them.

## Documentation layout

- Agent working records use docs-conventions timestamp trees under `docs/`.
- Workshop and ops material stay under `usr/` (existing `usr/bin/orbit-upload`).
- Blank note skeletons live under `usr/templates/note/` from docs-conventions.
- Do not put secrets, tokens, or machine-local absolute paths in `docs/` or committed `usr/` text.

## Skills

- engineering-audit, security-audit, claims-audit, derivation-audit, pressure-benchmarking: packaged from amkisko/prayers under `.agents/skills/`
