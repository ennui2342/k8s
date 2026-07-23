# Best-effort reconstruction of the 2026-05-22 patch (commit 2f47372).
# Resolves 1 CRITICAL + 7 HIGH CVEs: openssl 3.5.5-r0->3.5.6-r0, musl
# 1.2.5-r21->r23, nghttp2 1.68.0-r0->1.69.0-r0, zlib 1.3.1-r2->1.3.2-r0.
# NOTE: verify the base image's original USER (`docker inspect --format '{{.Config.User}}'`)
# and restore it after the upgrade — omitted here since it wasn't recorded at patch time.
FROM tsightler/ring-mqtt:latest
USER root
RUN apk update && apk upgrade --no-cache
