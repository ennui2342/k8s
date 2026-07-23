# Best-effort reconstruction of the 2026-05-20 patch (commit 65cf5fb).
# Resolves 1 CRITICAL + 6 HIGH CVEs: libcrypto3/libssl3 3.5.5-r0->3.5.6-r0,
# musl 1.2.5-r21->r23, zlib 1.3.1-r2->1.3.2-r0.
# NOTE: verify the base image's original USER (`docker inspect --format '{{.Config.User}}'`)
# and restore it after the upgrade — omitted here since it wasn't recorded at patch time.
FROM ghcr.io/fluxcd/image-reflector-controller:v1.1.1
USER root
RUN apk update && apk upgrade --no-cache
