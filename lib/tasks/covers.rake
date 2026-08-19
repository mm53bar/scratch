namespace :covers do
  desc "Generate any missing cover variants (run after adding a new variant)"
  task variants: :environment do
    # preprocessed: true only fires when a cover is attached, so covers that
    # were already attached when a variant was added have never been built.
    # Left to generate on demand they are slow enough to occupy a web thread —
    # a cold variant on a network mount has been measured in the tens of
    # seconds — so they get built deliberately instead.
    groups = ReleaseGroup.joins(:cover_attachment).includes(cover_attachment: :blob)
    total = groups.count
    built = 0

    groups.find_each.with_index(1) do |group, index|
      ReleaseGroup::COVER_VARIANTS.each do |variant|
        # Symbol, not String: named variants are keyed by symbol, and a string
        # falls through to being read as a transformation hash.
        # .processed is idempotent — it returns an existing variant untouched —
        # so there is nothing to check first.
        group.cover.variant(variant.to_sym).processed
        built += 1
      rescue StandardError => e
        # One unreadable cover should not stop the other hundred and sixty.
        warn "\n  #{group.artist.name} — #{group.title}: #{e.class}: #{e.message}"
      end
      print "\r  #{index}/#{total} albums, #{built} variants built" if (index % 5).zero?
    end

    puts "\r  #{total} albums, #{built} variants built#{' ' * 20}"
  end
end
