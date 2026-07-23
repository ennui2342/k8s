# Best-effort reconstruction of the 2026-05-25 patch (commit 9fbeceb).
# Resolves 2 CRITICAL + 20 HIGH CVEs: libcrypto3/libssl3 3.5.4-r0->3.5.6-r0,
# bind-libs/bind-tools 9.20.16-r0->9.20.22-r0, lcms2 2.16-r0->2.19-r0.
# NOTE: verify the base image's original USER (`docker inspect --format '{{.Config.User}}'`)
# and restore it after the upgrade — omitted here since it wasn't recorded at patch time.
FROM homeassistant/home-assistant:2026.5.3
USER root
RUN apk update && apk upgrade --no-cache
