# Rebased 2026-08-13 onto upstream grafana/promtail:3.6.11 (was 3.5.1) — tm
# task 40c8fcc3, CVE-2025-68973 (gpgv) + CVE-2026-45447 (openssl) both HIGH.
#
# Promtail itself is fully EOL upstream (deprecated in favor of Grafana
# Alloy; commercial support ended 2026-02-28, code merged into Alloy, and
# grafana/promtail:3.6.11 published 2026-05-13 is the last image Grafana
# will ever publish for it — the grafana/helm-charts `promtail` chart hasn't
# had a release since 6.17.1 (2025-10-31, appVersion still 3.5.1), so this
# repo's HelmRelease stays pinned to chart "6.17.x" and overrides
# `values.image.{registry,repository,tag}` to point at this locally-rebuilt
# image instead of bumping the chart). 3.5.1 -> 3.6.11 is a promtail-binary
# version bump, not just an OS-package refresh, but promtail's own code has
# had no functional development since its Loki-3.0-era deprecation — every
# 3.5.x/3.6.x release in this range is a maintenance/security/dependency
# bump only (confirmed via Loki v3.5/v3.6 release notes: no promtail-config
# breaking changes listed, only chart/Loki-server-side items - Loki UI
# plugin move, BoltDB deprecation, OTel tracing switch - none of which touch
# promtail). This deployment's config is minimal (chart defaults plus a
# single `clients[0].url`), so the version bump carries negligible risk.
#
# Verified via local trivy 0.70.0 scan (--ignore-unfixed, HIGH+CRITICAL):
# plain 3.5.1 was 40 HIGH/CRITICAL fixable (incl. gpgv 2.4.4-2ubuntu17.2 and
# openssl/libssl3t64 3.0.13-0ubuntu3.5, both short of the fixed versions).
# Plain 3.6.11 already resolves the gpgv CVE (Ubuntu picked up
# 2.4.4-2ubuntu17.4 in a later noble-security sync than promtail's last
# rebuild needed) but still ships openssl/libssl3t64 3.0.13-0ubuntu3.9,
# short of the fixed 3.0.13-0ubuntu3.11 - promtail will never get another
# upstream rebuild to pick that up, so the apt upgrade below closes it.
FROM grafana/promtail:3.6.11
USER root
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
