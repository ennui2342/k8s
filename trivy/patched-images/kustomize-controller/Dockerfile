# Frozen-rebuild patch of ghcr.io/fluxcd/kustomize-controller.
#
# Rebased 2026-10-27 onto upstream v1.10.0 (was v1.9.6) - reconcile-scanner
# task c625b93b: plain v1.10.0 scans 0 CRITICAL + 1 HIGH vs v1.9.6's re-scanned
# 0 CRITICAL + 14 HIGH. v1.10.0 is Alpine 3.24.3; apk upgrade bumps libcurl
# 8.22.0-r0 -> 8.23.0-r0 only (verified via `apk upgrade --simulate` in the
# base image). See trivy/patched-images.yaml for post-patch scan counts.
#
# Changelog v1.9.6 -> v1.10.0 reviewed (official CHANGELOG.md):
#   - ObjectLevelWorkloadIdentity feature gate retired (always on) - this repo
#     passes no --feature-gates flag to the controller; grepped.
#   - --sops-vault-configmap superseded by transit-engine.auth.fluxcd.io/*
#     annotations - flag not used here (SOPS is age-only via sops-age secret).
#   - spec.kubeConfig.configMapRef legacy `audiences` key -> annotation - no
#     Kustomization here uses spec.kubeConfig; grepped.
#   - New opt-in SPIFFE inter-controller mTLS, --override-manager-before-dry-run
#     flag, SOPS comment-regex decryption fix - all additive/opt-in.
#   - Built with Kubernetes 1.37 client libs / Go 1.27 (cluster is k3s v1.36,
#     within client-go skew).
# Upstream CRD diff v1.9.6 -> v1.10.0 is description text plus an equivalent
# rewrite of the kubeConfig exactly-one-of CEL rule; config/rbac/role.yaml and
# config/manager/deployment.yaml are byte-identical - so this controller-only
# bump is safe against the Flux v2.9.6 CRDs/RBAC in gotk-components.yaml.
#
# Previous rebases: v1.9.5 -> v1.9.6 (2026-10-02, tm 85f65544), v1.9.4 ->
# v1.9.5 (2026-09-11, tm 950679d7) - see git history of this file.
FROM ghcr.io/fluxcd/kustomize-controller:v1.10.0
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
