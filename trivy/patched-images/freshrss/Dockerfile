# Patch rebased 2026-08-18 (task 11b88cee-46b3-4b1c-9daf-238946c72694), replacing the
# 2026-08-07 patch that was built on freshrss/freshrss:1.29.1.
#
# freshrss/freshrss:8400 is an "edge" dev build (FRESHRSS_VERSION = 1.29.2-dev, built from
# FreshRSS/FreshRSS PR #8400) — newer than 1.29.1 but not itself a tagged release. It already
# improves the CVE picture over 1.29.1 (28 CRIT + 32 HIGH vs 1.29.1's 28 CRIT + 50 HIGH at
# reconcile-scan time) but wasn't fully clean before this dist-upgrade.
#
# Breaking change reviewed: PR #8400 itself ("Disallow access to local networks such as
# 127.0.0.1 by default") only wraps FreshRSS's own feed-fetch code paths (FreshRSS_http_Util /
# SimplePieFetch, used by feedController/subscriptionController/Feed::pubSubHubbubSubscribe) —
# confirmed via the PR diff (github.com/FreshRSS/FreshRSS/pull/8400.diff). It does not intercept
# arbitrary curl_init()/curl_exec() calls made by third-party extensions. Checked both places
# this instance could be affected:
#   - Subscribed feeds: queried live from data/users/ennui2342/db.sqlite's feed table — every
#     URL is a public external host, none point at 127.0.0.1/private ranges.
#   - Extensions: only WallabagButton is installed, and its Controllers/wallabagButtonController.php
#     calls curl_init/curl_exec directly against the user-configured wallabag_instance_url (an
#     internal hostname, later.k8s.ecafe.org) — bypassing FreshRSS's own httpGet/SimplePieFetch
#     entirely, so the new default-deny doesn't apply to it either way.
# No config edit (INTERNAL_HOST_ALLOWLIST) needed as a result.
#
# apt dist-upgrade against the 8400 base resolves the residual CVEs found in the plain image
# (trivy 0.74.0 --ignore-unfixed CRITICAL,HIGH scan of freshrss/freshrss:8400 pre-patch: 2
# CRITICAL php8.4/php8.4-* ext-pgsql SQLi + bccomp() OOB write (CVE-2026-17543, CVE-2026-17544)
# — same php8.4 8.4.21-1~deb13u1 build as 1.29.1 shipped, evidently not yet rebuilt against a
# newer php8.4 package — plus 1 HIGH util-linux/libblkid CVE-2026-53615, fixed
# 2.41.5-0+deb13u1). Verified post-patch: 0 CRITICAL + 0 HIGH fixable remaining
# (trivy 0.74.0, --ignore-unfixed).
FROM freshrss/freshrss:8400
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
