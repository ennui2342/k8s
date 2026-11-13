# Frozen-rebuild patch of ghcr.io/fluxcd/kustomize-controller.
#
# Forked 2026-11-13 (tm 651d6773, cve-scanner): plain v1.10.1 (Alpine 3.24.3,
# still the newest kustomize-controller release) ships 1 CRITICAL + 7 HIGH
# fixable OS-package CVEs:
#   - openssh 10.3_p1-r1 -> 10.3_p1-r2 (CVE-2026-123158, CRITICAL)
#   - git 2.54.0-r0 -> 2.54.1-r0 (CVE-2026-105437/111760/114466)
#   - libexpat 2.9.0-r0 -> 2.10.0-r0 (CVE-2026-113351/115506/117610/118370)
# `apk upgrade --simulate` in the base image bumps exactly those plus
# alpine-release 3.24.4, zlib 1.4-r0 and apk-tools 3.0.9 - same-branch Alpine
# patch updates; the controller binary is untouched. See
# trivy/patched-images.yaml for post-patch scan counts.
#
# Previous fork lineage (v1.9.4 -> v1.10.0-patched, dropped 2026-11-03 for
# plain v1.10.1 in 2907eab) - see git history of this file.
FROM ghcr.io/fluxcd/kustomize-controller:v1.10.1
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
