# A specific thing you own: this vinyl, that CD, the files on disk.
#
# Tracks belong to a release rather than to its group so that a deluxe CD with
# bonus tracks and a nine-track vinyl of the same album can both be true.
class Release < ApplicationRecord
  MEDIA = %w[vinyl cd digital].freeze

  # Form-only. Adding a record from a shop is usually the first time this
  # collection has heard of the artist or the album, so the form accepts them
  # by name and the controller resolves them. Keeping them as attributes means
  # a failed save re-renders with what was typed rather than losing it.
  attr_accessor :artist_name, :album_title

  belongs_to :release_group
  has_one :artist, through: :release_group
  has_many :tracks, -> { order(:disc, :position) }, dependent: :destroy, inverse_of: :release

  validates :medium, presence: true, inclusion: { in: MEDIA }
  validates :path, uniqueness: true, allow_nil: true

  # A digital release is a folder; physical media are not. Enforced because a
  # physical release with a path would be silently rewritten by the next scan.
  validate :path_only_for_digital

  scope :physical, -> { where(medium: %w[vinyl cd]) }
  scope :digital, -> { where(medium: "digital") }

  def digital? = medium == "digital"
  def physical? = !digital?

  # What to call this in a list: the album, plus the edition when there is one.
  def display_title
    [ release_group.title, edition.presence && "(#{edition})" ].compact.join(" ")
  end

  private

  def path_only_for_digital
    errors.add(:path, "is only meaningful for digital releases") if path.present? && !digital?
  end
end
