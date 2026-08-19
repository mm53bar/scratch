ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/fake_catalogue_transport"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # No test reaches MusicBrainz. A test that wants a different answer says
    # so; a test that forgets to gets a stub rather than a socket.
    setup { CatalogueLookup.transport = FakeCatalogueTransport.new }
    teardown { CatalogueLookup.transport = nil }

    # Add more helper methods to be used by all tests here...
  end
end
