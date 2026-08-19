class CatalogueLookup
  # One pressing that might be the record in your hands.
  #
  # Deliberately not an ActiveRecord object: nothing is saved until a person
  # looks at the list and says which one it is. Half these fields exist only to
  # help tell four pressings of the same album apart.
  Candidate = Data.define(
    :musicbrainz_release_id, :title, :artist_name, :year, :date, :country,
    :label, :catalogue_number, :format, :track_count, :disambiguation, :tracks
  ) do
    def self.from_json(release, tracks: [])
      label_info = Array(release["label-info"]).first || {}
      media = Array(release["media"])
      date = release["date"].to_s

      new(
        musicbrainz_release_id: release["id"],
        title: release["title"],
        artist_name: artist_credit(release),
        year: date[0, 4].presence&.to_i,
        date: date.presence,
        country: release["country"],
        label: label_info.dig("label", "name"),
        catalogue_number: label_info["catalog-number"],
        format: media.first&.dig("format"),
        track_count: media.sum { |m| m["track-count"].to_i },
        disambiguation: release["disambiguation"].presence,
        tracks: tracks
      )
    end

    # "The Beatles" is one credit; "Artist X feat. Artist Y" is three joined by
    # phrases MusicBrainz keeps as separate fields.
    def self.artist_credit(release)
      Array(release["artist-credit"]).map do |credit|
        "#{credit.dig('artist', 'name') || credit['name']}#{credit['joinphrase']}"
      end.join.presence
    end

    # Everything that distinguishes this pressing from the one above it in the
    # list, in the order a person reads it.
    def description
      [ date, country, label, format, ("#{track_count} tracks" if track_count.positive?), disambiguation ]
        .compact_blank.join(" · ")
    end

    def to_release_attributes
      { catalogue_number:, country:, year:, musicbrainz_release_id: }
    end
  end
end
