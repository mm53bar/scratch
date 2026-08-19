require "net/http"
require "json"

class CatalogueLookup
  # Talks to MusicBrainz over HTTP and hands back parsed JSON.
  #
  # Separated from the lookup itself so tests can hand in a stub. Nothing here
  # knows what a release is; nothing in CatalogueLookup knows what a socket is.
  class Transport
    HOST = "https://musicbrainz.org/ws/2"

    # Observed 503ing at one request every 1.1 seconds, which is inside the
    # published limit, so the limit is not the only reason it says no. Retried
    # rather than surfaced, because a person who typed a number and got
    # "unavailable" would simply type it again anyway.
    RETRIES = 2
    BACKOFF = 1.0

    # A lookup happens inside a request, so the ceiling on how long it can hold
    # a web thread has to be a number someone chose on purpose.
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 6

    def initialize(user_agent: self.class.user_agent)
      @user_agent = user_agent
    end

    # MusicBrainz asks that clients identify themselves and throttles harder
    # when they do not. The contact is an env var because this repo is public
    # and someone else's address does not belong in it.
    def self.user_agent
      contact = ENV["MUSICBRAINZ_CONTACT"].to_s.strip
      contact.present? ? "scratch/1.0 ( #{contact} )" : "scratch/1.0"
    end

    def get(path, params)
      uri = URI("#{HOST}/#{path}")
      uri.query = URI.encode_www_form(params.merge(fmt: "json"))
      JSON.parse(fetch(uri))
    rescue JSON::ParserError
      raise Unavailable, "MusicBrainz sent something that was not JSON"
    end

    private

    # Raised for the conditions that are worth asking again about. A 400 will
    # be a 400 the second time, so it is not one of them.
    Retryable = Class.new(StandardError)
    RETRYABLE_ERRORS = [ Retryable, Timeout::Error, SystemCallError, IOError, Net::HTTPBadResponse ].freeze

    def fetch(uri)
      attempt = 0
      begin
        attempt += 1
        case (response = request(uri))
        when Net::HTTPSuccess then response.body
        when Net::HTTPServiceUnavailable, Net::HTTPTooManyRequests
          raise Retryable, "MusicBrainz is rate limiting this app"
        else
          raise Unavailable, "MusicBrainz replied #{response.code}"
        end
      rescue *RETRYABLE_ERRORS => e
        raise Unavailable, e.message if attempt > RETRIES

        sleep(BACKOFF * attempt)
        retry
      end
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: true,
                      open_timeout: OPEN_TIMEOUT,
                      read_timeout: READ_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => @user_agent))
      end
    end
  end
end
