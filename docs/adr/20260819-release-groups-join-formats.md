# 20260819 — Release groups join formats; tracks belong to releases

## Context

The point of this application is to answer *what do I own, across formats* — to
know that the record on the shelf and the files on disk are the same album.
Getting that wrong makes everything else pointless: if vinyl and digital are
unrelated rows, "what do I own on vinyl but not digitally" becomes a fuzzy
title-matching problem, and fuzzy matching over a personal collection is a
source of permanent low-grade wrongness.

The complication is that different releases of the same album genuinely differ.
A deluxe CD has bonus tracks. A vinyl pressing splits a long album across sides
and sometimes drops a track. A remaster renumbers. These are not errors to be
reconciled — they are true, simultaneously.

## Decision

Three levels, not two:

- **`release_group`** — the album as a concept. "Rumours" is one row however many
  copies of it you own. It belongs to an artist and carries the album's own year.
- **`release`** — a specific thing you own: this vinyl, that CD, the files on
  disk. It has a `medium` of `vinyl`, `cd` or `digital`, an optional `edition`
  ("Deluxe Edition"), and its own year, which for a reissue is not the album's.
- **`track`** — belongs to a **release**, not to the group.

Two releases sharing a `release_group_id` are the same album on different media.
That single fact makes the headline query a group-by:

```ruby
ReleaseGroup.on_medium("vinyl").not_on_medium("digital")
```

Both scopes are `EXISTS` subqueries rather than joins, so asking two questions at
once does not multiply rows.

## Consequences

- Differing track counts across formats are represented rather than reconciled.
  A nine-track vinyl and a twelve-track deluxe CD of one album are both simply
  true, and neither has to win.
- The gap query needs no matching logic, no similarity threshold and no manual
  confirmation step. Two rows either share a group id or they do not.
- The natural key on a group is `(artist_id, title)`. Two artists may both have
  an album called *Low Tide*; one artist may not have two.
- A physical release stops at tracks with no file. The file columns on `tracks`
  are nullable for exactly this reason, and a release's `path` is rejected
  unless it is digital — a physical release with a path would be silently
  rewritten by the next scan.
- Tracks carry an optional `artist_credit`, nil meaning "same as the album
  artist". Compilations need it; ordinary albums should not carry the noise.

## Alternatives considered

- **Two levels: album and track, with a format column on the album.** Rejected.
  Owning an album twice means duplicating it, and the two copies then have no
  stated relationship — which is precisely the question being asked.
- **Tracks on the release group, with releases listing which tracks they
  include.** A join table would model differing contents faithfully, but it
  makes the common case (list this record's tracks in order) a three-table
  query, and it has nothing to say about a track that exists only on one
  pressing. Rejected as more machinery for less clarity.
- **Matching formats by title similarity at query time.** Rejected: this is the
  fuzzy matching the schema exists to avoid, and it would be recomputed on every
  page load.
- **A separate `media_files` table.** Deferred, not dismissed. Every track here
  has exactly one file, so a second table would be a join with nothing on the
  other side. If multiple encodings of one track ever need to coexist, that is
  the moment to extract it — the file columns move wholesale.
