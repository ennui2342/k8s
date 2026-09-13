# Rebased 2026-09-13 onto upstream v1.9.5 (was v1.9.4) — upstream itself
# improved from 1 CRITICAL + 18 HIGH (v1.9.4, broader scan) to 1 CRITICAL + 8
# HIGH (v1.9.5) but still isn't fully clean; apk upgrade closes the remaining
# Alpine-base gap. Residual CRITICAL/HIGH after this patch are Go module deps
# baked into the controller binary, out of scope for an apk-upgrade patch —
# same residual class as the other Flux controller forks.
#
# Changelog v1.9.4->v1.9.5 reviewed (official CHANGELOG.md) and confirmed via
# the GitHub compare view (only CHANGELOG.md/go.mod/go.sum/api go.mod/go.sum/
# config/manager/kustomization.yaml changed — no CRD files touched):
#   - Upgrade Helm to 4.2.4, to sync with helm-controller 1.6 which moved
#     back from the Flux fork of Helm to upstream Helm — dependency-only,
#     this repo has no direct Helm SDK usage of its own.
#   - Update fluxcd/pkg dependencies, bringing Kubernetes client libs to
#     1.36.4 — cluster is k3s v1.32.x, within client-go skew tolerance (same
#     call as the other Flux controller forks).
# No CRD field removals, no config/arg/RBAC changes, no other breaking
# changes in this range.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.9.5's image was baked before
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
FROM ghcr.io/fluxcd/source-controller:v1.9.5
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
