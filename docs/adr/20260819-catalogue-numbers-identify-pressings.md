# 20260819 — Catalogue numbers identify pressings; a person confirms

## Context

Physical media is the only thing in this inventory a library scan cannot rebuild. A record leaves
no file behind, so every field has to be typed — artist, title, year, edition, and a tracklist that
may differ from the digital copy of the same album.

Every record and CD carries a catalogue number on its label and usually its spine: `T-2576`,
`PMC 7009`, `CDP 7 46441 2`. For anything pressed before barcodes it is the *only* machine-usable
identifier on the object. Barcodes were the obvious thing to reach for — point a phone at the back
of the sleeve — but they exclude exactly the part of a collection most worth cataloguing carefully.

MusicBrainz indexes catalogue numbers, serves them without an API key, and its search normalises
punctuation and spacing, so `T-2576`, `T 2576` and `T2576` are one query.

## Decision

**A catalogue number is the way in, and the lookup proposes rather than decides.**

`catalogue_number`, `country` and `musicbrainz_release_id` are columns on `releases`. Entering a
number lists the pressings it could name; picking one prefills the form, tracklist included; saving
is a separate, deliberate act.

The lookup is never load-bearing. Every field it fills can be typed instead, and the form works
unchanged when MusicBrainz is unreachable, rate limiting, or has never heard of the pressing.

## Consequences

- **The number names an edition, not a copy.** Capitol issued `ST-2576` in 1966 and again in 1971
  after the label changed; `T 2576` covers both a US and a Canadian pressing. So a lookup that
  returns four results is correct behaviour, not ambiguity to resolve automatically. The candidate
  list leads with date, country, label, format, track count and MusicBrainz's disambiguation —
  "mono, Abbey Record pressing" — because those are what a person compares against the label.
- **A catalogue number does not date a copy.** It cannot; it outlives the pressing run. Dating a
  specific disc means reading the label design and the runout, which is knowledge in someone's
  hands, not in a database. The `year` from a lookup is the edition's, and is editable.
- **Tracklists come across, which is the point.** A US *Revolver* has eleven tracks where the UK
  original has fourteen — the same release group, genuinely different releases. That distinction is
  what `20260819-release-groups-join-formats.md` exists to hold, and until now nothing populated
  it for physical media.
- **`musicbrainz_release_id` is unique**, so the same pressing cannot be shelved twice. Two copies
  of the same pressing are a quantity, not two rows; if that ever needs representing, it needs a
  column, not a duplicate.
- Lookups are cached (a week for searches, thirty days for releases). Repeat lookups of the same
  number cost nothing, which matters because being unsure is the normal reason to look twice.
- MusicBrainz returned `503` at one request every 1.1 seconds — inside its published limit — so
  rate limiting is a routine event and the transport retries it. Non-retryable replies are not
  retried, because a malformed query is malformed the second time too.

## Alternatives considered

- **Barcode scanning by camera.** Still worth having, and complementary. Rejected as the primary
  route because pre-1980s pressings have no barcode, and they are the ones where a catalogue number
  is doing real work.
- **Matching automatically on the best-scoring result.** Rejected. The results differ in track
  count and territory; picking for someone would silently record the wrong edition, and the wrong
  edition is worse than no edition because it looks like an answer.
- **Storing the full MusicBrainz response.** Rejected as an inventory of what someone owns, not a
  mirror of a database. The release id is kept so the question can be asked again.
- **Discogs**, which catalogues pressings in more depth. Rejected for now: it requires a token, and
  a token is configuration this otherwise does not need.
