# Builds the digital half of the catalogue by reading what is on disk.
#
# The tags are the source of truth, not the folder names. That is deliberate:
# a media server groups albums by the `album` and `albumartist` tags, so
# reading the same fields means this catalogue and the player agree about what
# an album is. A folder named differently from its tags is a naming quirk, not
# a different album.
#
# Idempotent. A release is recognised by its path, so rescanning updates in
# place rather than duplicating. Physical releases are never touched — they
# exist only in this database and no scan can know about them.
class LibraryScan
  AUDIO = ".mp3"
  # Only the names bin/tag writes and the players agree on. cover.webp is
  # deliberately absent: Music Assistant ignores it, so if one is the only cover
  # in a folder that folder has a problem worth seeing rather than papering over.
  COVERS = %w[cover.jpg cover.jpeg cover.png].freeze

  Result = Struct.new(:albums, :tracks, :created, :updated, :skipped, keyword_init: true) do
    def to_s
      "#{albums} albums, #{tracks} tracks (#{created} new, #{updated} updated, #{skipped} skipped)"
    end
  end

  def initialize(root: Scratch.library_root, logger: Rails.logger)
    @root = Pathname.new(root)
    @logger = logger
  end

  # Yields (done, total) as it goes, so something can show progress on a job
  # that takes minutes. The scanner does not know or care what is listening;
  # without a block it behaves exactly as it did before.
  def call
    result = Result.new(albums: 0, tracks: 0, created: 0, updated: 0, skipped: [])
    directories = album_directories
    yield(0, directories.size) if block_given?

    directories.each_with_index do |dir, index|
      tracks = read_tracks(dir)
      if tracks.empty?
        result.skipped << relative(dir)
        next
      end

      ActiveRecord::Base.transaction { absorb(dir, tracks, result) }
      result.albums += 1
      result.tracks += tracks.size
    ensure
      # In the ensure so a skipped folder still advances the count — otherwise
      # a library with unreadable folders appears to stall.
      yield(index + 1, directories.size) if block_given?
    end

    @logger.info("LibraryScan: #{result}")
    result
  end

  private

  # Any directory holding audio is an album. Walking for files rather than
  # assuming <artist>/<album> means an unexpected layout is catalogued instead
  # of silently ignored.
  def album_directories
    return [] unless @root.directory?

    @root.glob("**/*#{AUDIO}").map(&:dirname).uniq.sort
  end

  def read_tracks(dir)
    dir.children.select { |f| f.extname.casecmp(AUDIO).zero? }.sort.filter_map do |file|
      tags = read_tags(file)
      next if tags.nil?

      tags.merge(filename: file.basename.to_s, byte_size: file.size)
    end
  end

  def read_tags(file)
    got = nil
    begin
      Mp3Info.open(file.to_s) do |mp3|
        t = mp3.tag2
        got = {
          title: t["TIT2"].presence,
          album: t["TALB"].presence,
          album_artist: t["TPE2"].presence,
          artist_credit: t["TPE1"].presence,
          position: number_from(t["TRCK"]),
          disc: number_from(t["TPOS"]) || 1,
          # ID3v2.3 stores the year in TYER, v2.4 in TDRC, and a library
          # assembled over time contains both. Reading only one silently
          # produces a catalogue where almost nothing has a year.
          year: year_from(t),
          duration_seconds: mp3.length&.round
        }
      end
    rescue Errno::EBADF
      # Reading over a network mount can fail when flushing on close even
      # though the tags were read. Keep what we got; only give up if nothing
      # came back.
      raise if got.nil?
    rescue StandardError => e
      # Log the message, not just the class: a swallowed NameError from an
      # unloaded gem looks exactly like an unreadable file otherwise.
      @logger.warn("LibraryScan: cannot read #{file}: #{e.class}: #{e.message}")
      return nil
    end
    got
  end

  # TDRC may be a full date ("1998-06-17"); we only want the year.
  def year_from(tag)
    raw = tag["TYER"].presence || tag["TDRC"].presence || tag["TDAT"].presence
    raw.to_s[/\d{4}/]&.to_i
  end

  # "3/12" and "3" both mean track three.
  def number_from(value) = value.to_s[/\d+/]&.to_i

  def absorb(dir, tracks, result)
    album_title = majority(tracks, :album) || dir.basename.to_s.sub(/\A\d{4}\s*-\s*/, "")
    artist_name = majority(tracks, :album_artist) || dir.parent.basename.to_s
    year = majority(tracks, :year)

    artist = Artist.find_or_create_by!(name: artist_name)
    group = ReleaseGroup.find_or_create_by!(artist:, title: album_title)
    group.update!(year:) if year && group.year != year

    release = Release.find_or_initialize_by(path: relative(dir))
    new_record = release.new_record?
    release.assign_attributes(release_group: group, medium: "digital", year:)
    release.save!
    new_record ? result.created += 1 : result.updated += 1

    attach_cover(group, dir)

    replace_tracks(release, tracks, artist_name)
  end

  # Tracks are replaced wholesale rather than merged. A rescan is cheap, and
  # reconciling "this file used to be track 4 and is now track 5" is exactly the
  # kind of guessing this app avoids elsewhere.
  def replace_tracks(release, tracks, album_artist)
    release.tracks.delete_all
    rows = tracks.each_with_index.map do |t, i|
      credit = t[:artist_credit]
      {
        release_id: release.id,
        position: t[:position] || i + 1,
        disc: t[:disc],
        title: t[:title].presence || File.basename(t[:filename], ".*"),
        artist_credit: (credit if credit && credit != album_artist),
        duration_seconds: t[:duration_seconds],
        filename: t[:filename],
        file_format: "mp3",
        byte_size: t[:byte_size],
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    # Two files claiming the same disc and position would violate the unique
    # index. That is a real fault in the files, not something to paper over, so
    # keep the first and let the rest surface as a gap in the numbering.
    Track.insert_all!(rows.uniq { |r| [ r[:disc], r[:position] ] })
  end

  # Copied in rather than read from the library on each request: the library is
  # read-only and may not be mounted, and variants must be written somewhere
  # regardless. Re-attached only when the file actually differs, so a rescan of
  # an unchanged library does no image work at all.
  def attach_cover(group, dir)
    file = COVERS.filter_map { |name| dir.join(name) }.find(&:exist?)
    return if file.nil?

    return if group.cover.attached? && group.cover.blob.byte_size == file.size

    group.cover.attach(io: file.open, filename: file.basename.to_s,
                       content_type: Marcel::MimeType.for(file))
  rescue StandardError => e
    @logger.warn("LibraryScan: cover failed for #{dir}: #{e.class}: #{e.message}")
  end

  def majority(tracks, key)
    values = tracks.filter_map { |t| t[key] }
    return nil if values.empty?

    values.tally.max_by { |_, count| count }.first
  end

  def relative(dir) = dir.relative_path_from(@root).to_s
end
