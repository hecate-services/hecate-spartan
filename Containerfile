# Multi-stage Erlang build for hecate-spartan.
# Pushed to ghcr.io/hecate-services/hecate-spartan:latest + :semver by CI.

#----------------------------------------------------------------------
# Stage 1 — builder: full Erlang + rebar3 + deps
#----------------------------------------------------------------------
FROM docker.io/erlang:27-alpine AS builder

RUN apk add --no-cache git build-base

WORKDIR /build
# No rebar.lock committed (org convention: lockfiles stay out of git), so
# deps resolve at build time.
COPY rebar.config ./
COPY apps ./apps
COPY config ./config

# Fetch deps + assemble a production release with embedded ERTS.
RUN rebar3 as prod tar

#----------------------------------------------------------------------
# Stage 2 — runtime: slim image, just the release tarball
#----------------------------------------------------------------------
FROM docker.io/alpine:3.20

RUN apk add --no-cache libstdc++ ncurses-libs openssl wget

WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_spartan/*.tar.gz /tmp/release.tar.gz
RUN tar xf /tmp/release.tar.gz && rm /tmp/release.tar.gz

# Realm service-principal cert mounts here; station socket under /run/macula.
VOLUME ["/etc/hecate/secrets", "/var/lib/hecate-spartan"]

EXPOSE 8470 8471

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --spider -q http://localhost:8470/health || exit 1

ENTRYPOINT ["/app/bin/hecate_spartan"]
CMD ["foreground"]
