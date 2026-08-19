class HomeController < ApplicationController
  def index
    @library_path = Rails.configuration.x.music_library_path
    @library_readable = @library_path.directory? && @library_path.readable?
  end
end
