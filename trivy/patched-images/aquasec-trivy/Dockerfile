# Best-effort reconstruction of the 2026-05-30 patch (commit 1b6892d).
# Resolves 1 CRITICAL + 7 HIGH CVEs: openssl 3.5.5-r0->3.5.6-r0, musl
# 1.2.5-r21->r23, nghttp2 1.68.0-r0->1.69.0-r0, zlib 1.3.1-r2->1.3.2-r0.
# This is the image the trivy CronJob itself uses to scan the cluster — take
# care not to leave the fleet without a working scanner mid-rebuild.
FROM aquasec/trivy:0.70.0
USER root
RUN apk update && apk upgrade --no-cache
