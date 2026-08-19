# 20260819 — The music library is read-only

## Context

This application catalogues music that already exists on disk. A catalogue naturally tempts you
toward "and while we're here, fix that tag" — the data is right there, the app already knows the
file, and the edit is one form away.

Tag writing is genuinely a separate problem with a separate shape. It is deterministic, it is
destructive, it needs dry runs and backups, and it is done in batches against a folder rather than
one record at a time through a web form. Combining the two means the catalogue inherits every
hazard of the writer: a bad request becomes a damaged file, and a read-only browse page becomes the
most dangerous surface in the system.

There is also a correctness argument. If two things write to the same files by different rules,
they will eventually disagree, and the disagreement will be discovered as data loss rather than as
a merge conflict.

## Decision

**The library is mounted read-only (`:ro`) and this application never writes to it.** Not to audio
files, not to sidecars, not to cover art. It reads tags to build its catalogue and does nothing
else to the tree.

Tag management is done by separate tools outside this repository.

## Consequences

- The mount flag is the guarantee. It does not rely on the application being careful, on a code
  review catching a stray write, or on there being no authentication bug — the kernel refuses.
- A feature request that requires writing to the library is a signal that the feature belongs in
  the tagging tools, not here. That is a useful boundary to have drawn in advance.
- The catalogue can be rebuilt at any time by rescanning, because it is derived data. Nothing in
  it is authoritative, so losing the database costs a scan and nothing else.
- Physical media (vinyl, CD) is the exception in the other direction: those records exist only in
  this application, because there is no file to derive them from. They are the only rows that must
  actually be backed up.

## Alternatives considered

- **Read-write with careful guards.** Rejected. The guards are only as good as the next change to
  them, and the failure mode is silent corruption of files that may not be backed up.
- **Read-write behind authentication.** Rejected, and the reasoning inverts: with no
  authentication, read-only is the property that makes running this on a home network defensible
  at all.
- **Write only sidecar files, never audio.** Tempting, and still rejected — it splits the
  "who owns this tree" answer in a way that is hard to reason about later.
