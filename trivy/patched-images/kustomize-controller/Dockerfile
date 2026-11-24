# Frozen-rebuild patch of ghcr.io/fluxcd/kustomize-controller.
#
# Rebased 2026-11-24 (tm 45894c5c, reconcile-scanner) onto v1.10.2. Plain
# v1.10.2 (Alpine 3.24.4) already ships the openssh/git/libexpat fixes this
# fork was created for; its only residual CRITICAL/HIGH is in the Go binary
# (golang.org/x/net v0.61.0 CVE-2026-78661), which an apk upgrade can't touch.
# `apk upgrade --simulate` on the base bumps libcrypto3/libssl3 3.5.9-r0 ->
# 3.5.9-r1, zlib 1.3.2-r1 -> 1.4-r0 and libffi 3.5.2-r1 -> 3.8.1-r0 (MEDIUM/LOW
# openssl + zlib CVEs); the controller binary is untouched. See
# trivy/patched-images.yaml for post-patch scan counts.
#
# History: forked 2026-11-13 on v1.10.1 (tm 651d6773) for openssh 10.3_p1-r2,
# git 2.54.1-r0, libexpat 2.10.0-r0. Earlier lineage (v1.9.4 -> v1.10.0-patched,
# dropped 2026-11-03 in 2907eab) - see git history of this file.
FROM ghcr.io/fluxcd/kustomize-controller:v1.10.2
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
