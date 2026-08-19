class ArtistsController < ApplicationController
  def index
    @artists = Artist.alphabetical
                     .left_joins(:release_groups)
                     .group(:id)
                     .select("artists.*, COUNT(release_groups.id) AS release_groups_count")
  end

  def show
    @artist = Artist.find(params[:id])
    @release_groups = @artist.release_groups.includes(:releases, cover_attachment: :blob).chronological
  end
end
