# Frozen-rebuild patch of aquasec/trivy — the scanner image the
# monitoring/cve-scanner CronJob itself runs (the `scan` and `reconcile`
# initContainers in trivy/trivy.yaml). A CVE scanner flagging its own image
# is still a real finding: it runs privileged-ish with a cluster-reader
# ServiceAccount and pulls arbitrary content over TLS from every registry in
# the fleet.
#
# Base: 0.74.0 — the tag already running in this cluster AND the newest
# upstream release (Docker Hub: 0.74.0 published 2026-08-14, same digest as
# `latest`; only `canary` is newer). No version bump possible, this is a
# same-tag OS-package patch.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.24/main repo (confirmed against
# https://secdb.alpinelinux.org/v3.24/main.json — 3.5.8-r0 lists
# CVE-2026-14456 plus 9 more openssl CVEs). aquasec/trivy:0.74.0's Alpine
# 3.24.1 base was baked before that and still ships 3.5.7-r0 (verified via
# `apk list --installed` in the base image). A same-base `apk upgrade` on
# Alpine 3.24.1 bumps libcrypto3 + libssl3 3.5.7-r0 -> 3.5.8-r0 (and, as a
# side effect, libcurl 8.21.0-r0 -> 8.22.0-r0, libexpat 2.8.2-r0 -> 2.8.4-r0,
# pcre2 10.47-r1 -> 10.48-r0, apk-tools/libapk 3.0.6-r0 -> 3.0.8-r0) — the
# trivy binary (/usr/local/bin/trivy) and `trivy` entrypoint are untouched,
# pure OS-package patch-level bump, no config or behaviour change.
#
# Same CVE-2026-14456 and same frozen-rebuild pattern as the six Flux
# controller forks and the two Tailscale forks (all hit by the same openssl
# CVE in the same Alpine 3.22-3.24 generation of base images). Rebuild +
# repush with a new base + tag suffix whenever aquasec ships a newer trivy
# release, or drop this fork entirely once an upstream aquasec/trivy image
# picks up openssl >= 3.5.8-r0 (reconcile-scanner tracks this against
# `upstream_image` in trivy/patched-images.yaml).
FROM aquasec/trivy:0.74.0
RUN apk update && apk upgrade --no-cache
