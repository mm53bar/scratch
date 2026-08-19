require "test_helper"

class ReleaseGroupsControllerTest < ActionDispatch::IntegrationTest
  test "lists every album" do
    get albums_path
    assert_response :success
    assert_select "a[href=?] p", album_path(release_groups(:low_tide)), text: "Low Tide"
    assert_select "a[href=?] p", album_path(release_groups(:signal_fires)), text: "Signal Fires"
  end

  test "filters by medium" do
    get albums_path(medium: "vinyl")
    assert_response :success
    assert_select "a[href=?] p", album_path(release_groups(:signal_fires)), text: "Signal Fires"
    assert_select "a[href=?]", album_path(release_groups(:paper_streets)), count: 0
  end

  test "an unknown medium is ignored rather than filtering everything away" do
    get albums_path(medium: "cassette")
    assert_response :success
    assert_select "a[href=?] p", album_path(release_groups(:paper_streets)), text: "Paper Streets"
  end

  test "an album page shows each release it is owned on, with its own tracks" do
    get album_path(release_groups(:low_tide))
    assert_response :success
    assert_select "h1", "Low Tide"
    # The vinyl has one track and the digital rip two; both are shown.
    assert_select "li", text: /Slack Water/
    assert_select "li", text: /Harbour Wall/
  end

  test "a release with no track listing says so" do
    get album_path(release_groups(:signal_fires))
    assert_response :success
    assert_select "p", text: /catalogued by hand/
  end

  test "an album with no cover shows its title rather than an empty square" do
    group = release_groups(:paper_streets)
    assert_not group.cover.attached?

    get albums_path

    # Physical-only albums are never scanned, so they have no cover at all.
    # A hole in the grid reads as a broken image.
    assert_select "a[href=?] div span", album_path(group), text: group.title
  end

  test "a card says which media the album is owned on" do
    get albums_path

    # The whole point of the app is uniting formats, so the card has to carry
    # that rather than making someone open the album to find out.
    assert_select "a[href=?]", album_path(release_groups(:low_tide)) do
      assert_select "span", text: "digital"
    end
  end
end
