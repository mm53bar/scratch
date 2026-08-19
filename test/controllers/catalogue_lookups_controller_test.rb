require "test_helper"

class CatalogueLookupsControllerTest < ActionDispatch::IntegrationTest
  test "lists the pressings carrying a number" do
    get catalogue_lookup_path(catalogue_number: "HL-1042")

    assert_response :success
    assert_select "turbo-frame#catalogue_results"
    assert_select "li", 2
    assert_match "Low Tide", response.body
    assert_match "Tidal Records", response.body
  end

  test "each pressing links to a prefilled form rather than saving anything" do
    assert_no_difference [ "Release.count", "ReleaseGroup.count", "Artist.count" ] do
      get catalogue_lookup_path(catalogue_number: "HL-1042")
    end

    assert_select "a[href=?]", new_release_path(mbid: "11111111-1111-4111-8111-111111111111", medium: "vinyl")
  end

  test "carries the medium through so a CD lookup does not return a record" do
    get catalogue_lookup_path(catalogue_number: "HL-1042", medium: "cd")

    assert_select "a[href*=?]", "medium=cd"
  end

  test "an uncatalogued number says so without implying an error" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(search: "empty")

    get catalogue_lookup_path(catalogue_number: "ZZ-0000")

    assert_response :success
    assert_match "Nothing found", response.body
    assert_match "fill the form in by hand", response.body
  end

  test "an unreachable MusicBrainz is a note on the page, not an error page" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(raise_with: "rate limited")

    get catalogue_lookup_path(catalogue_number: "HL-1042")

    # The form underneath still works, so this must not take the page down.
    assert_response :success
    assert_match "Could not reach MusicBrainz", response.body
  end

  test "asks nothing when nothing was typed" do
    transport = FakeCatalogueTransport.new
    CatalogueLookup.transport = transport

    get catalogue_lookup_path

    assert_response :success
    assert_empty transport.calls
  end

  # --- Telling two pressings of one number apart -----------------------------

  test "details are not fetched with the list" do
    transport = FakeCatalogueTransport.new
    CatalogueLookup.transport = transport

    get catalogue_lookup_path(catalogue_number: "HL-1042")

    # Two candidates would be two more requests to a rate-limited service, for
    # information only wanted when two of them look alike.
    assert_equal 1, transport.calls.size
    assert_select "turbo-frame#pressing_11111111-1111-4111-8111-111111111111 a", "Pressing details"
  end

  test "details quote the runout stamps, which is what is readable on the record" do
    get catalogue_pressing_path("11111111-1111-4111-8111-111111111111")

    assert_response :success
    assert_select "turbo-frame#pressing_11111111-1111-4111-8111-111111111111"
    assert_match "Matrix / Runout (Label A): HL-X-1-1042", response.body
    assert_select "a[href=?]", "https://example.com/release/1042"
  end

  test "details open in a new tab without handing the referrer over" do
    get catalogue_pressing_path("11111111-1111-4111-8111-111111111111")

    assert_select "a[rel=?]", "noopener noreferrer"
  end

  test "says so plainly when there is nothing further" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(release: "release_bare")

    get catalogue_pressing_path("11111111-1111-4111-8111-111111111111")

    assert_response :success
    assert_match "nothing further", response.body
  end

  test "unreachable details do not take the list down with them" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(raise_with: "rate limited")

    get catalogue_pressing_path("11111111-1111-4111-8111-111111111111")

    assert_response :success
    assert_match "Could not fetch details", response.body
  end

  test "opening details pays for picking the pressing" do
    transport = FakeCatalogueTransport.new
    CatalogueLookup.transport = transport

    with_cache do
      get catalogue_pressing_path("11111111-1111-4111-8111-111111111111")
      get new_release_path(mbid: "11111111-1111-4111-8111-111111111111")
    end

    # Same fetch behind both, so looking before choosing costs nothing extra.
    assert_equal 1, transport.calls.size
    assert_select "input[name=?][value=?]", "release[catalogue_number]", "HL-1042"
  end

  private

  def with_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
