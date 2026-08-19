require "test_helper"

class CatalogueLookupTest < ActiveSupport::TestCase
  test "finds the pressings carrying a catalogue number" do
    candidates = CatalogueLookup.new.search("HL-1042")

    assert_equal 2, candidates.size
    first = candidates.first
    assert_equal "Low Tide", first.title
    assert_equal "Harbour Lights", first.artist_name
    assert_equal 1998, first.year
    assert_equal "GB", first.country
    assert_equal "Tidal Records", first.label
    assert_equal "HL-1042", first.catalogue_number
    assert_equal 10, first.track_count
    assert_equal "mono", first.disambiguation
  end

  test "one number can name pressings that differ in the ways that matter" do
    gb, us = CatalogueLookup.new.search("HL-1042")

    # The whole reason a person has to pick rather than the app deciding.
    assert_not_equal gb.year, us.year
    assert_not_equal gb.country, us.country
    assert_not_equal gb.track_count, us.track_count
  end

  test "the description says what tells two pressings apart" do
    candidate = CatalogueLookup.new.search("HL-1042").first

    assert_equal "1998-03-12 · GB · Tidal Records · 12\" Vinyl · 10 tracks · mono", candidate.description
  end

  test "searches the number as a quoted phrase" do
    transport = FakeCatalogueTransport.new
    CatalogueLookup.new(transport:).search("HL-1042")

    _path, params = transport.calls.sole
    assert_equal %(catno:"HL-1042"), params[:query]
  end

  test "does not ask about a blank number" do
    transport = FakeCatalogueTransport.new

    assert_empty CatalogueLookup.new(transport:).search("  ")
    assert_empty transport.calls
  end

  test "a quote in the number cannot end the phrase early" do
    transport = FakeCatalogueTransport.new
    CatalogueLookup.new(transport:).search('HL" OR title:*')

    _path, params = transport.calls.sole
    assert_equal %(catno:"HL\\" OR title:*"), params[:query]
  end

  test "fetches a tracklist, numbered per side" do
    candidate = CatalogueLookup.new.find("11111111-1111-4111-8111-111111111111")

    assert_equal 4, candidate.tracks.size
    assert_equal [ 1, 1 ], candidate.tracks.first.values_at(:disc, :position)
    assert_equal "Slack Water", candidate.tracks.first[:title]
    assert_equal 214, candidate.tracks.first[:duration_seconds]
    # Side two is a second medium, restarting at position one.
    assert_equal [ 2, 1 ], candidate.tracks.third.values_at(:disc, :position)
    assert_equal "Ebb", candidate.tracks.third[:title]
  end

  test "carries the annotation and the Discogs link" do
    candidate = CatalogueLookup.new.find("11111111-1111-4111-8111-111111111111")

    assert candidate.details?
    assert_match "HL-X-1-1042", candidate.annotation
    assert_equal "https://example.com/release/1042", candidate.discogs_url
  end

  test "a link that is not a web address never reaches an href" do
    # MusicBrainz relations are editable by anyone, and this one is rendered
    # as a link, so the scheme is checked rather than trusted.
    assert_nil CatalogueLookup::Candidate.web_url("javascript:alert(1)")
    assert_nil CatalogueLookup::Candidate.web_url("data:text/html,<script>")
    assert_nil CatalogueLookup::Candidate.web_url("//evil.example.com")
    assert_nil CatalogueLookup::Candidate.web_url("not a url")
    assert_equal "https://example.com/r/1", CatalogueLookup::Candidate.web_url("https://example.com/r/1")
  end

  test "a pressing with nothing further says so rather than looking broken" do
    transport = FakeCatalogueTransport.new(release: "release_bare")
    candidate = CatalogueLookup.new(transport:).find("11111111-1111-4111-8111-111111111111")

    assert_not candidate.details?
    assert_nil candidate.annotation
    assert_nil candidate.discogs_url
  end

  test "refuses anything that is not an identifier without asking" do
    transport = FakeCatalogueTransport.new

    assert_nil CatalogueLookup.new(transport:).find("../../etc/passwd")
    assert_nil CatalogueLookup.new(transport:).find("")
    assert_empty transport.calls
  end

  test "an unreachable MusicBrainz raises rather than returning nothing found" do
    transport = FakeCatalogueTransport.new(raise_with: "rate limited")

    # The difference matters: "not catalogued" and "could not ask" mean
    # opposite things to someone holding a record.
    assert_raises(CatalogueLookup::Unavailable) { CatalogueLookup.new(transport:).search("HL-1042") }
  end

  test "returns nothing found when the number is not catalogued" do
    transport = FakeCatalogueTransport.new(search: "empty")

    assert_empty CatalogueLookup.new(transport:).search("ZZ-0000")
  end

  test "asks once for a number looked up twice" do
    transport = FakeCatalogueTransport.new

    with_cache do
      2.times { CatalogueLookup.new(transport:).search("HL-1042") }
    end

    assert_equal 1, transport.calls.size
  end

  test "the same number in different case is the same question" do
    transport = FakeCatalogueTransport.new

    with_cache do
      CatalogueLookup.new(transport:).search("HL-1042")
      CatalogueLookup.new(transport:).search("hl-1042")
    end

    assert_equal 1, transport.calls.size
  end

  private

  # The test environment caches nothing, which is right everywhere except here:
  # not hammering MusicBrainz is the behaviour under test.
  def with_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
