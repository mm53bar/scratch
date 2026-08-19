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

  test "suggestions are returned as JSON for the autocomplete component" do
    get search_suggestions_path(q: "Harbour"), as: :json
    assert_response :success
    body = JSON.parse(response.body)
    titles = body["suggestions"].map { |s| s["title"] }
    assert_includes titles, "Harbour Lights"
    assert_includes titles, "Harbour Wall"
  end

  test "each suggestion carries a url to navigate to" do
    get search_suggestions_path(q: "Low Tide"), as: :json
    suggestion = JSON.parse(response.body)["suggestions"].first
    assert_equal album_path(release_groups(:low_tide)), suggestion["url"]
    assert suggestion["subtitle"].present?
  end

  # A single character would match most of the collection and cost a query per
  # keystroke for no useful result.
  test "very short queries return nothing" do
    get search_suggestions_path(q: "a"), as: :json
    assert_equal [], JSON.parse(response.body)["suggestions"]
  end

  test "suggestion queries escape LIKE wildcards too" do
    get search_suggestions_path(q: "%%"), as: :json
    assert_equal [], JSON.parse(response.body)["suggestions"]
  end

  test "the search box in the nav is the autocomplete component" do
    get root_path
    assert_select "[data-controller~=?]", "autocomplete"
    assert_select "[data-autocomplete-url-value=?]", search_suggestions_path
  end

  # The component imports @floating-ui/dom. Without the pin the controller
  # never loads and the search box silently does nothing, which is exactly how
  # it shipped the first time.
  test "the autocomplete javascript dependency is pinned" do
    importmap = Rails.root.join("config/importmap.rb").read
    assert_match(/@floating-ui\/dom/, importmap)
    assert Rails.root.join("vendor/javascript/floating-ui--dom.js").exist?,
           "the dependency should be vendored, not fetched from a CDN at runtime"
  end

  # Without .form-control the inputs fall back to browser defaults — wrong font
  # size, misaligned icon.
  test "the base component css is compiled" do
    css = Rails.root.join("app/assets/builds/tailwind.css").read
    assert_includes css, ".form-control"
  end
end
