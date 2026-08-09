# Rebased 2026-08-09 from aquasec/trivy:0.72.0 onto aquasec/trivy:0.73.0
# (upstream app release, not just an Alpine base bump — see
# trivy/patched-images.yaml's entry for this workload for the changelog
# review and residual CVE count). Alpine base still needs an apk upgrade on
# top of the new app version to reach 0 CRITICAL + 0 HIGH fixable.
# This is the image the trivy CronJob itself uses to scan the cluster — take
# care not to leave the fleet without a working scanner mid-rebuild.
FROM aquasec/trivy:0.73.0
USER root
RUN apk update && apk upgrade --no-cache
