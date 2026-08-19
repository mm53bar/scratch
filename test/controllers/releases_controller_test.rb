require "test_helper"

class ReleasesControllerTest < ActionDispatch::IntegrationTest
  test "adding a record creates the artist and album when they are new" do
    assert_difference [ "Release.count", "ReleaseGroup.count", "Artist.count" ], 1 do
      post releases_path, params: { release: {
        medium: "vinyl", artist_name: "New Name", album_title: "First Pressing", year: 1985
      } }
    end
    assert_redirected_to album_path(ReleaseGroup.find_by!(title: "First Pressing"))
  end

  test "adding a record to an album already owned joins it rather than duplicating" do
    group = release_groups(:paper_streets)

    assert_difference "Release.count", 1 do
      assert_no_difference "ReleaseGroup.count" do
        post releases_path, params: { release: { medium: "vinyl", release_group_id: group.id } }
      end
    end
    assert_equal %w[digital vinyl], group.reload.media
  end

  test "an existing artist is reused rather than duplicated" do
    assert_no_difference "Artist.count" do
      post releases_path, params: { release: {
        medium: "cd", artist_name: artists(:harbour_lights).name, album_title: "Something New"
      } }
    end
  end

  test "a record needs an artist and an album" do
    assert_no_difference "Release.count" do
      post releases_path, params: { release: { medium: "vinyl", artist_name: "", album_title: "" } }
    end
    assert_response :unprocessable_entity
  end

  # The files are the source of truth for digital releases and this app cannot
  # write to them, so an edit form would promise something it cannot deliver.
  test "digital releases cannot be edited" do
    get edit_release_path(releases(:low_tide_digital))
    assert_redirected_to album_path(release_groups(:low_tide))
    assert_match(/not edited here/, flash[:alert])
  end

  test "digital releases cannot be deleted" do
    assert_no_difference "Release.count" do
      delete release_path(releases(:low_tide_digital))
    end
  end

  test "a physical release can be edited" do
    patch release_path(releases(:low_tide_vinyl)), params: { release: { edition: "First Pressing" } }
    assert_equal "First Pressing", releases(:low_tide_vinyl).reload.edition
  end

  test "the medium of an existing release cannot be switched" do
    patch release_path(releases(:low_tide_vinyl)), params: { release: { medium: "cd" } }
    assert_equal "vinyl", releases(:low_tide_vinyl).reload.medium
  end

  test "removing the last release removes the album entry too" do
    group = release_groups(:signal_fires)
    assert_difference "ReleaseGroup.count", -1 do
      delete release_path(releases(:signal_fires_vinyl))
    end
    assert_not ReleaseGroup.exists?(group.id)
  end

  test "removing one of several releases keeps the album" do
    assert_no_difference "ReleaseGroup.count" do
      delete release_path(releases(:low_tide_vinyl))
    end
    assert ReleaseGroup.exists?(release_groups(:low_tide).id)
  end
end
