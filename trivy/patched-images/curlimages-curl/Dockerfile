# Patched 2026-08-13 — curlimages/curl:8.20.0 is used as grafana's
# downloadDashboardsImage initContainer (monitoring/Deployment/
# kube-prometheus-stack-grafana, container "download-dashboards"), which
# runs a simple `curl -skf ... | sed ... > file` script
# (grafana's download_dashboards.sh) to fetch the two community dashboard
# JSONs from grafana.com at pod start. No auth mechanisms beyond plain
# HTTPS GET are used, so curl 8.21.0's flagged upcoming removals (NTLM,
# SMB, TLS-SRP, CURLAUTH_DIGEST_IE) don't apply here.
#
# Bumping the base tag to curlimages/curl:8.21.0 (Alpine 3.24.1) already
# resolves 4 of 5 HIGH CVEs from the original scan out of the box —
# libcrypto3 lands at 3.5.7-r0 (CVE-2026-45447) and libssh2 at 1.11.1-r3
# (CVE-2026-55199, CVE-2026-55200, CVE-2026-7598) match or exceed the
# required fix versions already. The remaining CVE-2026-33630 (c-ares
# use-after-free/double-free, fix 1.34.8-r0) is NOT yet fixed in the
# 8.21.0 tag itself — verified live via `docker run` + `apk info -vv`,
# it still ships c-ares 1.34.6-r0 — but the fix is already published in
# the same Alpine 3.24 repos, so a same-base-version apk upgrade closes
# it (confirmed live: apk upgrade brings c-ares 1.34.6-r0 -> 1.34.8-r0,
# no other package changes). Same pattern as this repo's grafana image
# patch (trivy/patched-images/grafana/Dockerfile), which hit the
# identical c-ares gap on the same Alpine 3.24.1 base one day earlier.
#
# Base image's default user is curl_user (uid 100, gid 101) — apk
# requires root, so switch back afterward to preserve the original
# runtime identity. In practice the grafana Deployment's pod-level
# securityContext (runAsUser/runAsGroup: 472, fsGroup: 472) overrides
# this anyway, but keep it correct for any other consumer of this image.
FROM curlimages/curl:8.21.0
USER root
RUN apk update && apk upgrade --no-cache
USER curl_user
