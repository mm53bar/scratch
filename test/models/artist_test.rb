require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  test "a leading article moves to the end for sorting" do
    artist = Artist.new(name: "The Ordinary Signals")
    artist.valid?
    assert_equal "Ordinary Signals, The", artist.sort_name
  end

  test "names without a leading article are left alone" do
    artist = Artist.new(name: "Quiet Machines")
    artist.valid?
    assert_equal "Quiet Machines", artist.sort_name
  end

  test "an article inside the name is not moved" do
    artist = Artist.new(name: "Songs of the Sea")
    artist.valid?
    assert_equal "Songs of the Sea", artist.sort_name
  end

  test "an explicit sort name is not overwritten" do
    artist = Artist.new(name: "The Ordinary Signals", sort_name: "Deliberate Choice")
    artist.valid?
    assert_equal "Deliberate Choice", artist.sort_name
  end
end
