# Frozen-rebuild patch of ghcr.io/fluxcd/image-automation-controller.
#
# Base: v1.2.5 — rebased 2026-09-13 from the earlier v1.2.3-patched fork.
# v1.2.4 (2026-08-07) shipped an ImageUpdateAutomation CRD schema change (an
# added OpenAPI `pattern` regex on `.spec.git.push.refspec`, rejecting
# deletion refspecs and `+`-prefixed force-update refspecs — see
# https://github.com/fluxcd/image-automation-controller/blob/v1.2.5/CHANGELOG.md).
# Confirmed via a direct diff of the v1.2.3 vs v1.2.5 CRD YAML
# (config/crd/bases/image.toolkit.fluxcd.io_imageupdateautomations.yaml):
# the ONLY change is that added `pattern:` line plus its doc-comment — no new
# field, no removed field, no type change. It's admission-time validation
# only; the Go API types are unchanged. This repo's ImageUpdateAutomations
# (opsimath, taskmgt — flux-system/opsimath-image-automation.yaml,
# flux-system/taskmgt-image-automation.yaml) both use plain
# `.spec.git.push.branch`, never `.spec.git.push.refspec`, so the v1.2.5
# binary runs safely against the existing (unmigrated) CRD already installed
# in this cluster — hand-splicing the regenerated CRD into
# flux-system/gotk-components.yaml is NOT needed. v1.2.5 itself is
# fluxcd/pkg dependency bumps only (Kubernetes client libs to 1.36.4), no
# further schema change on top of v1.2.4.
#
# Resolves CVE-2026-14456 (HIGH) — OpenSSL DoS via unbounded memory growth in
# the QUIC server. v1.2.5's Alpine 3.23.5 base still ships libssl3/libcrypto3
# 3.5.7-r0 (verified via `apk list --installed`) — the fixed 3.5.8-r0 package
# was published to the alpine v3.23/main repo after v1.2.5's image was baked.
# A same-base `apk upgrade` bumps only libcrypto3 + libssl3 3.5.7-r0 ->
# 3.5.8-r0 (plus apk-tools/libapk 3.0.6-r0 -> 3.0.8-r0) — the
# image-automation-controller binary and entrypoint are untouched beyond the
# v1.2.5 rebase itself, no config or behaviour change from that rebase.
#
# Same frozen-rebuild pattern as the helm-controller / kustomize-controller /
# image-reflector-controller / notification-controller / source-controller
# forks. Rebuild + repush with a new tag whenever fluxcd ships a newer
# image-automation-controller release, or drop this fork entirely once an
# upstream image picks up openssl >= 3.5.8-r0 (reconcile-scanner tracks this
# via upstream_image in trivy/patched-images.yaml).
FROM ghcr.io/fluxcd/image-automation-controller:v1.2.5
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
