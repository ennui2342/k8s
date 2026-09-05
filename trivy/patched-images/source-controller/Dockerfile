# Frozen-rebuild patch of ghcr.io/fluxcd/source-controller.
#
# Base: v1.9.4 (the tag already running in this cluster, and the newest
# upstream release) — no version bump, this is a same-tag OS-package patch.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.9.4's image was baked before
# that and still ships 3.5.7-r0 (verified via `apk list --installed` in the
# base image). A same-base `apk upgrade` on Alpine 3.23.5 bumps libcrypto3 +
# libssl3 3.5.7-r0 -> 3.5.8-r0 (verified in the built image) — the
# source-controller binary and entrypoint are untouched, pure OS-package
# patch-level bump, no config or behaviour change.
#
# Same frozen-rebuild pattern as the helm-controller / kustomize-controller /
# image-reflector-controller / image-automation-controller / notification-
# controller forks (all hit by the same CVE-2026-14456 in the same Alpine
# 3.23.5 generation of Flux controller base images). Rebuild + repush with a
# new base + tag suffix whenever fluxcd ships a newer source-controller
# release, or drop this fork entirely once an upstream image picks up
# openssl >= 3.5.8-r0 (reconcile-scanner tracks this).
FROM ghcr.io/fluxcd/source-controller:v1.9.4
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
