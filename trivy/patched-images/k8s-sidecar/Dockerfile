# Frozen-rebuild patch of docker.io/kiwigrid/k8s-sidecar.
#
# Base: 2.11.2 (built 2026-09-04) — the newest upstream tag (confirmed via
# Docker Hub tags API ordered by last_updated). The digest currently deployed
# (sha256:2912be00...) matches the digest the registry serves for this tag
# today, so kiwigrid hasn't rebuilt it either — a plain tag bump can't pick up
# the fix.
#
# Resolves 6 HIGH util-linux CVEs (CVE-2026-53612, CVE-2026-53613,
# CVE-2026-53614, CVE-2026-76642, CVE-2026-78408, CVE-2026-78410). Note:
# util-linux itself (mount/nsenter binaries) is NOT installed in this image —
# verified via `apk info`/`/lib/apk/db/installed` in the base image, the only
# installed package from util-linux's origin is the `libuuid` shared-library
# subpackage (pulled in transitively, no mount/nsenter binaries present).
# Alpine's whole util-linux source package (including the libuuid
# subpackage) shares one version number, and the v3.22/main repo already
# publishes libuuid 2.41.6-r1, which covers all six advisories (fixed at
# 2.41.6-r0/-r1). Pure OS-package patch-level bump via `apk upgrade` on the
# same Alpine 3.22.4 base — the k8s-sidecar Python app and entrypoint are
# untouched, no config or behaviour change. Verified in the built image:
# libuuid 2.41-r9 -> 2.41.6-r1, alpine-release still 3.22.x line, entrypoint
# unchanged (`python -u -m sidecar`).
#
# Base image runs as uid 65534:65534 (nobody, non-root, per the upstream
# Dockerfile's own MustRunAsNonRoot comment) — apk requires root, so switch
# back afterward to preserve the original runtime UID.
FROM docker.io/kiwigrid/k8s-sidecar:2.11.2
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
