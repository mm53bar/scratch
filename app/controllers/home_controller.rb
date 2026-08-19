class HomeController < ApplicationController
  def index
    @counts = {
      artists: Artist.count,
      albums: ReleaseGroup.count,
      releases: Release.count,
      tracks: Track.count
    }
    @by_medium = Release.group(:medium).count

    # Twelve rather than eight: it divides evenly by every column count the
    # grid uses (2, 3, 4, 6), so the last row is never a gap-toothed remnant.
    @recent = ReleaseGroup.includes(:artist, :releases, cover_attachment: :blob)
                          .order(created_at: :desc).limit(12)

    # When the catalogue was last rebuilt, which is the only thing on this page
    # that goes stale. The library diagnostics moved to the Library page, where
    # they are what the page is about rather than a footnote under the covers.
    @last_scan = ScanRun.recent.first
  end
end
