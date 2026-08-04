# Rebased 2026-08-04 onto upstream v1.2.3 (was v1.1.2) — upstream itself
# improved from 1 CRITICAL + 27 HIGH (v1.1.2) to 0 CRITICAL + 1 HIGH (v1.2.3)
# but wasn't fully clean; apk upgrade closes the remaining Alpine-base gap.
# v1.2.0 dropped the deprecated image.toolkit.fluxcd.io/v1beta2 CRD version —
# confirmed not in use anywhere in this repo (only .../v1 is referenced) and
# this cluster's CRD storedVersions are already v1-only, so it's safe here.
FROM ghcr.io/fluxcd/image-automation-controller:v1.2.3
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
