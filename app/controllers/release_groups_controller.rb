class ReleaseGroupsController < ApplicationController
  def index
    @release_groups = ReleaseGroup.includes(:artist, :releases).chronological
    @release_groups = @release_groups.on_medium(params[:medium]) if Release::MEDIA.include?(params[:medium])
    @medium = params[:medium]
  end

  def show
    @release_group = ReleaseGroup.includes(releases: :tracks).find(params[:id])
    @releases = @release_group.releases.order(:medium)
  end
end
