class Artist < ApplicationRecord
  has_many :release_groups, dependent: :destroy
  has_many :releases, through: :release_groups
  has_many :tracks, through: :releases

  validates :name, presence: true, uniqueness: true
  validates :sort_name, presence: true

  before_validation :derive_sort_name, if: -> { sort_name.blank? }

  scope :alphabetical, -> { order(:sort_name) }

  # "The Beatles" sorts under B, "A Tribe Called Quest" under T. Only leading
  # articles move; nothing else about the name is touched, because a name is
  # data and guessing at it is how you end up with "Boys, Beach The".
  ARTICLES = /\A(the|a|an)\s+/i

  def derive_sort_name
    return if name.blank?

    self.sort_name =
      if (m = ARTICLES.match(name))
        "#{name[m.end(0)..]}, #{name[0...m.end(0)].strip}"
      else
        name
      end
  end
end
