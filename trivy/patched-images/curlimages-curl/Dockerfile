# Patched 2026-10-26 (tm 26a7e093) — curlimages/curl is used only as
# grafana's downloadDashboardsImage initContainer (monitoring/Deployment/
# kube-prometheus-stack-grafana, container "download-dashboards"), which
# runs grafana's download_dashboards.sh: a plain `curl -skf ... | sed ... >
# file` HTTPS GET of two community dashboard JSONs from grafana.com.
#
# Base bumped 8.22.0 -> 8.23.0 (Alpine 3.24.1 -> 3.24.2). curl 8.23.0's
# breaking changes — SMB support dropped, and the tool's --no-clobber
# suffix naming changed — don't apply to that script (no SMB, no
# --no-clobber/-O usage). Upstream 8.23.0 already resolves CVE-2026-58050
# (libssh2 1.11.1-r4) but still ships brotli-libs 1.2.0-r1, not the fixed
# 1.2.1-r0 for CVE-2026-111497 (trivy, --ignore-unfixed: 1 HIGH). The fix
# is already published in the same Alpine 3.24 repos, so a same-base apk
# upgrade closes it (brotli-libs 1.2.1-r0, plus c-ares 1.34.9-r0, musl
# 1.2.6-r3, alpine-release 3.24.3-r0 — no other changes).
#
# History: an earlier fork (8.21.0-patched, c-ares gap) existed 2026-08-13
# to 2026-09-12 and was dropped when plain 8.22.0 scanned clean — see git
# history.
#
# Base image's default user is curl_user (uid 100, gid 101) — apk requires
# root, so switch back afterward to preserve the original runtime identity.
# (The grafana pod's securityContext runAsUser 472 overrides it anyway.)
FROM curlimages/curl:8.23.0
USER root
RUN apk update && apk upgrade --no-cache
USER curl_user
