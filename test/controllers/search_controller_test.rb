require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "an empty search invites one rather than listing everything" do
    get search_path
    assert_response :success
    assert_select "p", text: /Search artists, albums and tracks/
  end

  test "finds albums, artists and tracks" do
    get search_path(q: "Harbour")
    assert_response :success
    assert_select "a", text: "Harbour Lights"
    assert_select "li", text: /Harbour Wall/
  end

  test "reports nothing found rather than an empty page" do
    get search_path(q: "zzzzz")
    assert_response :success
    assert_select "p", text: "Nothing found."
  end

  test "wildcards in the query are treated as literal text" do
    get search_path(q: "%")
    assert_response :success
    assert_select "p", text: "Nothing found."
  end
end
