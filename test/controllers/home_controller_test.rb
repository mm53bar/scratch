require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "shows collection counts" do
    get root_path
    assert_response :success
    assert_select "h1", "Your collection"
    assert_select "p", text: /\d+ albums/
    assert_select "p", text: /\d+ tracks/
  end

  test "breaks the collection down by medium" do
    get root_path
    assert_select "span", text: "vinyl"
    assert_select "span", text: "cd"
    assert_select "span", text: "digital"
  end

  test "says when the library was last scanned" do
    ScanRun.delete_all
    ScanRun.create!(started_at: 2.hours.ago, status: "completed", finished_at: 2.hours.ago, albums: 5)

    get root_path

    assert_select "p", text: /Library scanned about 2 hours ago/
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
