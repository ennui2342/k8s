# Rebased 2026-11-24 (reconcile-scanner tm 1b3337d6) from the 1.30.4 fork onto upstream FreshRSS
# 1.31.0 (2026-11-23, multi-arch release): tag 1.31.0-patched-20261124. The reconcile task named
# freshrss/freshrss:9536 as the target, but that's an amd64-only PR-preview tag (not a valid base
# on this arm64 cluster, see history); 1.31.0 shipped the same morning and supersedes it.
# 1.31.0 base: Debian 13.7, PHP 8.4.28, Apache 2.4.71; already ships libbrotli1 1.1.0-2+deb13u1
# (the 1.30.4 fork's reason) and the PHP 8.4.28 fixes. Breaking changes checked: PHP 8.2+
# minimum (n/a, 8.4.28); bcrypt challenge login replaced by direct server-side compare against
# the stored bcrypt hash (#9358: existing hashes keep working, verified by a real form login on a
# copy of the live data); SimplePie drops local-file feeds (all 88 feeds are http(s)). Favicon
# cache keys are now keyed hashes (#9518), so the first actualize re-fetches every favicon once.
# Verified on a copy of the real data: login, main/config/extension/queries/stats pages,
# WallabagButton loaded, forced full actualize (86 OK, same 2 feeds in error as 1.30.4, 0 blocked).
# The one remaining HIGH fixable CVE in upstream 1.31.0's Debian 13.7 base:
#   zlib1g   1:1.3.dfsg+really1.3.1-1+b1 -> 1:1.3.dfsg+really1.3.1-1+deb13u1   (CVE-2026-85091)
# Plain trixie-security dist-upgrade of already-installed packages.
# Rebuild: docker build --pull --no-cache --platform linux/arm64 \
#   -t 192.168.0.8:30500/freshrss:1.31.0-patched-$(date +%Y%m%d) . && docker push <that tag>
#
# History: 2026-08-07 first forked 1.29.1 (2 CRITICAL + 17 HIGH Debian 13.5 CVEs); 2026-08-18
# attempted rebase onto freshrss/freshrss:8400 reverted (amd64-only PR-preview image; use only
# multi-arch release or :edge tags, check `docker buildx imagetools inspect`); 2026-10-24 rebuilt
# 1.29.1 for PHP 8.4.27, then rebased onto 1.30.4 (tm 410d7741, libbrotli1 CVE-2026-111497).
FROM freshrss/freshrss:1.31.0
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
