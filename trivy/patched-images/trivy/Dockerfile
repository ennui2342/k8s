# Patch built 2026-10-21 (task 0d0e631c-eb7f-4a92-b009-33d1f988570b).
# aquasec/trivy:0.75.0 (Alpine 3.24.2) was flagged HIGH for libexpat 2.8.5-r0
# CVE-2026-77214, plus 4 fixable HIGH in the trivy Go binary itself. Upstream
# 0.76.0 fixed the Go-binary findings but kept the same Alpine base, so this
# frozen-rebuild bases on the upstream tag and upgrades the Alpine package layer.
# The trivy binary (/usr/local/bin/trivy) is untouched.
# Rebased 2026-10-29 (task e5bee7bc) onto 0.76.1 (brotli-libs/libcurl findings).
# Rebased 2026-11-12 (task 0f419765) onto 0.76.2 (Alpine 3.24.3, go-jose 4.1.6,
# x/net 0.62.0 — clears the go-jose residual and the libcurl/brotli findings).
# Plain 0.76.2 still scans 0 CRITICAL + 3 HIGH (6 findings) for git 2.54.0-r0
# (CVE-2026-105437, CVE-2026-111760, CVE-2026-114466, published 2026-11-10,
# fixed 2.54.1-r0); apk upgrade -> git/git-init-template 2.54.1-r0, zlib 1.4-r0,
# apk-tools 3.0.9-r0. Result: 0 CRITICAL + 0 HIGH (--ignore-unfixed).
# Build for the cluster's arch (all nodes arm64):
#   docker build --platform linux/arm64 -t 192.168.0.8:30500/trivy:0.76.2-patched-20261112 trivy/patched-images/trivy/
FROM aquasec/trivy:0.76.2
RUN apk upgrade --no-cache
