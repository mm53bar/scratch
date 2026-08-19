# 20260819 — Every filesystem path is configuration

## Context

This application touches the filesystem in two places: the music library it reads, and the storage
directory holding its own database and Active Storage blobs.

Writing either as a literal is wrong twice over. It hardcodes one machine's layout into a public
repository, so anyone else running this would have to fork it to change a directory. And a path
that is a literal in code is a path that cannot be moved without a deploy.

## Decision

**No filesystem path appears as a literal anywhere in the application.** Roots are read from the
environment in `config/application.rb` and exposed through `Rails.configuration.x`:

| helper | env var | default |
|---|---|---|
| `config.x.music_library_path` | `MUSIC_LIBRARY_PATH` | `Rails.root/music` |

Each has a working default inside the app's own directory, so a fresh clone runs with no
configuration at all, and a deployment overrides only the roots it actually mounts elsewhere.

**Any path stored in the database is relative to a configured root and validated to stay inside
it.** `Pathname#join` replaces the root outright when handed an absolute path, and `expand_path`
resolves `..` lexically, so both escape attempts land outside the root and are rejected by the same
comparison.

## Consequences

- Someone else can run this without editing Ruby. That is the point.
- The library can be mounted anywhere; only the env var changes.
- Relative storage means the database is portable — moving the library to a different path does not
  invalidate every row.
- The containment check is lexical and does not resolve symlinks. An operator who deliberately
  symlinks something into the library has still pointed this app at it, which is their decision.

## Alternatives considered

- **Absolute paths in the database.** Rejected: it bakes one machine's layout into the data, and
  any move invalidates every row.
- **A settings page in the application.** Rejected for roots specifically: a path the app needs in
  order to find its own database cannot come from that database. Per-item settings can live there;
  roots cannot.
