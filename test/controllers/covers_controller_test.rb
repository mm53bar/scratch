require "test_helper"

class CoversControllerTest < ActionDispatch::IntegrationTest
  setup do
    @group = release_groups(:low_tide)
    @group.cover.attach(
      io: Rails.root.join("test/fixtures/files/library/Harbour Lights/1998 - Low Tide/cover.png").open,
      filename: "cover.png", content_type: "image/png"
    )
  end

  test "serves a named variant" do
    get album_cover_path(@group, "thumb")
    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  test "only the named sizes are servable" do
    get album_cover_path(@group, "gigantic")
    assert_response :not_found
  end

  test "an album with no cover is a 404, not an error" do
    get album_cover_path(release_groups(:paper_streets), "thumb")
    assert_response :not_found
  end

  # The URL names one album at one size, so the bytes behind it cannot change.
  test "covers are cacheable forever" do
    get album_cover_path(@group, "thumb")
    cache_control = response.headers["Cache-Control"]
    # About a year — asserted as a range rather than an exact constant, because
    # Rails' 1.year is 365.2425 days and pinning the number tests arithmetic.
    max_age = cache_control[/max-age=(\d+)/, 1].to_i
    assert_operator max_age, :>, 300.days.to_i
    assert_match(/immutable/, cache_control)
    assert_match(/public/, cache_control)
  end

  # Rack::Sendfile rewrites Content-Length to 0 on a GET and lets the proxy
  # restate it. A HEAD has no proxy step to restate anything, so it must answer
  # the length itself.
  test "a HEAD reports the real length rather than zero" do
    head album_cover_path(@group, "thumb")
    assert_response :success
    assert response.headers["Content-Length"].to_i.positive?,
           "HEAD should report the byte size, got #{response.headers["Content-Length"].inspect}"
  end
end
