# Physical releases only. Digital ones come from LibraryScan and are not
# editable here: the files are the source of truth and this app cannot write to
# them, so an edit form would promise something it cannot deliver.
class ReleasesController < ApplicationController
  before_action :set_release, only: %i[edit update destroy]
  before_action :refuse_digital, only: %i[edit update destroy]

  def new
    @release = Release.new(medium: params[:medium].presence_in(Release::MEDIA) || "vinyl",
                           release_group_id: params[:release_group_id])
  end

  def create
    @release = Release.new(release_params.except(:artist_name, :album_title))
    @release.artist_name = release_params[:artist_name]
    @release.album_title = release_params[:album_title]
    @release.release_group = resolve_release_group

    if @release.release_group&.persisted? && @release.save
      redirect_to album_path(@release.release_group), notice: "Added to your shelf."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @release.update(release_params.except(:medium, :artist_name, :album_title))
      redirect_to album_path(@release.release_group), notice: "Updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    group = @release.release_group
    @release.destroy!
    # A group with nothing left in it is not a collection entry any more.
    group.destroy! if group.releases.reload.empty?
    redirect_to shelf_path, notice: "Removed."
  end

  private

  def set_release = @release = Release.find(params[:id])

  def refuse_digital
    return if @release.physical?

    redirect_to album_path(@release.release_group),
                alert: "Digital releases come from the library and are not edited here."
  end

  def release_params
    params.expect(release: %i[medium edition year acquired_on notes release_group_id artist_name album_title])
  end

  # Either attach to an album already known, or create the artist and album on
  # the way in — a record arriving from a shop is usually the first time this
  # collection has heard of it.
  def resolve_release_group
    if release_params[:release_group_id].present?
      ReleaseGroup.find_by(id: release_params[:release_group_id])
    else
      artist_name = release_params[:artist_name].to_s.strip
      title = release_params[:album_title].to_s.strip
      return nil if artist_name.blank? || title.blank?

      artist = Artist.find_or_create_by!(name: artist_name)
      ReleaseGroup.find_or_create_by!(artist:, title:).tap do |group|
        group.update!(year: release_params[:year]) if release_params[:year].present? && group.year.blank?
      end
    end
  end
end
