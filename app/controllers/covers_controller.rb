# Serves an album's cover at one of the named sizes.
#
# Addressed by album and size rather than by storage key, so the URL is stable:
# regenerating a variant does not hand every page on the site a new URL and make
# it fetch again for nothing.
#
# HAND THE PROXY A PATH; DO NOT STREAM, AND DO NOT BUFFER IF A PATH WILL DO.
# Active Storage's own proxy controller includes ActionController::Live, whose
# buffer deletes Content-Length on the first write and hands the body to a
# second thread that checks out its own database connection. Measured elsewhere
# in this house: a 40KB thumbnail through that route had a p90 of 516ms and a
# 2.4s tail, while send_file served 2.3MB in a flat 165ms.
#
# So: send_file when the blob is a real file on disk, send_data when it is not.
# The fallback is not decoration — path_for exists on the Disk service and
# nowhere else, so this degrades to buffering rather than raising the day
# storage moves elsewhere.
class CoversController < ApplicationController
  def show
    group = ReleaseGroup.find(params[:album_id])

    return head :not_found unless group.cover.attached?
    return head :not_found unless ReleaseGroup::COVER_VARIANTS.include?(params[:variant])

    serve group.cover.variant(params[:variant].to_sym)
  end

  private

  def serve(variant)
    blob = variant.processed.image

    # Immutable by construction: this URL names one album at one size, so the
    # bytes behind it cannot change.
    expires_in 1.year, public: true, immutable: true

    # Set explicitly. Rack::Head empties the body of a HEAD before anything
    # downstream counts it, so a length computed from the body is 0 for exactly
    # the request that asked only for the length.
    response.headers["Content-Length"] = blob.byte_size.to_s

    # A HEAD asks what a GET would answer, not for the bytes. This returns
    # before send_file deliberately: Rack::Sendfile rewrites Content-Length to 0
    # and lets the proxy restate it from the file, which is right for a GET and
    # would throw away the only answer a HEAD has.
    return head :ok, content_type: blob.content_type if request.head?

    options = { type: blob.content_type, filename: blob.filename.sanitized, disposition: :inline }

    if (path = disk_path_for(blob))
      send_file path, **options
    else
      send_data blob.download, **options
    end
  end

  # The blob as a path the proxy can open, or nil if it is not one. Checked
  # rather than assumed on both counts: a missing file has to fall through to a
  # download instead of handing Rack a path that resolves to nothing, because
  # Rack::Sendfile does not stat it and the proxy would answer an empty 200.
  def disk_path_for(blob)
    service = blob.service
    return nil unless service.respond_to?(:path_for)

    path = service.path_for(blob.key)
    path if File.exist?(path)
  end
end
