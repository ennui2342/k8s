# Rebased 2026-10-24 (tm 410d7741) from the 1.29.1 fork onto upstream FreshRSS 1.30.4: tag
# 1.30.4-patched-20261024. 1.30.4 (2026-10-21) is the first upstream release shipping the
# PHP2Shell fix (CVE-2026-109618/-109619; Debian 13.7, PHP 8.4.27-1~deb13u1, Apache 2.4.69) and
# carries the 1.30.x security fixes. Breaking change checked: #8400's local-network default-deny
# lives only in app/Utils/httpUtil.php + SimplePie, none of this instance's 89 feeds resolve to
# a private IP, and the WallabagButton extension uses its own curl_init() (unaffected). Verified
# on a copy of the real data: full actualize, same 2 feeds in error as on 1.29.1, 0 blocked.
# The one remaining HIGH fixable CVE in upstream 1.30.4's Debian 13.7 base:
#   libbrotli1   1.1.0-2+b7 -> 1.1.0-2+deb13u1   (CVE-2026-111497)
# Plain trixie-security dist-upgrade of already-installed packages.
# Rebuild: docker build --pull --no-cache --platform linux/arm64 \
#   -t 192.168.0.8:30500/freshrss:1.30.4-patched-$(date +%Y%m%d) . && docker push <that tag>
#
# History: 2026-08-07 first forked 1.29.1 (2 CRITICAL + 17 HIGH Debian 13.5 CVEs); 2026-08-18
# attempted rebase onto freshrss/freshrss:8400 reverted (amd64-only PR-preview image; use only
# multi-arch release or :edge tags, check `docker buildx imagetools inspect`); 2026-10-24 rebuilt
# 1.29.1 for PHP 8.4.27, then rebased here.
FROM freshrss/freshrss:1.30.4
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
