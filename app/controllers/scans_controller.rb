# Starting a library scan, and watching one that is already going.
class ScansController < ApplicationController
  def index
    ScanRun.release_stale
    @current = ScanRun.current
    @runs = ScanRun.recent.limit(10)
  end

  # The status panel on its own, for the page to poll while a scan runs.
  def status
    ScanRun.release_stale
    @current = ScanRun.current
    @last = ScanRun.recent.first
    render partial: "scans/status", locals: { current: @current, last: @last }
  end

  def create
    ScanRun.release_stale
    ScanRun.create!(started_at: Time.current, triggered_by: "web").tap do |run|
      LibraryScanJob.perform_later(run)
    end
    redirect_to scans_path
  rescue ActiveRecord::RecordNotUnique
    # The unique index did its job: someone double-clicked, or two people
    # pressed it at once. Not an error worth showing as one.
    redirect_to scans_path, notice: "A scan is already running."
  end
end
