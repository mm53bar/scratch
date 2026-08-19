# Production image.
#
# Built and published by .github/workflows/build.yml on every push to main:
#   ghcr.io/<owner>/<repo>:latest      (moves with main)
#   ghcr.io/<owner>/<repo>:<short-sha> (immutable per commit)
#
# The image is host-agnostic — the runtime UID/GID comes from the `user:`
# directive in compose.yaml, so the same image runs anywhere the bind-mounted
# directories are owned by that UID/GID.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Base packages. libvips is for Active Storage variants, sqlite3 for the database.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage, to keep the final image small
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

# Capture the commit so the running app can show which build it is serving.
# .git is removed afterwards so it does not ride along into the final image.
RUN if [ -d .git ]; then \
      git rev-parse HEAD > REVISION && \
      git rev-parse --short HEAD > REVISION_SHORT; \
    else \
      echo "unknown" > REVISION && echo "unknown" > REVISION_SHORT; \
    fi && \
    rm -rf .git

RUN bundle exec bootsnap precompile app/ lib/

# Precompile assets without requiring the real secret key.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final image
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Make the runtime directories world-writable, then drop privileges. A host
# bind-mounting storage/ owns it as some other UID, and compose's `user:` is set
# to match — so Puma has to create its pidfile and socket directory as an
# arbitrary UID, not just as 1000. Without this the container starts, binds its
# port, and then dies on
# `Permission denied @ dir_s_mkdir - /rails/tmp/sockets`.
#
# The chmod runs before USER because only root can apply it. Nothing secret
# lives in these directories; the databases in storage/ are owned by the host.
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log storage && \
    chmod -R 0777 tmp log storage

# Default to the unprivileged user baked in above. A deployment bind-mounting
# storage/ should override this with compose's `user:` to match the host owner.
USER 1000:1000

# That arbitrary UID has no writable home directory, so Bundler warns and falls
# back to a temp home on every boot. Point HOME at the world-writable tmp dir.
ENV HOME="/rails/tmp"

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
