# 20260819 — No authentication

## Context

This is a single-household inventory of a personal record collection. There is no per-user state,
nothing is customised per person, and there is no version of it that makes sense to expose to the
internet. Adding a login means a user model, session handling, password reset, and a permanent
question of "who can see what" — for a tool where the answer is always "whoever is in the house".

## Decision

**No authentication and no user model.** Access control is the network's job: run this only
somewhere that is not publicly reachable.

## Consequences

- There is nothing to leak, because there are no credentials and no accounts.
- Every request is trusted, which is exactly why the library is mounted read-only
  (`20260819-read-only-library.md`) — the two decisions hold each other up. With no login in front,
  read-only is what makes an unauthenticated app on a home network reasonable.
- Anything stored in the database is visible to anyone who can reach the port. That is acceptable
  for "which albums do I own" and would not be for anything else, so do not add anything else.
- If this ever needs to be shared beyond one household, that is a decision to revisit deliberately,
  with a new ADR, rather than by bolting on a login.

## Alternatives considered

- **Forward-auth headers from a reverse proxy.** Reasonable, and the natural choice if this ever
  needs to distinguish people. Rejected for now because it adds a trust boundary to reason about
  for zero present benefit.
- **A single shared password.** Rejected: the friction of a login without the ability to tell
  anyone apart, and it invites the belief that the app is safe to expose.
