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
end
