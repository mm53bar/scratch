# 20260819 — Scanning from the UI, with the run as the record

## Context

Rebuilding the digital catalogue meant `docker exec scratch bin/rails library:scan`. It takes
around two and a half minutes on a real library — it reads ID3 tags from every file over a network
mount — so it cannot happen inside a request, and needing a shell for it means it effectively only
happens when someone remembers.

## Decision

**A `ScanRun` row is the scan.** Pressing *Scan now* creates one and enqueues `LibraryScanJob`;
the job writes progress to that row as it goes; the page polls a Turbo Frame that renders it.

`LibraryScan` gained an optional block yielding `(done, total)`. Without a block it behaves exactly
as before, and it still knows nothing about jobs, rows or pages.

## Consequences

- **One scan at a time, enforced by a partial unique index** (`where: "status = 'running'"`), not
  by checking first and inserting after — which is a race. A double-click gets a notice, not a
  second scan.
- **An interrupted scan does not block the next one forever.** If the container restarts mid-scan,
  the row stays `running` and the index refuses new ones. A run that has not written progress for
  thirty minutes is treated as dead and marked failed, with a note saying so, at the moment someone
  next asks — nothing sweeps on a timer, because the only moment it matters is when someone wants
  to start a scan.
- **A failure is recorded, not just raised.** Otherwise a scan that died is indistinguishable from
  one that never started.
- **Skipped folders are listed rather than counted.** A skipped folder is one whose tags could not
  be read: a fixable problem in the files, and the whole point of surfacing it.
- **Progress writes are throttled to every two seconds.** A write per album is a lot of noise for a
  bar that moves a pixel at a time.
- **No websocket.** Polling a frame every two seconds needs no Action Cable, no connection
  upgrade through the proxy, and nothing to debug when it silently fails. The poll controller
  lives *inside* the frame and only in the branch rendered while a scan runs, so when the scan
  finishes the element is gone, the controller disconnects, and polling stops — there is no
  "should I stop now" condition to get wrong. It also skips polling a hidden tab.
- `bin/rails library:scan` records a run too, so the history on the page is the whole history
  rather than the part that happened to be started from a browser.

## Alternatives considered

- **Turbo Streams over Action Cable.** Idiomatic, and it would push instead of poll. Rejected
  because it puts a websocket through a reverse proxy into the dependency path of a progress bar,
  and when that breaks it breaks silently. Polling every two seconds for two minutes is sixty
  requests against a local SQLite row.
- **Running the scan in the request with a streaming response.** Rejected: it holds a Puma thread
  for minutes and dies with the tab.
- **A recurring scheduled scan** via `config/recurring.yml`. Not rejected so much as not yet
  needed — the trigger for a scan is "I just added an album", which a person knows and a clock
  does not. The plumbing is now in place if that changes.
