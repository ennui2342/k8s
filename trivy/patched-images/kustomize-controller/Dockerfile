# Frozen-rebuild patch of ghcr.io/fluxcd/kustomize-controller.
#
# Rebased 2026-10-02 onto upstream v1.9.6 (was v1.9.5) as part of the Flux
# distribution v2.8.1 -> v2.9.6 regeneration of flux-system/gotk-components.yaml
# (tm task 85f65544). Plain v1.9.6 (Alpine 3.23.6) is 0 CRITICAL + 5 HIGH: one
# os-pkgs HIGH (pcre2 CVE-2026-103111, 10.48-r0 -> 10.49-r0) plus 4 lang-pkgs
# HIGH baked into the Go binary. apk upgrade closes the Alpine-base gap -
# verified in the built image: pcre2 10.48-r0 -> 10.49-r0 and libssl3/libcrypto3
# 3.5.8-r0 -> 3.5.9-r0 only; local trivy 0.74.0 scan shows os-pkgs 0 CRITICAL +
# 0 HIGH after patch. Residual 0 CRITICAL + 4 HIGH are Go module deps in the
# controller binary (golang.org/x/crypto CVE-2026-56854; google.golang.org/grpc
# CVE-2026-84304 / CVE-2026-84445 / GHSA-hrxh-6v49-42gf), out of scope for an
# apk-upgrade patch - same residual class as the other Flux controller forks.
#
# Changelog v1.9.5 -> v1.9.6 reviewed (official CHANGELOG.md):
#   - SOPS decryption error redaction extended to spec.postBuild.substituteFrom
#     values - security fix, no config impact (no Kustomization here uses
#     postBuild substitution; grepped).
#   - New opt-in DisableCommitStatusEvent feature gate - off by default, unused.
#   - fluxcd/pkg dependency bumps.
# No CRD field removals, no arg/RBAC changes, no breaking changes in this range.
#
# Previous rebase (2026-09-11, v1.9.4 -> v1.9.5): see git history of this file.
FROM ghcr.io/fluxcd/kustomize-controller:v1.9.6
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
