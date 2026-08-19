module ApplicationHelper
  MEDIUM_STYLES = {
    "vinyl" => "bg-amber-100 text-amber-900 ring-amber-200",
    "cd" => "bg-sky-100 text-sky-900 ring-sky-200",
    "digital" => "bg-neutral-100 text-neutral-700 ring-neutral-200"
  }.freeze

  def medium_badge(medium)
    tag.span medium,
             class: "inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium " \
                    "ring-1 ring-inset #{MEDIUM_STYLES.fetch(medium, MEDIUM_STYLES['digital'])}"
  end

  # Albums without a year sort last and should say so rather than showing a gap.
  def year_or_dash(year) = year.presence || "—"
end
