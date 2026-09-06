# Frozen-rebuild patch of tailscale/k8s-operator (the Tailscale Kubernetes
# operator, deployed via the tailscale-operator Helm chart — image overridden
# through HelmRelease values `operatorConfig.image`).
#
# Base: v1.98.9 — the newest release in the 1.98.x line this repo's HelmRelease
# pins (`tailscale/helmrelease.yaml`, chart version "1.98.x"). The next
# published line is 1.102.x, which is a 4-minor version jump AND still ships
# the same vulnerable openssl (verified: v1.102.3's Alpine 3.22.5 base also
# carries libcrypto3/libssl3 3.5.7-r0), so it is neither an in-scope upgrade
# nor a fix. This is a pure same-tag OS-package patch.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.22/main repo; v1.98.9's image was baked before
# that and still ships 3.5.7-r0 (verified via `apk list --installed` in the
# base image, and confirmed against https://secdb.alpinelinux.org/v3.22/main.json
# which lists CVE-2026-14456 fixed in openssl 3.5.8-r0). A same-base
# `apk upgrade` on Alpine 3.22.5 bumps libcrypto3 + libssl3 3.5.7-r0 -> 3.5.8-r0
# (verified in the built image) — the operator binary (/usr/local/bin/operator)
# and entrypoint are untouched, pure OS-package patch-level bump, no config or
# behaviour change.
#
# Same CVE-2026-14456 and same frozen-rebuild pattern as the six Flux
# controller forks (helm/kustomize/source/notification/image-reflector/
# image-automation-controller). Rebuild + repush with a new base + tag suffix
# whenever the HelmRelease's pinned chart line moves, or drop this fork
# entirely once an upstream tailscale/k8s-operator image picks up
# openssl >= 3.5.8-r0 (reconcile-scanner tracks this against `upstream_image`
# in trivy/patched-images.yaml).
FROM tailscale/k8s-operator:v1.98.9
USER root
RUN apk update && apk upgrade --no-cache
