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
# Base: v1.104.1 (rebased 2026-10-20 from the v1.102.3-patched fork, tm task
# f98dda28; earlier history: v1.98.9-patched -> v1.102.3-patched 2026-09-14).
# reconcile-scanner found plain tailscale/tailscale:v1.104 improves on
# v1.102.3 (12 HIGH vs 22) but still doesn't fully resolve.
#
# Changelog v1.102.3 -> v1.104.1 reviewed (tailscale.com/changelog): the only
# breaking changes in range are platform-minimum bumps (v1.104 is built with
# Go 1.27: macOS 12 Monterey and iOS 15 dropped) — irrelevant to the Linux
# container proxies. Container image v1.104.1 is "no functional changes;
# library updates only"; Linux client changes are netmap caching for faster
# start-up, single WireGuard batch buffer, IPv6 link-local relay fix, and
# v1.102.5's "container no longer stops tailscaled when it falls behind on
# status updates" fix. Operator-side v1.104.1 changes (PeerRelay, ProxyGroup,
# DNSConfig, `tailscale.com/experimental-forward-cluster-traffic-via-ingress`
# annotation behaviour) don't touch this repo — no ProxyGroup/PeerRelay/
# DNSConfig/ProxyClass resources and no such annotation anywhere (repo-wide
# grep), and the operator itself stays on its own 1.98.x chart line.
# `tailscale version` confirms 1.104.1 post-build; containerboot/tailscale/
# tailscaled are byte-identical in size to the unpatched base.
#
# v1.104.1's Alpine 3.22.6 base already ships libssl3/libcrypto3 3.5.8-r0, so
# the original reason for this fork (CVE-2026-14456) is resolved upstream.
# Same-base `apk upgrade` now bumps libcrypto3+libssl3 3.5.8-r0 -> 3.5.9-r0
# and zlib 1.3.2-r0 -> 1.3.2-r1 (CVE-2026-85091, MEDIUM) — the OS layer scans
# 0 findings at any severity post-patch (was 1 MEDIUM). No CRITICAL/HIGH is
# resolved by the apk layer itself; the fork is kept (rather than dropped for
# plain upstream) so the reconcile-scanner keeps tracking upstream for the
# Go-binary residuals below and files a Revert task once a clean tag ships.
#
# Residual (not fixable by an apk-upgrade — baked into the Go binaries):
# 12 HIGH, 0 CRITICAL, trivy 0.76.0 (--ignore-unfixed --severity
# CRITICAL,HIGH, gobinary included): in each of containerboot/tailscale/
# tailscaled, Go stdlib 1.27.1 CVE-2026-78667, CVE-2026-78669, CVE-2026-97031
# (fixed 1.27.2) and golang.org/x/net v0.59.0 CVE-2026-78669 (fixed 0.60.0).
# Identical count to plain upstream v1.104.1. The previous fork's
# golang.org/x/crypto CVE-2026-56854, golang.org/x/image CVE-2026-46602/46603
# and golang.org/x/text CVE-2026-56851 are all gone in v1.104.1.
#
# Rebuild + repush with a new base + tag suffix when a newer upstream release
# is built with Go >= 1.27.2 and golang.org/x/net >= 0.60.0, or drop this fork
# entirely at that point (reconcile-scanner tracks this against
# `upstream_image` in trivy/patched-images.yaml).
FROM tailscale/tailscale:v1.104.1
USER root
RUN apk update && apk upgrade --no-cache
