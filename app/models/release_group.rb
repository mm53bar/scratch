# An album as a concept, independent of format.
#
# This is the join that gives the app its reason to exist: two releases sharing
# a release group are the same album on different media, so "what do I own on
# vinyl but not digitally" is a group-by rather than a matching problem.
class ReleaseGroup < ApplicationRecord
  belongs_to :artist
  has_many :releases, dependent: :destroy
  has_many :tracks, through: :releases

  # The cover is copied in from the library rather than read from it on every
  # request: the library is mounted read-only and may not be mounted at all,
  # and variants have to be written somewhere regardless.
  has_one_attached :cover do |attachable|
    # preprocessed so the variant exists by the time a page asks for it. A cold
    # variant on a NAS has been measured at 42 seconds against 32ms warm, which
    # is long enough to occupy every Puma thread on one unlucky page load.
    attachable.variant :thumb, resize_to_fill: [ 160, 160 ], format: :jpeg, saver: { quality: 80 }, preprocessed: true
    attachable.variant :detail, resize_to_limit: [ 600, 600 ], format: :jpeg, saver: { quality: 85 }, preprocessed: true
  end

  COVER_VARIANTS = %w[thumb detail].freeze

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
