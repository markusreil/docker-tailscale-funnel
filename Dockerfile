ARG TAILSCALE_VERSION=stable
FROM tailscale/tailscale:${TAILSCALE_VERSION}

ARG BUILD_DATE=unknown
ARG VERSION=unknown
ARG GIT_SHA=unknown
ENV BASE_IMAGE=tailscale/tailscale \
    BUILD_DATE=${BUILD_DATE} \
    VERSION=${VERSION} \
    GIT_SHA=${GIT_SHA}
LABEL org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.revision=${GIT_SHA} \
      org.opencontainers.image.created=${BUILD_DATE}

COPY docker/entrypoint.sh docker/funnel.sh /usr/local/bin/docker-tailscale/
RUN chmod +x /usr/local/bin/docker-tailscale/entrypoint.sh \
    && ln -sf /usr/local/bin/docker-tailscale/entrypoint.sh /entrypoint.sh

HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=3 \
  CMD tailscale status --json | grep -q '"BackendState": *"Running"' || exit 1

ENTRYPOINT ["/entrypoint.sh"]
