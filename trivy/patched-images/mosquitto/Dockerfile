# Best-effort reconstruction of the 2026-05-20 patch (commit bc5bf85).
# Resolves 1 CRITICAL + 4 HIGH gnutls CVEs (3.8.12-r0 -> 3.8.13-r0).
# No newer 2.1.2 upstream tag exists — rebuild locally, import into node
# containerd, and reference as ghcr.io/ennui2342/eclipse-mosquitto:2.1.2-patched
# with imagePullPolicy: Never.
FROM eclipse-mosquitto:2.1.2-alpine
RUN apk update && apk upgrade --no-cache
