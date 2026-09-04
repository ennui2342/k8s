# Frozen-rebuild patch of ghcr.io/fluxcd/image-reflector-controller.
#
# Base: v1.2.3 — the exact tag the CVE scanner flagged and the tag this repo
# already pins in flux-system/gotk-components.yaml. Kept on the v1.2.3 base
# rather than rebasing onto a newer release (v1.2.4/v1.2.5 exist) to keep this
# controller in lockstep with its sibling image-automation-controller, which is
# frozen at v1.2.3-patched for this same CVE (commit 659279d) because
# image-automation-controller v1.2.4 ships an ImageUpdateAutomation CRD schema
# change requiring a hand-spliced CRD update in the Flux bootstrap manifest.
# image-reflector-controller's own v1.2.4/v1.2.5 changelogs are fluxcd/pkg
# dependency bumps only (ECR host-detection alignment, k8s client libs to
# 1.36.4) with no CRD schema change and no breaking changes — but rebasing this
# controller alone still would not fix the CVE: v1.2.5's image also ships
# openssl 3.5.7-r0 (verified via `apk list --installed`), so an apk-upgrade
# layer is required regardless. Keeping both image-* controllers on the same
# v1.2.3 base is the consistent, lowest-risk choice.
#
# Resolves CVE-2026-14456 (HIGH) — OpenSSL DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.2.3's image was baked before that
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
FROM ghcr.io/fluxcd/image-reflector-controller:v1.2.3
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
