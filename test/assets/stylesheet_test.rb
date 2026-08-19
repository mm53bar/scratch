require "test_helper"

class StylesheetTest < ActiveSupport::TestCase
  # The Rails Blocks components ship dark: classes throughout, and Tailwind v4
  # points that variant at prefers-color-scheme by default. This app's own
  # views are light-only — the body is bg-white with no dark counterpart — so
  # honouring the OS setting produced dark cards on a white page.
  #
  # Asserting on the built stylesheet rather than the source because the source
  # is one @custom-variant line whose entire purpose is what it compiles to,
  # and because installing another component is exactly how this comes back.
  test "no styling keys off the operating system's colour scheme" do
    css = Rails.root.join("app/assets/builds/tailwind.css")
    skip "stylesheet not built" unless css.exist?

    # assert_not on a boolean rather than assert_not_includes: the latter
    # prints the whole stylesheet on failure, which buries the message.
    assert_not css.read.include?("prefers-color-scheme"),
                        "dark: classes are following the OS again — the app has no dark theme " \
                        "of its own, so this shows component styling against a white page"
  end
end
