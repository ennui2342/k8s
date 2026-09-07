# Frozen-rebuild patch of tailscale/tailscale — the proxy image the Tailscale
# Kubernetes operator injects into every ingress/egress/Connector/Funnel proxy
# StatefulSet it creates (ts-freshrss-ts-*, ts-k8s-connector-*, ts-linkding-ts-*,
# ts-opsimath-ts-*, ts-taskmgt-ts-*, ts-wallabag-ts-*, ts-webdav-funnel-*).
# Image is overridden through the tailscale-operator Helm chart values
# `proxyConfig.image.repository` / `proxyConfig.image.tag`
# (tailscale/helmrelease.yaml), which the chart renders into the operator's
# PROXY_IMAGE env var.
#
# Base: v1.98.9 — kept in lockstep with the k8s-operator fork
# (trivy/patched-images/k8s-operator/Dockerfile). v1.98.9 is the newest release
# in the 1.98.x chart line this repo's HelmRelease pins. The next published line
# (1.102.x) is a 4-minor version jump AND still ships the same vulnerable
# openssl (v1.102.3's Alpine 3.22.5 base also carries libcrypto3/libssl3
# 3.5.7-r0), so it is neither an in-scope upgrade nor a fix. Pure same-tag
# OS-package patch.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.22/main repo; v1.98.9's image was baked before
# that and still ships 3.5.7-r0 (verified via `apk policy` in the base image:
# installed 3.5.7-r0, candidate 3.5.8-r0 from https://dl-cdn.alpinelinux.org/alpine/v3.22/main).
# A same-base `apk upgrade` on Alpine 3.22.5 bumps libcrypto3 + libssl3
# 3.5.7-r0 -> 3.5.8-r0 (verified in the built image) — the tailscale/tailscaled
# binaries (/usr/local/bin/{containerboot,tailscale,tailscaled}) and the
# containerboot entrypoint are untouched, pure OS-package patch-level bump, no
# config or behaviour change.
#
# Same CVE-2026-14456, same Alpine 3.22.5 base and same frozen-rebuild pattern
# as the k8s-operator fork and the six Flux controller forks. Rebuild + repush
# with a new base + tag suffix whenever the HelmRelease's pinned chart line
# moves, or drop this fork entirely once an upstream tailscale/tailscale image
# picks up openssl >= 3.5.8-r0 (reconcile-scanner tracks this against
# `upstream_image` in trivy/patched-images.yaml).
FROM tailscale/tailscale:v1.98.9
USER root
RUN apk update && apk upgrade --no-cache
