# Patch built 2026-07-31 (task e93d4061-502c-4132-8775-82ef55c3e5a7).
# Rebased 2026-08-11 (task 54fb10ac-2d5c-4373-8d21-725e614135c7) from
# sissbruecker/linkding:1.45.0 onto sissbruecker/linkding:1.46.0 — plain 1.46.0 upstream
# improved to 0 CRITICAL + 1 HIGH (from 1.45.0's 10 CRITICAL + 521 HIGH) but wasn't fully
# clean, so the apt dist-upgrade patch strategy continues on the newer base. Changelog
# 1.45.0->1.46.0 reviewed (CHANGELOG.md + GitHub compare): no breaking changes, only new
# features (bundle filtering, tag deletion API, sort-by-modified, RSS feed filtering,
# session duration config) and bug/dependency fixes — nothing touches this deployment's
# LD_CSRF_TRUSTED_ORIGINS/LD_SUPERUSER_* env vars or requires a config edit.
# Rebased again 2026-08-25 (task 697c57ea-f21e-45b5-93ca-acd2f22cede1) from
# sissbruecker/linkding:1.46.0 onto sissbruecker/linkding:1.46.2 — plain 1.46.2 upstream
# improved to 0 CRITICAL + 39 HIGH (from 1.46.0's 0 CRITICAL + 1 HIGH residual libcap2
# CVE-2026-4878 — that single CVE apparently regressed into a broader Debian 13.1 os-pkgs
# set of 39 HIGH util-linux/libblkid/libmount/libuuid CVEs, e.g. CVE-2026-53612 through
# CVE-2026-53615, by the time this rebase happened) but still wasn't fully clean. Changelog
# 1.46.0->1.46.1->1.46.2 reviewed (CHANGELOG.md + GitHub compare v1.46.0...v1.46.2): no
# breaking changes — 1.46.1 was a CI/build-tooling fix only (singlefile snapshots on old
# node, PR #1445, doesn't affect the runtime image); 1.46.2 added two small UI fixes (tag
# hash CSS rendering PR #1447, tag management bookmarks-page link fix PR #1452) plus a
# django 6.0.6->6.0.7 and sqlparse 0.5.5->0.6.0 dependency bump. Nothing touches this
# deployment's LD_CSRF_TRUSTED_ORIGINS/LD_SUPERUSER_* env vars or requires a config edit.
# The image's own apt sources already include the trixie-security component, so a plain
# dist-upgrade of already-installed packages picks up every published security fix rather
# than a hand-maintained package list. linkding itself (the Python/Django app) is unchanged
# by this Dockerfile — only the OS package layer is patched.
FROM sissbruecker/linkding:1.46.2
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
