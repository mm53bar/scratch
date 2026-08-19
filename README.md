# scratch

A self-hosted inventory of the music you own — **vinyl, CD and digital, in one view**.

Streaming services know what you can listen to. A media server knows what is on your disk. Neither
knows what is on your shelf, and nothing joins the two. scratch is the thing that says *"I own
Rumours on vinyl and digitally, and Pet Sounds only on CD."*

## What it does

- Catalogues releases across **vinyl, CD and digital**, joined by album rather than by format
- Answers *what do I own on vinyl but not digitally* — and the reverse
- Browses by artist and album, and searches every track
- Adds physical media by looking it up online, including by barcode

## What it does not do

- **It is not a player.** Use a media server for that.
- **It never writes to your music files.** The library is mounted read-only; scratch reads tags and
  nothing else. Tagging is a separate concern and deliberately outside this app.
- It does not scan for duplicates, transcode, or manage downloads.

## Status

Early. The skeleton deploys and reads its configuration; the catalogue is next.

## Running it

The library is mounted **read-only** and every path is configuration. See `compose.yaml` for a
documented template — copy it, set the volume paths, the `user:` UID:GID and `SECRET_KEY_BASE`,
then deploy.

```bash
docker compose up -d
```

There is **no authentication**. Run it only somewhere that is not publicly reachable.

## Configuration

All configuration is environment variables — there are no Rails encrypted credentials, so this
repository can be public without hiding anything.

| variable | what it does |
|---|---|
| `SECRET_KEY_BASE` | Rails session/cookie signing key. Required. `openssl rand -hex 64` |
| `MUSIC_LIBRARY_PATH` | where the music is mounted inside the container. Defaults to `music/` inside the app |
| `HTTP_PORT` | the port Thruster listens on. The image default of 80 cannot always be bound by a non-root user |
| `RAILS_MAX_THREADS` | Puma threads. Browsing is read-heavy and SQLite in WAL mode handles concurrent readers well |
| `VIPS_CONCURRENCY` | caps libvips per-image parallelism so thumbnail generation cannot starve the web server |
| `MUSICBRAINZ_CONTACT` | optional. An address or URL sent in the `User-Agent` on catalogue lookups. MusicBrainz asks clients to identify themselves and throttles anonymous ones harder. Left out of the default on purpose: this repository is public and someone else's address is not ours to ship |
| `TZ` | container timezone |

## Adding physical media

Records and CDs are the only thing here a scan cannot find, so they are typed in — but mostly not
by hand. Every pressing carries a catalogue number on its label and usually its spine (`T-2576`,
`PMC 7009`), and for anything pressed before barcodes it is the only identifier on the object.
Enter it on **Add to your shelf** and the form fills itself from MusicBrainz, tracklist included.

The number names an *edition*, not a copy: Capitol used `ST-2576` in 1966 and again in 1971 after
the label changed, and territories share numbers. So a lookup lists what the number could mean and
a person picks. It never decides.

Nothing depends on it. If MusicBrainz is unreachable, rate limiting, or has never heard of the
pressing, the form underneath still takes everything by hand.

## Local development

```bash
mise install        # Ruby version is pinned in .mise.toml
bundle install
bin/rails db:prepare
bin/dev             # Rails + Tailwind watcher, http://localhost:3000
```

Run the same checks CI runs:

```bash
bin/ci
```

## Design notes

Significant decisions are recorded in [`docs/adr/`](docs/adr/). Read those before assuming a
choice has not already been made and argued about.
