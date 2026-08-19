require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Scratch
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Every filesystem path this app touches is configuration, never a literal.
    # The library root is where the music lives; it is mounted read-only and the
    # app only ever reads from it. Defaults to a directory inside the app so a
    # fresh clone runs with no configuration at all.
    config.x.music_library_path =
      Pathname.new(ENV.fetch("MUSIC_LIBRARY_PATH", Rails.root.join("music").to_s))

    # The commit this build was made from, written into the image at build time.
    # Shown in the footer so a deploy that silently did not land is visible.
    config.x.revision =
      (Rails.root.join("REVISION_SHORT").read.strip if Rails.root.join("REVISION_SHORT").exist?)

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
