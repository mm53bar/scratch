require "test_helper"

class TrackTest < ActiveSupport::TestCase
  test "a track falls back to the album artist when not separately credited" do
    assert_equal "Harbour Lights", tracks(:low_tide_digital_1).credited_artist
    assert_equal "Quiet Machines & The Ordinary Signals", tracks(:after_hours_cd_2).credited_artist
  end

  test "physical tracks have no file" do
    assert_nil tracks(:low_tide_vinyl_1).filename
    assert_equal "1 - Slack Water.mp3", tracks(:low_tide_digital_1).filename
  end

  test "duration is formatted for display" do
    assert_equal "3:34", tracks(:low_tide_digital_1).duration
    assert_nil tracks(:low_tide_vinyl_1).duration
  end

  test "a position is unique within a disc of a release" do
    dupe = Track.new(release: releases(:low_tide_digital), position: 1, disc: 1, title: "Clash")
    assert_not dupe.valid?
  end
end
