# Frozen-rebuild patch of tailscale/tailscale — the proxy image the Tailscale
# Kubernetes operator injects into every ingress/egress/Connector/Funnel proxy
# StatefulSet it creates (ts-freshrss-ts-*, ts-k8s-connector-*, ts-linkding-ts-*,
# ts-opsimath-ts-*, ts-taskmgt-ts-*, ts-wallabag-ts-*, ts-webdav-funnel-*).
# Image is overridden through the tailscale-operator Helm chart values
# `proxyConfig.image.repository` / `proxyConfig.image.tag`
# (tailscale/helmrelease.yaml), which the chart renders into the operator's
# PROXY_IMAGE env var. This is configured independently of the operator's own
# chart version pin (`tailscale/helmrelease.yaml`'s `chart.spec.version:
# "1.98.x"`, unchanged by this rebase) and independently of the sibling
# tailscale/k8s-operator fork — the operator happily injects a newer client
# than its own chart line, so there's no lockstep requirement here the way
# there is when the *chart line itself* moves.
#
# Base: v1.102.3 (rebased 2026-09-14 from the earlier v1.98.9-patched fork).
# reconcile-scanner found plain tailscale/tailscale:v1.102 improves on
# v1.98.9's CVE count but still doesn't fully resolve — same underlying
# OS-level CVE-2026-14456 (HIGH, openssl DoS via unbounded memory growth in
# the QUIC server) remains, since v1.102.3's Alpine 3.22.5 base still ships
# libssl3/libcrypto3 3.5.7-r0 (verified via `apk policy` in the base image:
# installed 3.5.7-r0, candidate 3.5.8-r0 from
# https://dl-cdn.alpinelinux.org/alpine/v3.22/main — the fixed package was
# published after v1.102.3's image was baked).
#
# Changelog v1.98.9 -> v1.102 reviewed (tailscale.com/changelog): the only
# breaking change in range is deprecated legacy 4via6 MagicDNS name formats
# being removed (v1.102.1) — this repo's tailscale manifests (tailscale/,
# */tailscale-ingress.yaml) never reference 4via6 naming at all (verified via
# repo-wide grep), so it doesn't apply. Everything else in range (PeerRelays
# CRD, workload-identity federation, TS_BOOT_TIMEOUT env var, ACME timeout,
# various security fixes TS-2026-*) is additive/opt-in, not used by this
# repo's plain ingress/egress/Connector/Funnel proxy usage. `tailscale
# version` confirms 1.102.3 post-build; binaries are byte-identical in size
# to the unpatched base (containerboot/tailscale/tailscaled untouched).
#
# Same-base `apk upgrade` on Alpine 3.22.5 bumps libcrypto3 + libssl3
# 3.5.7-r0 -> 3.5.8-r0 (verified in the built image: alpine layer scans 0
# vulnerabilities post-patch, was 2 HIGH pre-patch) — the
# tailscale/tailscaled/containerboot binaries and the containerboot
# entrypoint are untouched, pure OS-package patch-level bump, no config or
# behaviour change.
#
# Residual (not fixed by this patch — baked into the Go binaries themselves,
# not Alpine OS packages, so out of scope for an apk-upgrade patch strategy):
# CVE-2026-56854 (HIGH, golang.org/x/crypto/ssh auth bypass via unenforced
# source-address restrictions) in all three binaries, plus CVE-2026-46602 and
# CVE-2026-46603 (HIGH, golang.org/x/image TIFF/VP8L decoder DoS) in the
# tailscale CLI binary. 5 HIGH findings total, 0 CRITICAL, verified via local
# trivy 0.74.0 scan (--ignore-unfixed --severity CRITICAL,HIGH — no
# --pkg-types filter, so gobinary findings are included).
#
# Rebuild + repush with a new base + tag suffix whenever a newer upstream
# release ships openssl >= 3.5.8-r0 AND the golang.org/x/crypto and
# golang.org/x/image module versions above are bumped past their fixed
# versions, or drop this fork entirely at that point (reconcile-scanner
# tracks this against `upstream_image` in trivy/patched-images.yaml).
FROM tailscale/tailscale:v1.102.3
USER root
RUN apk update && apk upgrade --no-cache
