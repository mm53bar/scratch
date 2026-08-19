module ApplicationHelper
  # Which Rails Blocks badge variant each medium wears. The badge component
  # itself lives in app/views/shared/components/badge/ — do not hand-roll one.
  MEDIUM_VARIANTS = { "vinyl" => "orange", "cd" => "blue", "digital" => "neutral" }.freeze

  def medium_badge(medium, size: "sm")
    render "shared/components/badge/badge",
           text: medium,
           variant: MEDIUM_VARIANTS.fetch(medium, "neutral"),
           size: size,
           pill: true
  end

  # Albums without a year sort last and should say so rather than showing a gap.
  def year_or_dash(year) = year.presence || "—"

  # The frame a pressing's details load into. Named for the pressing so that
  # several open rows do not fight over one frame.
  def dom_id_for_pressing(candidate) = "pressing_#{candidate.musicbrainz_release_id}"

  # A cover at a named size, or a neutral placeholder when the album has none.
  def cover_image(group, variant: "thumb", size: 40, classes: nil)
    box = "size-#{size / 4} shrink-0 rounded bg-neutral-100 object-cover"
    if group.cover.attached?
      image_tag album_cover_path(group, variant),
                loading: "lazy", alt: "", class: [ box, classes ]
    else
      tag.div class: [ box, "ring-1 ring-inset ring-neutral-200", classes ]
    end
  end
end
