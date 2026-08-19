require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  test "releases of one album may have different track counts" do
    vinyl = releases(:low_tide_vinyl)
    digital = releases(:low_tide_digital)

    assert_equal vinyl.release_group, digital.release_group
    assert_equal 1, vinyl.tracks.count
    assert_equal 2, digital.tracks.count
  end

  test "medium is restricted to the formats we catalogue" do
    release = releases(:low_tide_vinyl)
    release.medium = "cassette"
    assert_not release.valid?
    assert_includes release.errors[:medium], "is not included in the list"
  end

  test "only digital releases may carry a path" do
    vinyl = releases(:low_tide_vinyl)
    vinyl.path = "somewhere/on/disk"
    assert_not vinyl.valid?
    assert_includes vinyl.errors[:path], "is only meaningful for digital releases"
  end

  test "display_title includes the edition only when there is one" do
    assert_equal "After Hours (Deluxe Edition)", releases(:after_hours_cd).display_title
    assert_equal "Low Tide", releases(:low_tide_vinyl).display_title
  end

  test "a digital path is unique across the library" do
    dupe = Release.new(release_group: release_groups(:paper_streets), medium: "digital",
                       path: releases(:low_tide_digital).path)
    assert_not dupe.valid?
  end
end
