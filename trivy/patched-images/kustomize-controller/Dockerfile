# Rebased 2026-09-11 onto upstream v1.9.5 (was v1.9.4) — upstream itself
# improved from 1 CRITICAL + 23 HIGH (v1.9.4) to 1 CRITICAL + 12 HIGH (v1.9.5)
# but still isn't fully clean; apk upgrade closes the remaining Alpine-base gap.
# Residual CRITICAL/HIGH after this patch are Go module deps baked into the
# controller binary (golang.org/x/* / grpc-go / stdlib class), out of scope
# for an apk-upgrade patch — same residual class as the other Flux forks.
# Changelog v1.9.4->v1.9.5 reviewed (official CHANGELOG.md):
#   - "purge tmp dirs at startup" — internal cleanup fix, no config/behaviour
#     impact.
#   - post-build substitution negative-length crash fix (${VAR:2:-1}) — only
#     affects Kustomizations using spec.postBuild.substitute; grepped this
#     repo, none do.
#   - .spec.kubeConfig Secrets must now be self-contained (inline creds only,
#     no local-file references) — only affects Kustomizations using
#     spec.kubeConfig for remote-cluster apply; grepped this repo, none do.
#   - fluxcd/pkg bump brings Kubernetes client libs to 1.36.4 — cluster is
#     k3s v1.32.x, within client-go skew tolerance (same call as the
#     notification-controller / source-controller forks).
# No CRD field removals or other breaking changes in this range.
FROM ghcr.io/fluxcd/kustomize-controller:v1.9.5
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
