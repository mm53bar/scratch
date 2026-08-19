# One run of the library scan, and what it found.
#
# Kept because a scan takes minutes and happens out of sight: without a record
# of it, "did that work?" has no answer but running it again. Also the only
# place the skipped folders are visible, and those are the ones worth fixing.
class ScanRun < ApplicationRecord
  STATUSES = %w[running completed failed].freeze

  # A scan that has not reported in this long is not running any more — the
  # container was restarted mid-scan and took the job with it. Generous,
  # because a slow library on a network mount is normal and a false positive
  # here would let two scans run at once.
  STALE_AFTER = 30.minutes

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(started_at: :desc) }
  scope :running, -> { where(status: "running") }

  def running? = status == "running"
  def completed? = status == "completed"
  def failed? = status == "failed"

  # Nothing sweeps these up on a timer, so staleness is decided when someone
  # asks — which is the only moment it matters.
  def stale? = running? && updated_at < STALE_AFTER.ago

  # At most one, guaranteed by a partial unique index rather than by looking.
  def self.current
    running.first&.then { |run| run.stale? ? nil : run }
  end

  # Clears a run whose process is gone, so the unique index stops refusing new
  # ones. Says what happened rather than deleting the evidence.
  def self.release_stale
    running.find_each do |run|
      next unless run.stale?

      run.update_columns(status: "failed", finished_at: Time.current, updated_at: Time.current,
                         error: "Interrupted — the app restarted while this scan was running.")
    end
  end

  def duration
    return nil if started_at.nil?

    ((finished_at || Time.current) - started_at).round
  end

  # Nil until the directories have been walked; the bar has no denominator yet.
  def percent
    return nil if albums_total.to_i.zero?

    [ (albums_done.to_f / albums_total * 100).round, 100 ].min
  end

  def summary
    "#{albums} albums, #{tracks} tracks (#{created} new, #{updated} updated, #{skipped.size} skipped)"
  end
end
