require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_path
    assert_response :success
    assert_select "h1", "scratch"
  end

  test "reports whether the configured library path is readable" do
    get root_path
    assert_select "dt", text: "Library path"
    assert_select "dt", text: "Readable"
  end
end
