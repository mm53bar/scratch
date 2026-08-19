class HomeController < ApplicationController
  def index
    @library_path = Scratch.library_root
    @library_readable = @library_path.directory? && @library_path.readable?
    # Surfaced deliberately: the read-only mount is a design guarantee
    # (docs/adr/20260819-read-only-library.md), so a deployment that gets it
    # wrong should be visible rather than merely harmless-looking.
    @library_writable = @library_path.directory? && @library_path.writable?

    @counts = {
      artists: Artist.count,
      albums: ReleaseGroup.count,
      releases: Release.count,
      tracks: Track.count
    }
    @by_medium = Release.group(:medium).count
    @recent = ReleaseGroup.includes(:artist, :releases, cover_attachment: :blob).order(created_at: :desc).limit(8)
  end
end
