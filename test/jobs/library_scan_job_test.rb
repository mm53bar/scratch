require "test_helper"

class LibraryScanJobTest < ActiveJob::TestCase
  setup do
    ScanRun.delete_all
    @library = Rails.root.join("test/fixtures/files/library")
  end

  test "records what the scan found" do
    run = ScanRun.create!(started_at: Time.current)

    with_library { LibraryScanJob.perform_now(run) }

    run.reload
    assert_equal "completed", run.status
    assert_equal 2, run.albums
    assert_equal 3, run.tracks
    assert run.finished_at.present?
    assert_equal run.albums_total, run.albums_done
  end

  test "a failure is recorded rather than only raised" do
    run = ScanRun.create!(started_at: Time.current)

    failing_scan do
      assert_raises(IOError) { LibraryScanJob.perform_now(run) }
    end

    run.reload
    assert_equal "failed", run.status
    # Otherwise a failed scan is indistinguishable from one that never started.
    assert_match "mount went away", run.error
    assert run.finished_at.present?
    # And the next scan is not blocked by the wreckage of this one.
    assert_nothing_raised { ScanRun.create!(started_at: Time.current) }
  end

  test "does not run a scan that was already finished" do
    run = ScanRun.create!(started_at: 1.hour.ago, status: "completed", finished_at: 1.hour.ago)

    with_library { LibraryScanJob.perform_now(run) }

    assert_equal 0, run.reload.albums
  end

  test "the run is what the page polls, so progress reaches the database" do
    run = ScanRun.create!(started_at: Time.current)

    with_library { LibraryScanJob.perform_now(run) }

    assert_equal 2, run.reload.albums_total
    assert_equal 100, run.percent
  end

  private

  # Minitest 6 dropped minitest/mock, and this needs no framework: swap the
  # constructor, put it back afterwards.
  def failing_scan
    original = LibraryScan.method(:new)
    LibraryScan.define_singleton_method(:new) { |*| raise IOError, "mount went away" }
    yield
  ensure
    LibraryScan.define_singleton_method(:new, original)
  end

  def with_library
    original = ENV["MUSIC_LIBRARY_PATH"]
    ENV["MUSIC_LIBRARY_PATH"] = @library.to_s
    yield
  ensure
    ENV["MUSIC_LIBRARY_PATH"] = original
  end
end
