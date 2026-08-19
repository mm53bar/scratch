require "test_helper"

class ReleaseGroupTest < ActiveSupport::TestCase
  test "a group knows which media it is owned on" do
    assert_equal %w[digital vinyl], release_groups(:low_tide).media
    assert release_groups(:low_tide).owned_on?("vinyl")
    assert_not release_groups(:paper_streets).owned_on?("vinyl")
  end

  test "on_medium finds groups owned on that medium" do
    on_vinyl = ReleaseGroup.on_medium("vinyl")
    assert_includes on_vinyl, release_groups(:low_tide)
    assert_includes on_vinyl, release_groups(:signal_fires)
    assert_not_includes on_vinyl, release_groups(:paper_streets)
  end

  test "not_on_medium finds groups missing from that medium" do
    missing_vinyl = ReleaseGroup.not_on_medium("vinyl")
    assert_includes missing_vinyl, release_groups(:paper_streets)
    assert_includes missing_vinyl, release_groups(:after_hours)
    assert_not_includes missing_vinyl, release_groups(:low_tide)
  end

  # The question the app exists to answer.
  test "owned digitally but not on vinyl" do
    gap = ReleaseGroup.on_medium("digital").not_on_medium("vinyl")
    assert_equal [ release_groups(:paper_streets) ], gap.to_a
  end

  test "owned on vinyl but not digitally" do
    gap = ReleaseGroup.on_medium("vinyl").not_on_medium("digital")
    assert_equal [ release_groups(:signal_fires) ], gap.to_a
  end

  # Combining the two scopes must not multiply rows, which a join would.
  test "combined scopes return each group once" do
    ids = ReleaseGroup.on_medium("digital").not_on_medium("vinyl").pluck(:id)
    assert_equal ids.uniq, ids
  end

  test "a title is unique within an artist but not across artists" do
    dupe = ReleaseGroup.new(artist: artists(:harbour_lights), title: "Low Tide")
    assert_not dupe.valid?

    elsewhere = ReleaseGroup.new(artist: artists(:quiet_machines), title: "Low Tide")
    assert elsewhere.valid?
  end
end
