# Patch built 2026-08-14 (task bbfe45a5-7728-4be4-80dd-ae08314de5f5).
# Resolves 9 HIGH fixable CVEs in the Debian 13.6 (trixie) base:
#   libaom3                        3.12.1-1 -> 3.12.1-1+deb13u1
#     (CVE-2026-56208, CVE-2026-56209, CVE-2026-56210, CVE-2026-56211 HIGH)
#   libheif1 / libheif-plugin-dav1d / libheif-plugin-libde265
#                                   1.19.8-1 -> 1.19.8-1+deb13u1
#     (CVE-2025-68431, CVE-2026-32740, CVE-2026-32741, CVE-2026-32882,
#      CVE-2026-47178 HIGH)
# nginx:1.31.3-trixie is the newest tag on the 1.31.x line (Docker Hub last rebuilt
# 2026-08-05, digest unchanged since) — the fixed package versions were only published
# to the trixie-security apt repo after that rebuild, so no newer upstream tag exists yet
# to pick them up. The image's own apt sources already include trixie-security, so a plain
# dist-upgrade of already-installed packages picks up the published fix rather than a
# hand-maintained package list. nginx itself is unchanged — pure OS-package patch-level
# bump, no breaking changes (libaom/libheif aren't nginx runtime dependencies here; they're
# transitive base-image packages, unused by this deployment's config).
FROM nginx:1.31.3-trixie
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
