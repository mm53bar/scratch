# Stands in for the network in tests. Records what it was asked so tests can
# assert on caching, and can be told to fail so the degraded paths get covered.
class FakeCatalogueTransport
  attr_reader :calls

  def initialize(search: "search", release: "release", raise_with: nil)
    @search = search
    @release = release
    @raise_with = raise_with
    @calls = []
  end

  def get(path, params)
    @calls << [ path, params ]
    raise CatalogueLookup::Unavailable, @raise_with if @raise_with

    fixture(path.start_with?("release/") ? @release : @search)
  end

  private

  def fixture(name)
    JSON.parse(Rails.root.join("test/fixtures/files/musicbrainz/#{name}.json").read)
  end
end
