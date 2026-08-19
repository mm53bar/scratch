require "test_helper"

class ShelfControllerTest < ActionDispatch::IntegrationTest
  test "lists what is owned physically" do
    get shelf_path
    assert_response :success
    assert_select "a", text: "Low Tide"
    assert_select "a", text: "Signal Fires"
    # Paper Streets is digital only, so it is not on the shelf list itself.
    assert_select "h1", "Your shelf"
  end

  test "shows what is on vinyl but not digitally" do
    get shelf_path
    assert_select "h2", text: /On vinyl, not digitally/
    assert_select "li", text: /Signal Fires/
  end

  test "shows what is digital only" do
    get shelf_path
    assert_select "h2", text: /Digital only/
    assert_select "li", text: /Paper Streets/
  end

  test "an empty shelf explains why it is empty" do
    Release.physical.destroy_all
    get shelf_path
    assert_select "p", text: /leaves no file behind/
  end
end
