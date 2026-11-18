# Patched 2026-11-18 (tm ce5b697e) — curlimages/curl is used only as
# grafana's downloadDashboardsImage initContainer (monitoring/Deployment/
# kube-prometheus-stack-grafana, container "download-dashboards"), which
# runs grafana's download_dashboards.sh: a plain `curl -skf ... | sed ... >
# file` HTTPS GET of two community dashboard JSONs from grafana.com.
#
# curlimages/curl:8.23.0 (Alpine 3.24.3, re-published 2026-10-28) is still
# the newest upstream tag, and ships krb5/krb5-libs 1.22.2-r1 — 16 HIGH
# fixable CVEs (MIT krb5 KDC/kadmind DoS batch, CVE-2026-107364,
# CVE-2026-112315..112323, ...), fixed in krb5 1.22.3-r0. The fix is
# already published in the same Alpine 3.24 repos, so a same-base apk
# upgrade closes it (krb5/krb5-libs 1.22.3-r0, plus zlib 1.4-r0,
# apk-tools/libapk 3.0.9-r0, alpine-release 3.24.4-r0 — no other changes).
# No curl version change, so no curl breaking changes to assess. The
# KDC/kadmind CVEs are server-side code paths curl's GSS client never
# exercises anyway, but the scanner flags the package regardless.
#
# History: earlier forks 8.21.0-patched (c-ares gap, 2026-08-13 to
# 2026-09-12) and 8.23.0-patched (brotli gap, 2026-10-26 to 2026-11-04)
# were each dropped once plain upstream scanned clean — see git history.
# This round uses a dated tag (8.23.0-patched-YYYYMMDD) so it can't
# silently overwrite the earlier 8.23.0-patched in the registry.
#
# Base image's default user is curl_user (uid 100, gid 101) — apk requires
# root, so switch back afterward to preserve the original runtime identity.
# (The grafana pod's securityContext runAsUser 472 overrides it anyway.)
FROM curlimages/curl:8.23.0
USER root
RUN apk update && apk upgrade --no-cache
USER curl_user
