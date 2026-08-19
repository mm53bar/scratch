require "test_helper"

class ScanRunTest < ActiveSupport::TestCase
  setup { ScanRun.delete_all }

  test "the database refuses a second running scan" do
    ScanRun.create!(started_at: Time.current)

    # Checked-then-inserted would race; the index cannot.
    assert_raises(ActiveRecord::RecordNotUnique) { ScanRun.create!(started_at: Time.current) }
  end

  test "a finished scan does not block the next one" do
    ScanRun.create!(started_at: 1.hour.ago, status: "completed", finished_at: 1.hour.ago)
    ScanRun.create!(started_at: 1.hour.ago, status: "failed", finished_at: 1.hour.ago)

    assert_nothing_raised { ScanRun.create!(started_at: Time.current) }
  end

  test "a scan whose process died is not treated as running" do
    run = ScanRun.create!(started_at: 2.hours.ago)
    run.update_columns(updated_at: 2.hours.ago)

    assert run.stale?
    assert_nil ScanRun.current
  end

  test "releasing a stale scan says what happened rather than deleting it" do
    run = ScanRun.create!(started_at: 2.hours.ago)
    run.update_columns(updated_at: 2.hours.ago)

    ScanRun.release_stale

    assert_equal "failed", run.reload.status
    assert_match "restarted", run.error
    assert run.finished_at.present?
    # And the index is free again.
    assert_nothing_raised { ScanRun.create!(started_at: Time.current) }
  end

  test "a scan still reporting is left alone" do
    run = ScanRun.create!(started_at: 2.hours.ago) # started long ago, still writing progress

    ScanRun.release_stale

    assert_equal "running", run.reload.status
    assert_equal run, ScanRun.current
  end

  test "progress has no percentage until the albums have been counted" do
    run = ScanRun.create!(started_at: Time.current)

    assert_nil run.percent, "a bar at zero reads as stuck; there is no denominator yet"

    run.update!(albums_total: 200, albums_done: 50)
    assert_equal 25, run.percent
  end

  test "progress cannot exceed the total" do
    run = ScanRun.create!(started_at: Time.current, albums_total: 10, albums_done: 12)

    assert_equal 100, run.percent
  end
end
