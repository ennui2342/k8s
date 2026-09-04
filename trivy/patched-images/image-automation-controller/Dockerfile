# Frozen-rebuild patch of ghcr.io/fluxcd/image-automation-controller.
#
# Base: v1.2.3 — the exact tag the CVE scanner flagged and the tag this repo
# already pins in flux-system/gotk-components.yaml. NOT rebased onto a newer
# release: v1.2.4 (2026-08-07) ships an ImageUpdateAutomation CRD schema change
# ("must be updated along with the controller" per its changelog) that would
# require hand-splicing the regenerated CRD into the Flux bootstrap manifest —
# out of scope for a routine OS-package CVE patch. The v1.2.4 change itself
# (reject deletion/force-update refspecs in .spec.git.push.refspec) does not
# apply to this repo's ImageUpdateAutomations (opsimath, taskmgt) — both use
# plain .spec.git.push.branch, no refspec — but the CRD-migration mechanics do.
# v1.2.5 is dependency-bumps only. Reconcile-scanner tracks the eventual move
# to a newer release.
#
# Resolves CVE-2026-14456 (HIGH) — OpenSSL DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.2.3's image was baked before that
# and still ships 3.5.7-r0 (verified via `apk list --installed` in the base).
# A same-base `apk upgrade` on Alpine 3.23.5 bumps only libcrypto3 + libssl3
# 3.5.7-r0 -> 3.5.8-r0 (verified in the built image) — the
# image-automation-controller binary and entrypoint are untouched, pure
# OS-package patch-level bump, no config or behaviour change.
#
# Same frozen-rebuild pattern as the helm-controller / kustomize-controller /
# syncthing forks. Rebuild + repush with a new tag whenever fluxcd ships a
# newer image-automation-controller release, or drop this fork entirely once an
# upstream image picks up openssl >= 3.5.8-r0 (reconcile-scanner tracks this).
FROM ghcr.io/fluxcd/image-automation-controller:v1.2.3
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
