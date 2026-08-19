# Runs the library scan out of the request cycle.
#
# The scan takes minutes — it reads tags from every file over a network mount —
# so it cannot happen while someone waits on a page. Progress is written to the
# ScanRun as it goes; the page polls that rather than the job.
class LibraryScanJob < ApplicationJob
  queue_as :default

  # Progress is written at most this often. The scan touches every album, and
  # a write per album on a large library is a lot of noise for a bar that only
  # moves a pixel at a time.
  PROGRESS_EVERY = 2.seconds

  def perform(scan_run)
    return unless scan_run.running?

    last_write = Time.current
    result = LibraryScan.new.call do |done, total|
      next unless total != scan_run.albums_total || done == total || Time.current - last_write >= PROGRESS_EVERY

      last_write = Time.current
      scan_run.update_columns(albums_done: done, albums_total: total, updated_at: Time.current)
    end

    scan_run.update!(status: "completed", finished_at: Time.current,
                     albums: result.albums, tracks: result.tracks,
                     created: result.created, updated: result.updated, skipped: result.skipped)
  rescue StandardError => e
    # The run is the only record that this happened, so it has to outlive the
    # exception — otherwise a failed scan is indistinguishable from one that
    # never started.
    scan_run.update_columns(status: "failed", finished_at: Time.current, updated_at: Time.current,
                            error: "#{e.class}: #{e.message}")
    raise
  end
end
