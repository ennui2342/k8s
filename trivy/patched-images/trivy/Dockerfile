# Patch built 2026-10-21 (task 0d0e631c-eb7f-4a92-b009-33d1f988570b).
# aquasec/trivy:0.75.0 (Alpine 3.24.2) was flagged HIGH for libexpat 2.8.5-r0
# CVE-2026-77214 (heap buffer over-read in XML_ParseBuffer, fixed in 2.9.0-r0),
# plus 4 fixable HIGH in the trivy Go binary itself (stdlib 1.27.1
# CVE-2026-78667/78669/97031, golang.org/x/net CVE-2026-78669).
# Upstream 0.76.0 (newest release at patch time) fixes the Go-binary findings
# (rebuilt on a patched Go toolchain) but still ships the identical Alpine
# 3.24.2 base with libexpat 2.8.5-r0 — no upstream tag is fully clean, so this
# frozen-rebuild bases on 0.76.0 and upgrades the Alpine package layer
# (libexpat 2.8.5-r0 -> 2.9.0-r0, libssl3/libcrypto3 -> 3.5.9-r0).
# The trivy binary (/usr/local/bin/trivy) is untouched.
# Build for the cluster's arch (all nodes arm64):
#   docker build --platform linux/arm64 -t 192.168.0.8:30500/trivy:0.76.0-patched trivy/patched-images/trivy/
FROM aquasec/trivy:0.76.0
RUN apk upgrade --no-cache
