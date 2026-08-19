# The physical collection, and what it is missing.
class ShelfController < ApplicationController
  def show
    @physical = ReleaseGroup.includes(:artist, :releases)
                            .where(id: Release.physical.select(:release_group_id))
                            .chronological

    # The question the app exists to answer, in both directions.
    @missing_digitally = ReleaseGroup.includes(:artist, :releases)
                                     .on_medium("vinyl").not_on_medium("digital").chronological
    @missing_physically = ReleaseGroup.includes(:artist, :releases)
                                      .on_medium("digital")
                                      .not_on_medium("vinyl").not_on_medium("cd")
                                      .chronological
  end
end
