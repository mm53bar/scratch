# Starting a library scan, and watching one that is already going.
class ScansController < ApplicationController
  def index
    ScanRun.release_stale
    @current = ScanRun.current
    @runs = ScanRun.recent.limit(10)

    @library_path = Scratch.library_root
    @library_readable = @library_path.directory? && @library_path.readable?
    # Surfaced deliberately: the read-only mount is a design guarantee
    # (docs/adr/20260819-read-only-library.md), so a deployment that gets it
    # wrong should be visible rather than merely harmless-looking.
    @library_writable = @library_path.directory? && @library_path.writable?
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
