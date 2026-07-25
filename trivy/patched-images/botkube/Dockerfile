# Patch built 2026-07-25 (task b9277318-40f6-4c25-b4f7-f8d3377046c1).
# Resolves 2 HIGH CVEs in the Alpine 3.18.9 base:
#   CVE-2024-52006 (git: newline confusion in credential helpers)  git 2.40.3-r0 -> 2.40.4-r0
#   CVE-2025-26519 (musl libc out-of-bounds write)                 musl 1.2.4-r2 -> 1.2.4-r3
# botkube upstream has shipped no release since v1.14.0 (2024-11-13); repo pushed_at
# 2024-12-11, no newer image tag exists to pick up an updated Alpine base.
FROM ghcr.io/kubeshop/botkube:v1.14.0
USER root
RUN apk update && apk upgrade --no-cache
USER botkube
