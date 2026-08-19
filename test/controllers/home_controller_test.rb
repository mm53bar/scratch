require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "shows collection counts" do
    get root_path
    assert_response :success
    assert_select "h1", "Your collection"
    assert_select "dt", text: "Albums"
    assert_select "dt", text: "Tracks"
  end

  test "breaks the collection down by medium" do
    get root_path
    assert_select "span", text: "vinyl"
    assert_select "span", text: "cd"
    assert_select "span", text: "digital"
  end

  # The read-only mount is a design guarantee, so a deployment that loses the
  # :ro flag should be visible on the page rather than merely harmless-looking.
  test "reports whether the library is readable and writable" do
    get root_path
    assert_select "dt", text: "Readable"
    assert_select "dt", text: "Writable"
    assert_select "dd", text: /read-only, as intended/
  end

  test "invites a scan when nothing is catalogued" do
    Track.delete_all
    Release.delete_all
    ReleaseGroup.delete_all
    Artist.delete_all

    get root_path
    # Scanning is a page now, not a shell command someone has to be told.
    assert_select "p a[href=?]", scans_path, text: "Scan the library"
  end
end
