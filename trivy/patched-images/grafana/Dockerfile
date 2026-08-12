# Patched 2026-08-12 — grafana/grafana:11.6.16 is the newest tag on the
# 11.6.x line (confirmed via Docker Hub tag listing; grafana has moved on to
# 12.x/13.x, which would be a major-version jump requiring a deliberate,
# reviewed pass — see CLAUDE.md's Gate A). No grafana version change here.
#
# The image's Alpine 3.24.1 base was carrying c-ares 1.34.6-r0 and
# curl/libcurl 8.20.0-r1, both with fixes already published in the same
# Alpine 3.24 main/community repos (c-ares 1.34.8-r0, curl/libcurl 8.21.0-r0)
# — a same-base-version apk upgrade closes all 9 HIGH CVEs
# (CVE-2026-33630, CVE-2026-11352, CVE-2026-11586, CVE-2026-12064,
# CVE-2026-8286, CVE-2026-8458, CVE-2026-8925, CVE-2026-8927,
# CVE-2026-9547) without touching the grafana binary itself. Verified via
# local trivy 0.73.0 scan: alpine/os-pkgs layer 0 CRITICAL + 0 HIGH after
# this patch (target image reports "(alpine 3.24.1)" with 0 vulnerabilities).
#
# Base image runs as uid 472 (non-root) by default — apk requires root, so
# switch back to 472 afterward to preserve the original runtime UID.
#
# Residual (unresolved by this patch, same class as every other
# frozen-rebuild entry in patched-images.yaml): 1 CRITICAL
# (github.com/getkin/kin-openapi GHSA-r277-6w6q-xmqw, fixed 0.144.0) + 6
# HIGH (grafana/tempo CVE-2026-21728/CVE-2026-28377, prometheus/prometheus
# CVE-2026-42151, golang.org/x/text CVE-2026-56852, google.golang.org/grpc
# GHSA-hrxh-6v49-42gf, stdlib CVE-2026-39822 x3 across the three Go
# binaries) — all Go module/stdlib deps baked into the grafana/grafana-cli/
# grafana-server binaries, not Alpine OS packages, out of scope for this
# apk-upgrade patch strategy.
FROM grafana/grafana:11.6.16
USER root
RUN apk update && apk upgrade --no-cache
USER 472
