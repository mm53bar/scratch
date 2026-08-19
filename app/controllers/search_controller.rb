class SearchController < ApplicationController
  LIMIT = 50

  def show
    @query = params[:q].to_s.strip
    return if @query.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    @artists = Artist.where("name LIKE ?", like).alphabetical.limit(LIMIT)
    @release_groups = ReleaseGroup.includes(:artist).where("title LIKE ?", like).chronological.limit(LIMIT)
    @tracks = Track.includes(release: { release_group: :artist })
                   .where("title LIKE ?", like).limit(LIMIT)
  end
end
