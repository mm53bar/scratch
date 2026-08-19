class HomeController < ApplicationController
  def index
    @library_path = Scratch.library_root
    @library_readable = @library_path.directory? && @library_path.readable?
    # Surfaced deliberately: the read-only mount is a design guarantee
    # (docs/adr/20260819-read-only-library.md), so a deployment that gets it
    # wrong should be visible rather than merely harmless-looking.
    @library_writable = @library_path.directory? && @library_path.writable?
  end
end
