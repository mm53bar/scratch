class SearchController < ApplicationController
  LIMIT = 50
  SUGGESTION_LIMIT = 6
  MIN_SUGGESTION_LENGTH = 2

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
    return render json: { suggestions: [] } if query.length < MIN_SUGGESTION_LENGTH

    render json: { suggestions: artist_suggestions + album_suggestions + track_suggestions }
  end

  private

  def query = params[:q].to_s.strip

  # Arel builds a real column reference and a bound parameter, rather than
  # interpolating a column name into a SQL string — which is safe here but
  # indistinguishable from unsafe to anything reading the code.
  #
  # The value is escaped so a query of "%" matches a literal percent sign
  # instead of every row in the table.
  def matching(scope, column)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    scope.where(scope.arel_table[column].matches(pattern))
  end

  def artist_suggestions
    matching(Artist, :name).alphabetical.limit(SUGGESTION_LIMIT).map do |artist|
      { title: artist.name, subtitle: "Artist", url: artist_path(artist) }
    end
  end

  def album_suggestions
    matching(ReleaseGroup, :title).includes(:artist, :releases)
                                  .chronological.limit(SUGGESTION_LIMIT).map do |group|
      { title: group.title,
        subtitle: [ group.artist.name, group.year, group.media.join(", ").presence ].compact.join(" · "),
        url: album_path(group) }
    end
  end

  def track_suggestions
    matching(Track, :title).includes(release: { release_group: :artist })
                           .limit(SUGGESTION_LIMIT).map do |track|
      { title: track.title,
        subtitle: "#{track.credited_artist} · #{track.release_group.title}",
        url: album_path(track.release_group) }
    end
  end
end
