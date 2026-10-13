# Frozen-rebuild patch of docker.io/kiwigrid/k8s-sidecar.
#
# Base: 2.14.1 (rebased 2026-10-13 from 2.13.3, per reconcile-scanner task
# baafbf9e). 2.14.x moves to Alpine 3.24.2 / stable Python 3.14.8 (from
# Alpine 3.22.4 / Python 3.15.0b2), which clears the libuuid HIGHs the
# earlier forks existed for. Changelog 2.13.3 -> 2.14.1: 2.14.0 = stable
# Python 3.14 base + charset segfault fix + s390x re-added; 2.14.1 =
# kubernetes client 35 -> 36.0.3 (pulls aiohttp & friends in as required
# deps, but the sidecar still uses only the sync client). Runtime config
# identical: User 65534:65534, WORKDIR /app, ENTRYPOINT `python -u -m
# sidecar`, no env-var/CLI changes.
#
# Upstream 2.14.1 still scans 4 HIGH (trivy 0.75.0, --ignore-unfixed,
# arm64), ALL inside pip's own vendored libraries — msgpack 1.1.2
# (GHSA-6v7p-g79w-8964), urllib3 2.7.0 (CVE-2026-97687/97689) and
# setuptools 70.3.0 (CVE-2025-47273), per pip/_vendor/vendor.txt — in both
# the system pip (/usr/local, pip 26.2.1) and the venv pip (/app/.venv, pip
# 26.1.2). pip 26.2.1 is already the newest release, so an upgrade can't fix
# it. The sidecar never imports or shells out to pip (verified: no
# pip/setuptools/pkg_resources/msgpack references in its modules), so pip is
# simply removed from the runtime image. The app's own urllib3 (2.8.0, in
# the venv's site-packages) is already the fixed version and is untouched.
# `apk upgrade` is kept for any Alpine 3.24 OS-package fixes newer than the
# upstream build.
#
# History: forked 2026-09-18 on 2.11.2 for 6 HIGH util-linux (libuuid)
# CVEs fixed at libuuid 2.41.6-r1 (CVE-2026-53612/53613/53614/76642/78408/
# 78410); rebased 2026-10-09 onto 2.13.3 (still Alpine 3.22.4 / libuuid
# 2.41-r9, same apk-upgrade recipe).
#
# Base image runs as uid 65534:65534 (nobody, non-root) — apk/rm require
# root, so switch back afterward to preserve the original runtime UID.
FROM docker.io/kiwigrid/k8s-sidecar:2.14.1
USER root
RUN apk update && apk upgrade --no-cache \
 && rm -rf /usr/local/lib/python3.14/site-packages/pip \
           /usr/local/lib/python3.14/site-packages/pip-*.dist-info \
           /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.* \
           /app/.venv/lib/python3.14/site-packages/pip \
           /app/.venv/lib/python3.14/site-packages/pip-*.dist-info \
           /app/.venv/bin/pip /app/.venv/bin/pip3 /app/.venv/bin/pip3.*
USER 65534:65534
