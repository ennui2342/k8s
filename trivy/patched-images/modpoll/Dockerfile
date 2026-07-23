# Best-effort reconstruction of the 2026-05-19 patch (commit 6e85c3f).
# Resolves 2 CRITICAL + 8 HIGH CVEs: openssl/libssl3 3.0.17->3.0.20, libpam
# 1.5.2-6+deb12u1->u2. No newer modpoll upstream tag exists.
FROM topmaker/modpoll:1.6.0
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
