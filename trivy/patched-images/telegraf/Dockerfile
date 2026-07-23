# Best-effort reconstruction of the 2026-06-08 patch (commit 55e6e67).
# Resolves 2 CRITICAL + 5 HIGH CVEs via targeted package bumps:
# libcap2/libcap2-bin 1:2.66-4+deb12u2+b2 -> u3+b1, libgnutls30 3.7.9-2+deb12u6 -> u7,
# libnghttp2-14 1.52.0-1+deb12u2 -> u3. telegraf itself unchanged (Go binary).
FROM telegraf:1.38.3
RUN apt-get update \
    && apt-get install -y --only-upgrade libcap2 libcap2-bin libgnutls30 libnghttp2-14 \
    && rm -rf /var/lib/apt/lists/*
