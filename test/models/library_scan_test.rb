require "test_helper"
require "tmpdir"

class LibraryScanTest < ActiveSupport::TestCase
  # A tiny synthetic library lives in test/fixtures/files/library: three
  # one-second silent MP3s, tagged by hand. Nothing real, so this repository
  # can stay public.
  LIBRARY = Rails.root.join("test/fixtures/files/library")

  setup do
    Track.delete_all
    Release.delete_all
    ReleaseGroup.delete_all
    Artist.delete_all
  end

  def scan(root: LIBRARY) = LibraryScan.new(root:, logger: Logger.new(File::NULL)).call

  test "builds artists, groups, releases and tracks from what is on disk" do
    result = scan

    assert_equal 2, result.albums
    assert_equal 3, result.tracks
    assert_equal 2, Artist.count
    assert_equal 2, ReleaseGroup.count
    assert_equal 2, Release.count
    assert_equal 3, Track.count
  end

  test "reads the album and artist from tags rather than folder names" do
    scan
    group = ReleaseGroup.find_by!(title: "Low Tide")

    assert_equal "Harbour Lights", group.artist.name
    assert_equal 1998, group.year
  end

  test "everything it finds on disk is a digital release" do
    scan
    assert_equal [ "digital" ], Release.distinct.pluck(:medium)
  end

  test "records the folder as a path relative to the library root" do
    scan
    assert_equal "Harbour Lights/1998 - Low Tide",
                 Release.find_by!(path: "Harbour Lights/1998 - Low Tide").path
  end

  test "tracks keep their numbering and file details" do
    scan
    tracks = ReleaseGroup.find_by!(title: "Low Tide").releases.sole.tracks.in_order

    assert_equal [ 1, 2 ], tracks.map(&:position)
    assert_equal [ "Slack Water", "Harbour Wall" ], tracks.map(&:title)
    assert_equal [ "mp3", "mp3" ], tracks.map(&:file_format)
    assert tracks.all? { |t| t.byte_size.to_i.positive? }
  end

  test "a track artist is stored only when it differs from the album artist" do
    scan
    assert_nil Track.find_by!(title: "Slack Water").artist_credit
    assert_equal "Quiet Machines & Guest", Track.find_by!(title: "Nightporter").artist_credit
  end

  test "rescanning updates in place rather than duplicating" do
    scan
    first = scan

    assert_equal 0, first.created
    assert_equal 2, first.updated
    assert_equal 2, Release.count
    assert_equal 3, Track.count
  end

  test "a missing library is reported rather than raising" do
    result = scan(root: Rails.root.join("test/fixtures/files/nonexistent"))
    assert_equal 0, result.albums
  end

  test "physical releases are untouched by a scan" do
    artist = Artist.create!(name: "Shelf Only")
    group = ReleaseGroup.create!(artist:, title: "On Vinyl")
    vinyl = Release.create!(release_group: group, medium: "vinyl")

    scan

    assert Release.exists?(vinyl.id), "a scan must not delete physical releases"
    assert_equal "vinyl", vinyl.reload.medium
  end

  # A library assembled over years contains both ID3 versions. Reading only
  # TYER produced a catalogue where 162 of 167 albums had no year at all.
  test "reads the year from v2.4 TDRC as well as v2.3 TYER" do
    Dir.mktmpdir do |tmp|
      album = File.join(tmp, "Quiet Machines", "2011 - After Hours")
      FileUtils.mkdir_p(album)
      src = LIBRARY.join("Quiet Machines/2011 - After Hours/1 - Nightporter.mp3")
      FileUtils.cp(src, File.join(album, "1 - Nightporter.mp3"))

      Mp3Info.open(File.join(album, "1 - Nightporter.mp3")) do |mp3|
        mp3.tag2.delete("TYER")
        mp3.tag2["TDRC"] = "2011-09-04"
      end

      LibraryScan.new(root: tmp, logger: Logger.new(File::NULL)).call
      assert_equal 2011, ReleaseGroup.find_by!(title: "After Hours").year
    end
  end

  test "attaches the cover found in the album folder" do
    scan
    group = ReleaseGroup.find_by!(title: "Low Tide")
    assert group.cover.attached?
    assert_equal "cover.png", group.cover.filename.to_s
  end

  test "an album with no cover file simply has none" do
    scan
    assert_not ReleaseGroup.find_by!(title: "After Hours").cover.attached?
  end

  # Re-reading and re-processing 167 covers on every scan would make a rescan of
  # an unchanged library far more expensive than it needs to be.
  test "rescanning does not re-attach an unchanged cover" do
    scan
    group = ReleaseGroup.find_by!(title: "Low Tide")
    blob_id = group.cover.blob.id

    scan
    assert_equal blob_id, group.reload.cover.blob.id
  end
end
