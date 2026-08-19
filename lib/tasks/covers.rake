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
        next if group.cover.variant(variant).send(:processed?)

        group.cover.variant(variant).processed
        built += 1
      end
      print "\r  #{index}/#{total} albums, #{built} variants built" if (index % 5).zero?
    end

    puts "\r  #{total} albums, #{built} variants built#{' ' * 20}"
  end
end
