# Best-effort reconstruction of the 2026-06-13 patch (commit 7a6729e).
# Resolves 5 CRITICAL + 24 HIGH CVEs (busybox, curl, openssl, musl, zlib,
# nghttp2, libcap, ca-certificates, bash, libretls — see commit for full list).
# Upstream Docker Hub inactive since 2023-07-01 (still Alpine 3.15.0); the
# v3.15 dl-cdn backport branch still serves security fixes as of patch time —
# reverify this is still true before rebuilding, it may need re-checking.
FROM monstrenyatko/mdns-repeater:latest
RUN apk update && apk upgrade --no-cache
