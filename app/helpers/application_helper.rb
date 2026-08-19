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
end
