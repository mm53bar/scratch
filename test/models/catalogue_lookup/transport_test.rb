require "test_helper"

class CatalogueLookup::TransportTest < ActiveSupport::TestCase
  # Counts attempts and hands back whatever the test queued, so the retry
  # behaviour can be exercised without a socket.
  class CountingTransport < CatalogueLookup::Transport
    attr_reader :attempts

    def initialize(responses)
      super()
      @responses = responses
      @attempts = 0
    end

    def sleep(_) = nil # the backoff is real in production and skipped here

    private

    def request(_uri)
      @attempts += 1
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  def response(klass, code, body = "{}")
    klass.new("1.1", code, "").tap do |r|
      r.instance_variable_set(:@body, body)
      r.instance_variable_set(:@read, true)
    end
  end

  test "retries a rate limit and returns the answer" do
    # Observed at one request every 1.1 seconds, which is inside the published
    # limit — so a 503 is a normal event, not a failure.
    transport = CountingTransport.new([
      response(Net::HTTPServiceUnavailable, "503"),
      response(Net::HTTPOK, "200", '{"count":1}')
    ])

    assert_equal({ "count" => 1 }, transport.get("release", {}))
    assert_equal 2, transport.attempts
  end

  test "gives up after a bounded number of tries" do
    transport = CountingTransport.new(Array.new(5) { response(Net::HTTPServiceUnavailable, "503") })

    assert_raises(CatalogueLookup::Unavailable) { transport.get("release", {}) }
    # A person is waiting on this, so the number of attempts is finite and small.
    assert_equal CatalogueLookup::Transport::RETRIES + 1, transport.attempts
  end

  test "retries a timeout" do
    transport = CountingTransport.new([
      Timeout::Error.new("execution expired"),
      response(Net::HTTPOK, "200", '{"ok":true}')
    ])

    assert_equal({ "ok" => true }, transport.get("release", {}))
  end

  test "does not retry a reply that will be the same next time" do
    transport = CountingTransport.new([
      response(Net::HTTPBadRequest, "400"),
      response(Net::HTTPOK, "200", '{"unused":true}')
    ])

    # A malformed query is malformed on the second attempt too; retrying it
    # only spends someone's patience and MusicBrainz's rate limit.
    assert_raises(CatalogueLookup::Unavailable) { transport.get("release", {}) }
    assert_equal 1, transport.attempts
  end

  test "nonsense that parses as HTTP but not as JSON is unavailable, not a crash" do
    transport = CountingTransport.new([ response(Net::HTTPOK, "200", "<html>maintenance</html>") ])

    assert_raises(CatalogueLookup::Unavailable) { transport.get("release", {}) }
  end

  test "identifies the app, and says who to contact when told" do
    assert_equal "scratch/1.0", CatalogueLookup::Transport.user_agent

    # Not baked in: this repo is public and someone else's address is not ours
    # to ship. MusicBrainz throttles anonymous clients harder.
    ENV["MUSICBRAINZ_CONTACT"] = "someone@example.com"
    assert_equal "scratch/1.0 ( someone@example.com )", CatalogueLookup::Transport.user_agent
  ensure
    ENV.delete("MUSICBRAINZ_CONTACT")
  end
end
