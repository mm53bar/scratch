# Looks up the number printed on a record and offers what it might be.
#
# Read-only and decides nothing: it renders a list, and a person picks from it.
# The picking happens in ReleasesController#new, because what comes back is a
# half-filled form rather than a saved row.
class CatalogueLookupsController < ApplicationController
  def show
    @catalogue_number = params[:catalogue_number].to_s.strip
    @medium = params[:medium].presence_in(Release::MEDIA) || "vinyl"
    @candidates = @catalogue_number.present? ? CatalogueLookup.new.search(@catalogue_number) : []
  rescue CatalogueLookup::Unavailable => e
    # A lookup is a convenience wrapped around a form that works without it, so
    # failing to reach MusicBrainz is a note on the page, not an error page.
    Rails.logger.warn("Catalogue lookup failed: #{e.message}")
    @candidates = []
    @unavailable = true
  end
end
