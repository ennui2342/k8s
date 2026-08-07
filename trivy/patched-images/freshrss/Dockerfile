# Patch built 2026-08-07 (task 33928d40-13ec-4dc6-a530-541e60d823f9).
# Resolves 2 CRITICAL + 17 HIGH fixable CVEs in the Debian 13.5 (trixie) base, including:
#   apache2 (and libapache2-mod-php)   2.4.67-1~deb13u2 -> 2.4.68-1~deb13u1
#     (CVE-2026-34355, CVE-2026-42536, CVE-2026-44185, CVE-2026-44186, CVE-2026-49975 HIGH)
#   php8.4 (and every php8.4-* subpackage) 8.4.21-1~deb13u1 -> 8.4.24-1~deb13u1
#     (CVE-2026-17543, CVE-2026-17544 CRITICAL: ext-pgsql SQL injection, bccomp() OOB write RCE)
#   libcurl4t64 / curl                 8.14.1-2+deb13u3 -> 8.14.1-2+deb13u4
#     (CVE-2026-5773, CVE-2026-6276 HIGH)
#   libexpat1                          2.7.1-2 -> 2.8.2-1~deb13u1
#     (CVE-2025-59375 HIGH)
# The image's own apt sources already include the trixie-security component, so a plain
# dist-upgrade of already-installed packages picks up every published security fix rather
# than a hand-maintained package list. FreshRSS itself (the PHP app) is unchanged — 1.29.1 is
# already the latest upstream release (Docker Hub last rebuilt 2026-05-20, digest unchanged
# since), so no newer tag exists yet to pick up an updated base image.
FROM freshrss/freshrss:1.29.1
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
