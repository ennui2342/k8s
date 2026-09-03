# Frozen-rebuild patch of ghcr.io/fluxcd/helm-controller.
#
# Base: v1.6.4 (released 2026-08-31) — the newest upstream release. Rebased
# from v1.6.3 (the tag the CVE scanner flagged) onto v1.6.4 after reviewing
# the v1.6.3 -> v1.6.4 changelog:
#   - "Validate HelmRelease kubeconfigs" (#1572): kubeconfigs referencing
#     local files are now rejected; credentials/certs must be embedded inline.
#     Does NOT apply here — no HelmRelease in this repo sets spec.kubeConfig
#     (all Helm releases target the in-cluster API), verified via repo-wide grep.
#   - "Move v1.6 back to upstream helm" (#1565): drops the temporary Flux fork
#     of the Helm SDK, now on upstream Helm v4.2.4. Stays within Helm 4 (v1.6.x
#     was already on the Helm 4 SDK) — not a Helm 3 -> 4 jump. All HelmReleases
#     in this repo use plain chart installs with no post-renderers or custom
#     Helm behaviour, so no impact.
#   - fluxcd/pkg dependency bumps + Kubernetes client libs to 1.36.4 (cluster
#     is k3s v1.32.x — within client-go skew tolerance).
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo; v1.6.4's image was baked before that
# and still ships 3.5.7-r0 (verified via `apk list --installed` in the base).
# A same-base `apk upgrade` on Alpine 3.23.5 bumps only libcrypto3 + libssl3
# 3.5.7-r0 -> 3.5.8-r0 (verified in the built image) — the helm-controller
# binary and entrypoint are untouched, pure OS-package patch-level bump, no
# config or behaviour change.
#
# Rebuild + repush with a new base + tag suffix whenever fluxcd ships a newer
# helm-controller release, or drop this fork entirely once an upstream image
# picks up openssl >= 3.5.8-r0 (reconcile-scanner tracks this).
FROM ghcr.io/fluxcd/helm-controller:v1.6.4
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
