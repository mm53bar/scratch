# Turns the number printed on a record into a list of pressings it might be.
#
# Physical media is the only thing in this collection a library scan cannot
# rebuild, so it is the only thing typed in by hand — and a catalogue number is
# far less to type, and far less to get wrong, than an artist, a title, a year
# and a tracklist.
#
# The number identifies an *edition*, never a copy. Capitol used ST-2576 in
# 1966 and again in 1971 after the label changed. So a lookup narrows the
# possibilities and a person picks; it never decides.
class CatalogueLookup
  Unavailable = Class.new(StandardError)

  # Catalogue data does not change, and the same record gets looked up twice
  # whenever someone is unsure. Long enough to make a second look free, short
  # enough that corrections upstream arrive eventually.
  SEARCH_TTL = 1.week
  RELEASE_TTL = 30.days

  LIMIT = 25

  # The seam. MusicBrainz publishes its database for mirroring, so pointing
  # this somewhere else is a real thing to want; the tests are the second
  # caller rather than the reason it exists.
  class << self
    attr_writer :transport

    def transport = @transport ||= Transport.new
  end

  def initialize(transport: self.class.transport)
    @transport = transport
  end

  # Pressings carrying this catalogue number, best match first.
  #
  # Punctuation and spacing are left alone: MusicBrainz indexes T-2576, T 2576
  # and T2576 identically, so normalising here would only invent differences
  # the search does not have.
  def search(catalogue_number)
    number = catalogue_number.to_s.strip
    return [] if number.blank?

    body = cached("catno/#{number.downcase}", SEARCH_TTL) do
      @transport.get("release", query: %(catno:"#{escape(number)}"), limit: LIMIT, inc: "labels")
    end

    Array(body["releases"]).map { |release| Candidate.from_json(release) }
  end

  # One pressing in full, tracklist included. Called once someone has picked.
  def find(musicbrainz_release_id)
    id = musicbrainz_release_id.to_s
    return nil unless id.match?(/\A[0-9a-f-]{36}\z/i)

    body = cached("release/#{id}", RELEASE_TTL) do
      @transport.get("release/#{id}", inc: "labels+recordings+artist-credits+annotation+url-rels")
    end
    return nil if body.blank?

    Candidate.from_json(body, tracks: tracks_from(body))
  end

  private

  # The number is always wrapped in double quotes, so the only two characters
  # that can end the phrase early and turn the rest into query syntax are the
  # quote and the backslash. Escaping the rest of Lucene's specials would be
  # escaping characters that are already literal inside a phrase.
  def escape(number) = number.gsub(/([\\"])/) { "\\#{Regexp.last_match(1)}" }

  def cached(key, ttl, &)
    Rails.cache.fetch("catalogue_lookup/#{key}", expires_in: ttl, &)
  end

  # A vinyl tracklist is per side, and the sides are the media. Positions are
  # renumbered across the whole release so that side two starts where side one
  # stopped, which is what a tracklist on a sleeve looks like.
  def tracks_from(body)
    Array(body["media"]).flat_map.with_index(1) do |medium, disc|
      Array(medium["tracks"]).map do |track|
        {
          disc: disc,
          position: track["position"].to_i,
          title: track["title"].presence || track.dig("recording", "title"),
          duration_seconds: (track["length"] || track.dig("recording", "length")).to_i / 1000
        }
      end
    end.select { |t| t[:title].present? && t[:position].positive? }
  end
end
