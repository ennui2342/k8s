# Patch built 2026-08-01 (task f38c9fb7-bb66-45f0-9d5c-c98a0d2b4ae8).
# Resolves 2 CRITICAL + 9 HIGH fixable CVEs in the Alpine 3.19.8 base, including:
#   php81 (and every php81-* subpackage)  8.1.32-r0 -> 8.1.34-r0
#     (CVE-2026-6722, CVE-2026-7261 CRITICAL: php-soap use-after-free/incorrect-handling RCE;
#      CVE-2025-14177/14178/14180, CVE-2025-1735, CVE-2026-7258/7262/7568 HIGH)
#   musl / musl-utils                     1.2.4_git20230717-r5 -> r6  (CVE-2026-40200)
# `apk upgrade` also picks up busybox, ca-certificates-bundle, libcrypto3/libssl3, libpq,
# sqlite-libs and a few other transitive packages along the way (verified via
# `apk upgrade --simulate` against the live image before building) — no CVEs from those were
# in the original scan, but taking the whole security-repo upgrade is simpler and safer than
# hand-pinning individual packages. No newer 2.6.14-line upstream tag exists (Docker Hub last
# published 2025-10-07) to pick up an updated base image, and wallabag's own app version/PHP
# minor version (8.1.x) is unchanged — pure OS-package patch level bump, no Doctrine schema
# migration involved.
FROM wallabag/wallabag:2.6.14
USER root
RUN apk update && apk upgrade --no-cache
