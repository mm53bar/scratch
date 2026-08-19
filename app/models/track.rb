class Track < ApplicationRecord
  belongs_to :release
  has_one :release_group, through: :release
  has_one :artist, through: :release_group

  validates :title, presence: true
  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :disc, presence: true, numericality: { greater_than: 0 }
  validates :position, uniqueness: { scope: %i[release_id disc] }

  scope :in_order, -> { order(:disc, :position) }

  # Nil artist_credit means "same as the album artist" — stored only when it
  # actually differs, which is the normal case on a compilation.
  def credited_artist = artist_credit.presence || artist&.name

  def duration
    return nil if duration_seconds.blank?

    format("%d:%02d", duration_seconds / 60, duration_seconds % 60)
  end
end
