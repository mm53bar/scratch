# An album as a concept, independent of format.
#
# This is the join that gives the app its reason to exist: two releases sharing
# a release group are the same album on different media, so "what do I own on
# vinyl but not digitally" is a group-by rather than a matching problem.
class ReleaseGroup < ApplicationRecord
  belongs_to :artist
  has_many :releases, dependent: :destroy
  has_many :tracks, through: :releases

  validates :title, presence: true, uniqueness: { scope: :artist_id }

  scope :alphabetical, -> { order(:title) }
  scope :chronological, -> { order(Arel.sql("year IS NULL, year"), :title) }

  # Owned on `medium`, or owned on none of the given media. Written as EXISTS
  # subqueries rather than joins so that asking two questions at once — on
  # vinyl AND not digitally — does not multiply rows.
  scope :on_medium, ->(medium) {
    where(Release.where("releases.release_group_id = release_groups.id").where(medium:).arel.exists)
  }
  scope :not_on_medium, ->(medium) {
    where.not(Release.where("releases.release_group_id = release_groups.id").where(medium:).arel.exists)
  }

  def media = releases.distinct.pluck(:medium).sort

  def owned_on?(medium) = releases.exists?(medium:)
end
