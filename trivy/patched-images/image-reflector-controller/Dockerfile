# Frozen-rebuild patch of ghcr.io/fluxcd/image-reflector-controller.
#
# Base: v1.2.5 — rebased 2026-09-12 from the original v1.2.3 base (was kept in
# lockstep with sibling image-automation-controller, itself frozen at
# v1.2.3-patched because ITS v1.2.4 ships an ImageUpdateAutomation CRD schema
# change). image-reflector-controller has no such blocker: v1.2.4/v1.2.5
# changelogs are fluxcd/pkg dependency bumps only (v1.2.4: ECR host-detection
# alignment #926; v1.2.5: k8s client libs to 1.36.4 #934/#935) — confirmed via
# the official CHANGELOG.md, the released CRD bundle is byte-identical between
# v1.2.3 and v1.2.5, and the released deployment.yaml differs only in the image
# tag. No CRD schema change, no breaking change, no config/arg/RBAC change.
# image-automation-controller stays frozen at v1.2.3-patched separately; the
# two no longer need to move in lockstep since the blocker was specific to
# image-automation-controller's own CRD.
#
# Rebasing the base image alone does not resolve the CVE: v1.2.5's image still
# ships openssl 3.5.7-r0 (verified via `apk list --installed`), same as
# v1.2.3's — so the apk-upgrade layer below is still required regardless of
# base tag.
#
# Resolves CVE-2026-14456 (HIGH) — OpenSSL DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.2.5's image was baked before that
# and still ships 3.5.7-r0 (verified via `apk list --installed` in the base).
# A same-base `apk upgrade` on Alpine 3.23.5 bumps libcrypto3 + libssl3
# 3.5.7-r0 -> 3.5.8-r0 plus apk-tools/libapk 3.0.6-r0 -> 3.0.8-r0 (verified in
# the built image) — the image-reflector-controller binary and entrypoint are
# untouched, pure OS-package patch-level bump, no config or behaviour change.
#
# Same frozen-rebuild pattern as the image-automation-controller /
# helm-controller / kustomize-controller / syncthing forks. Rebuild + repush
# with a new tag whenever fluxcd ships a newer image-reflector-controller
# release, or drop this fork entirely once an upstream image picks up
# openssl >= 3.5.8-r0 (reconcile-scanner tracks this).
FROM ghcr.io/fluxcd/image-reflector-controller:v1.2.5
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
