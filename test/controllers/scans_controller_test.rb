require "test_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  setup { ScanRun.delete_all }

  test "offers a scan when none is running" do
    get scans_path

    assert_response :success
    assert_select "form[action=?]", scans_path
    assert_select "button[type=submit][disabled]", false
  end

  test "starting a scan enqueues it rather than running it in the request" do
    assert_enqueued_with(job: LibraryScanJob) do
      assert_difference "ScanRun.count", 1 do
        post scans_path
      end
    end

    assert_redirected_to scans_path
    assert ScanRun.current.present?
  end

  test "a second press while one is running does not start another" do
    post scans_path

    assert_no_difference "ScanRun.count" do
      post scans_path
    end

    assert_redirected_to scans_path
    follow_redirect!
    assert_match "already running", response.body
  end

  test "the button is disabled while a scan runs" do
    ScanRun.create!(started_at: Time.current)

    get scans_path

    assert_select "button[type=submit][disabled='disabled']", text: "Scan now"
  end

  test "a running scan shows progress and asks to be polled" do
    ScanRun.create!(started_at: Time.current, albums_total: 200, albums_done: 50)

    get status_scans_path

    assert_response :success
    assert_select "turbo-frame#scan_status"
    assert_select "[data-controller=?]", "poll"
    assert_match "50 of 200", response.body
    assert_match "width: 25%", response.body
  end

  test "a scan that has not counted the albums yet does not show a bar at zero" do
    ScanRun.create!(started_at: Time.current)

    get status_scans_path

    assert_match "finding albums", response.body
    assert_no_match(/width: 0%/, response.body)
  end

  test "a finished scan stops asking to be polled" do
    ScanRun.create!(started_at: 1.minute.ago, status: "completed", finished_at: Time.current,
                    albums: 12, tracks: 140, created: 2, updated: 10)

    get status_scans_path

    # No controller in the response means the timer disconnects and the
    # polling stops on its own.
    assert_select "[data-controller=?]", "poll", false
    assert_match "12 albums, 140 tracks", response.body
  end

  test "skipped folders are listed, not just counted" do
    ScanRun.create!(started_at: 1.minute.ago, status: "completed", finished_at: Time.current,
                    skipped: [ "Some Artist/An Album", "Another/One" ])

    get scans_path

    # A skipped folder is a fixable problem in the files, so it has to be
    # possible to see which one.
    assert_match "Some Artist/An Album", response.body
    assert_match "2 folders skipped", response.body
  end

  test "a failed scan shows why" do
    ScanRun.create!(started_at: 1.minute.ago, status: "failed", finished_at: Time.current,
                    error: "Errno::ENOENT: the mount is gone")

    get scans_path

    assert_match "Last scan failed", response.body
    assert_match "the mount is gone", response.body
  end

  test "a scan interrupted by a restart does not block the next one forever" do
    dead = ScanRun.create!(started_at: 2.hours.ago)
    dead.update_columns(updated_at: 2.hours.ago)

    assert_difference "ScanRun.count", 1 do
      post scans_path
    end

    assert_equal "failed", dead.reload.status
    assert ScanRun.current.present?
  end
end
