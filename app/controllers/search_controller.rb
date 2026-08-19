class SearchController < ApplicationController
  LIMIT = 50
  SUGGESTION_LIMIT = 6

  def show
    @query = params[:q].to_s.strip
    return if @query.blank?

    @artists = matching(Artist, :name).alphabetical.limit(LIMIT)
    @release_groups = matching(ReleaseGroup, :title).includes(:artist).chronological.limit(LIMIT)
    @tracks = matching(Track, :title).includes(release: { release_group: :artist }).limit(LIMIT)
  end

  # Feeds the autocomplete component, which expects {suggestions: [...]} with a
  # title, an optional subtitle and a url to navigate to on selection.
  def suggestions
    query = params[:q].to_s.strip
    return render json: { suggestions: [] } if query.length < 2

    render json: { suggestions: artist_suggestions(query) + album_suggestions(query) + track_suggestions(query) }
  end

  private

  # Escaped so that a query of "%" matches a literal percent sign rather than
  # every row in the table.
  def matching(scope, column)
    scope.where("#{column} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%")
  end

  def artist_suggestions(query)
    Artist.where("name LIKE ?", like(query)).alphabetical.limit(SUGGESTION_LIMIT).map do |artist|
      { title: artist.name, subtitle: "Artist", url: artist_path(artist) }
    end
  end

  def album_suggestions(query)
    ReleaseGroup.where("title LIKE ?", like(query)).includes(:artist, :releases)
                .chronological.limit(SUGGESTION_LIMIT).map do |group|
      { title: group.title,
        subtitle: [ group.artist.name, group.year, group.media.join(", ").presence ].compact.join(" · "),
        url: album_path(group) }
    end
  end

  def track_suggestions(query)
    Track.where("title LIKE ?", like(query)).includes(release: { release_group: :artist })
         .limit(SUGGESTION_LIMIT).map do |track|
      { title: track.title,
        subtitle: "#{track.credited_artist} · #{track.release_group.title}",
        url: album_path(track.release_group) }
    end
  end

  def like(query) = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
end
