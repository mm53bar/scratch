require "test_helper"

class ArtistsControllerTest < ActionDispatch::IntegrationTest
  test "lists artists alphabetically by sort name" do
    get artists_path
    assert_response :success
    names = css_select("li a").map(&:text)
    assert_includes names, "Harbour Lights"
    # "The Ordinary Signals" sorts under O, so it follows Harbour Lights.
    assert names.index("Harbour Lights") < names.index("The Ordinary Signals")
  end

  test "an artist page lists their albums with the media owned" do
    get artist_path(artists(:harbour_lights))
    assert_response :success
    assert_select "h1", "Harbour Lights"
    assert_select "a", text: "Low Tide"
    assert_select "span", text: "vinyl"
    assert_select "span", text: "digital"
  end
end
