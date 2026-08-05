# Rebased 2026-08-05 onto upstream v1.9.4 (was v1.8.4) — upstream itself
# improved from 3 CRITICAL + 40 HIGH (v1.8.4) to 0 CRITICAL + 1 HIGH (v1.9.4)
# but wasn't fully clean; apk upgrade closes the remaining Alpine-base gap
# (verified via local trivy 0.70.0 scan: Alpine layer 0 CRITICAL + 0 HIGH
# after this patch). Residual 2 HIGH (golang.org/x/text CVE-2026-56852,
# grpc-go GHSA-hrxh-6v49-42gf) are Go module deps baked into the binary,
# out of scope for an apk-upgrade patch.
# Changelog v1.8.4->v1.9.4 reviewed: the only behavior change (v1.9.0's
# StrictPostBuildSubstitutions feature gate, default-on) only affects
# Kustomizations using spec.postBuild.substitute — grepped this repo, none
# do, so it doesn't apply here. No CRD field removals or other breaking
# changes in this range.
FROM ghcr.io/fluxcd/kustomize-controller:v1.9.4
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
