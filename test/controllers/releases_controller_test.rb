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

  # --- Adding a record by its catalogue number -------------------------------

  test "the new form offers a lookup before asking anyone to type" do
    get new_release_path

    assert_response :success
    assert_select "form[action=?]", catalogue_lookup_path
    assert_select "turbo-frame#catalogue_results"
  end

  test "picking a pressing prefills the form" do
    get new_release_path(mbid: "11111111-1111-4111-8111-111111111111")

    assert_response :success
    assert_select "input[name=?][value=?]", "release[catalogue_number]", "HL-1042"
    assert_select "input[name=?][value=?]", "release[country]", "GB"
    assert_select "input[name=?][value=?]", "release[year]", "1998"
    assert_select "input[name=?][value=?]", "release[artist_name]", "Harbour Lights"
    assert_select "input[name=?][value=?]", "release[album_title]", "Low Tide"
    assert_select "input[name=?][value=?]", "release[musicbrainz_release_id]",
                  "11111111-1111-4111-8111-111111111111"
  end

  test "a prefilled form saves nothing on its own" do
    assert_no_difference [ "Release.count", "Artist.count" ] do
      get new_release_path(mbid: "11111111-1111-4111-8111-111111111111")
    end
  end

  test "a lookup that fails still gives a usable form" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(raise_with: "rate limited")

    get new_release_path(mbid: "11111111-1111-4111-8111-111111111111")

    assert_response :success
    assert_select "input[name=?]", "release[artist_name]"
    assert_match "fill this in by hand", response.body
  end

  test "saving an identified pressing brings its tracklist with it" do
    assert_difference "Release.count", 1 do
      post releases_path, params: { release: {
        medium: "vinyl", artist_name: "Harbour Lights", album_title: "Low Tide",
        year: 1998, catalogue_number: "HL-1042", country: "GB",
        musicbrainz_release_id: "11111111-1111-4111-8111-111111111111"
      } }
    end

    release = Release.order(:created_at).last
    assert_equal "HL-1042", release.catalogue_number
    assert_equal "GB", release.country
    assert release.identified?

    # The tracklist is the point: it is what makes one pressing of an album
    # distinguishable from another in the collection.
    assert_equal 4, release.tracks.count
    assert_equal [ "Slack Water", "Harbour Wall", "Ebb", "Spring Tide" ], release.tracks.in_order.pluck(:title)
    assert_equal [ 1, 1, 2, 2 ], release.tracks.in_order.pluck(:disc)
    assert_equal 214, release.tracks.in_order.first.duration_seconds
  end

  test "a tracklist that cannot be fetched does not cost someone the entry" do
    CatalogueLookup.transport = FakeCatalogueTransport.new(raise_with: "rate limited")

    assert_difference "Release.count", 1 do
      post releases_path, params: { release: {
        medium: "vinyl", artist_name: "Harbour Lights", album_title: "Low Tide",
        musicbrainz_release_id: "11111111-1111-4111-8111-111111111111"
      } }
    end

    assert_equal 0, Release.order(:created_at).last.tracks.count
    follow_redirect!
    assert_match "tracklist could not be fetched", response.body
  end

  test "typing it all in by hand still works" do
    assert_difference "Release.count", 1 do
      post releases_path, params: { release: {
        medium: "cd", artist_name: "The Ordinary Signals", album_title: "Paper Streets", year: 2004
      } }
    end

    release = Release.order(:created_at).last
    assert_nil release.catalogue_number
    assert_not release.identified?
  end

  test "the same pressing cannot be shelved twice" do
    2.times do
      post releases_path, params: { release: {
        medium: "vinyl", artist_name: "Harbour Lights", album_title: "Low Tide",
        musicbrainz_release_id: "11111111-1111-4111-8111-111111111111"
      } }
    end

    assert_response :unprocessable_entity
    assert_equal 1, Release.where(musicbrainz_release_id: "11111111-1111-4111-8111-111111111111").count
  end
end
