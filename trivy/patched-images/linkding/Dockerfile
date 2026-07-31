# Patch built 2026-07-31 (task e93d4061-502c-4132-8775-82ef55c3e5a7).
# Resolves 7 CRITICAL + 426 HIGH CVEs in the Debian 13.1 (trixie) base, including:
#   curl/libcurl4t64  8.14.1-2+deb13u2 -> u4   (CVE-2026-5773, CVE-2026-6276)
#   krb5              1.21.3-5        -> +deb13u1 (CVE-2026-40355, CVE-2026-40356)
#   libcap2           1:2.75-10+b1    -> +deb13u1 (CVE-2026-4878)
#   libgnutls30t64     3.8.9-3         -> +deb13u4 (CVE-2026-33845, CVE-2026-42010, CVE-2026-33846,
#                                                     CVE-2026-3833, CVE-2026-42009)
# The image's own apt sources already include the trixie-security component, so a plain
# dist-upgrade of already-installed packages picks up every published security fix rather
# than a hand-maintained package list. linkding itself (the Python/Django app) is unchanged —
# no newer 1.45.0-line upstream tag exists yet to pick up an updated base image.
FROM sissbruecker/linkding:1.45.0
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
