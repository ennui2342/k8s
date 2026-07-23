# Best-effort reconstruction of the 2026-05-21 patch (commit 031454d).
# Resolves 1 CRITICAL + 5 HIGH CVEs: gnutls 3.8.12-r0->3.8.13-r0,
# nghttp2-libs 1.68.0-r0->1.69.0-r0.
# NOTE: verify the base image's original USER (`docker inspect --format '{{.Config.User}}'`)
# and restore it after the upgrade — omitted here since it wasn't recorded at patch time.
FROM ghcr.io/fluxcd/kustomize-controller:v1.8.4
USER root
RUN apk update && apk upgrade --no-cache
