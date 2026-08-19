require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "an empty search invites one rather than listing everything" do
    get search_path
    assert_response :success
    assert_select "p", text: /Start typing to search/
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
    assert_select "p", text: /Nothing found/
  end

  test "wildcards in the query are treated as literal text" do
    get search_path(q: "%")
    assert_response :success
    assert_select "p", text: /Nothing found/
  end

  # Typing submits into a Turbo Frame, so results swap without a full reload.
  test "results live in a turbo frame that the form targets" do
    get search_path(q: "Harbour")
    assert_select "turbo-frame#search_results"
    assert_select "form[data-turbo-frame=?]", "search_results"
    assert_select "input[data-action=?]", "input->debounced-submit#submit"
  end

  # Links inside the frame must break out of it or they would render a whole
  # page into the results panel.
  test "result links target the top level rather than the frame" do
    get search_path(q: "Harbour")
    assert_select "turbo-frame#search_results a[data-turbo-frame=?]", "_top"
  end
end
