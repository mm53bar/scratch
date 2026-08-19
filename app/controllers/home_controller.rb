class HomeController < ApplicationController
  def index
    @library_path = Scratch.library_root
    @library_readable = @library_path.directory? && @library_path.readable?
  end
end
