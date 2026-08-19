# scratch — agent guidance

An inventory of music owned across vinyl, CD and digital. This file is standing rules, not a spec —
read the code and `docs/adr/` for the actual design.

## Standing rules

- **This repository is public.** No personal data, no real library contents, no hostnames, IP
  addresses, filesystem paths, or names of other software in the deployment. That applies to code,
  comments, fixtures, seeds, tests, docs and commit messages. Fixtures are invented, not sampled
  from a real collection.
- **The music library is read-only and that is a design constraint, not a default.** Nothing in
  this app writes to, renames, moves or deletes an audio file. Tag management is a separate concern
  that lives outside this application. If a feature seems to need write access, that is a signal
  the feature belongs elsewhere.
- Prefer Rails conventions over architecture-heavy patterns. Reach for a plain model, job or PORO
  before a new abstraction. No service layer; extract nouns, not verbs — `LibraryScan`, not
  `LibraryScanningService`.
- **Every filesystem path is configuration**, read from the environment via
  `Rails.configuration.x`, never a literal in code. Paths stored in the database are relative to a
  configured root and validated to stay inside it.
- Secrets are plain **env vars**, not Rails encrypted credentials, so the repo can be public
  without `config/credentials.yml.enc`. `compose.yaml` carries placeholders only.
- Deployment is a **single container**: web and jobs together via Solid Queue in Puma, gated on
  `RAILS_ENV=production` in `config/puma.rb`. No separate worker, no Redis.
- **No authentication and no user model.** This is a single-household tool that must not be exposed
  publicly. Do not add roles or ownership without a decision recorded as an ADR.
- Testing: Minitest with fixtures. No RSpec, no factories, no mocking library — where a real
  dependency cannot be exercised directly, inject it and use a small hand-written fake.
- Test UI behaviour with `ActionDispatch::IntegrationTest` and `assert_select`. There is no
  Capybara/Selenium harness.
- Run `bin/ci` before considering work complete — the full gate, not just `bin/rails test`.
- Record significant architectural decisions as ADRs in `docs/adr/` using
  `## Context` / `## Decision` / `## Consequences` / `## Alternatives considered`.
