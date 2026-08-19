require "test_helper"

class ReleaseGroupsControllerTest < ActionDispatch::IntegrationTest
  test "lists every album" do
    get albums_path
    assert_response :success
    assert_select "a", text: "Low Tide"
    assert_select "a", text: "Signal Fires"
  end

  test "filters by medium" do
    get albums_path(medium: "vinyl")
    assert_response :success
    assert_select "a", text: "Signal Fires"
    assert_select "a", text: "Paper Streets", count: 0
  end

  test "an unknown medium is ignored rather than filtering everything away" do
    get albums_path(medium: "cassette")
    assert_response :success
    assert_select "a", text: "Paper Streets"
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
end
