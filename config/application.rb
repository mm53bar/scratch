require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Scratch
  # Every directory this app reads is configuration, never a literal in the
  # code. This repository is public and other people lay their disks out their
  # own way; a path baked into a model is a path they cannot change without a
  # fork.
  #
  # Both default to somewhere inside the app itself, so a fresh clone runs with
  # no configuration at all and a deployment overrides only what it mounts
  # elsewhere. These are module methods rather than config.x because
  # config/database.yml is evaluated during boot, before configuration is
  # available.

  # Where the music lives. Mounted READ-ONLY: this app catalogues what is on
  # disk and never writes to it.
  def self.library_root
    Pathname.new(ENV.fetch("MUSIC_LIBRARY_PATH") { Rails.root.join("music").to_s })
  end

  # Where the SQLite databases and Active Storage blobs live. They are useless
  # apart, so they share one directory and are backed up as one thing.
  def self.storage_root
    Pathname.new(ENV.fetch("STORAGE_PATH") { Rails.root.join("storage").to_s })
  end
end

module Scratch
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

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
