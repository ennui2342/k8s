# crane + busybox shell for the cve-scanner CronJob's discover-newer-tags
# initContainer (trivy/trivy.yaml, runs /scripts/discover.sh).
#
# Not a patched fork (no trivy/patched-images.yaml entry): upstream has no
# versioned shell-bearing crane image to catch up to. gcr.io/go-containerregistry/
# crane:debug is a floating tag on distroless/base-debug (Debian OS packages +
# stale-Go crane binary — 11 HIGH as of 2026-10-07), and versioned crane:vX tags
# are shell-less static images. Same model as k8s-toolbox/: rebuild + repush with
# a new date-suffixed tag when the weekly scan flags it or crane releases.
#
# Build/push (tag: <crane version>-YYYYMMDD):
#   docker build -t 192.168.0.8:30500/crane:0.22.1-20261007 trivy/crane/
#   docker push 192.168.0.8:30500/crane:0.22.1-20261007
#
# discover.sh needs only crane plus busybox sh/grep -E/sed -E/awk/sort/cut.
FROM gcr.io/go-containerregistry/crane:v0.22.1 AS crane

FROM busybox:1.38.0-musl
COPY --from=crane /ko-app/crane /usr/local/bin/crane
COPY --from=crane /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER 65532
ENTRYPOINT ["/usr/local/bin/crane"]
