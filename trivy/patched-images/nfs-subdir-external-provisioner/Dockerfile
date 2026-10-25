# Frozen-rebuild of registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
# onto a supported base (tm task b1f467fc).
#
# Why: upstream v4.0.2 (2021) is still the newest tag ever published to
# registry.k8s.io, and its base is gcr.io/distroless/static on Debian 9
# (stretch) — EOL, so trivy reports EOSL and no OS advisories will ever ship
# for it. No newer upstream tag exists to move to.
#
# Recipe: rebuild the exact v4.0.2 source (same commit the upstream image was
# built from — fab8b562, unchanged go.mod/go.sum/deps) with a current Go
# toolchain, statically (CGO_ENABLED=0, same as upstream's Makefile), and put
# the binary on distroless/static-debian13. No code or dependency changes —
# only the toolchain (go1.14 -> current, which also clears the old Go stdlib
# CVEs baked into the upstream binary) and the base image change.
#
# Runtime contract kept identical to upstream: single static binary at
# /nfs-subdir-external-provisioner as ENTRYPOINT, runs as root (uid 0 — the
# upstream image's User is "0"; it mkdir/chmods subdirectories on the NFS
# export mounted at /persistentvolumes), no shell needed.
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.27-bookworm AS build
ARG TARGETOS
ARG TARGETARCH
ARG SRC_REF=v4.0.2
RUN git clone --depth 1 --branch ${SRC_REF} \
      https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git /src
WORKDIR /src
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
      go build -mod=mod -trimpath -ldflags '-s -w -extldflags "-static"' \
      -o /out/nfs-subdir-external-provisioner ./cmd/nfs-subdir-external-provisioner

FROM gcr.io/distroless/static-debian13:latest
LABEL maintainers="Kubernetes Authors" \
      description="NFS subdir external provisioner (v4.0.2 rebuilt on distroless static-debian13)" \
      revision="v4.0.2"
COPY --from=build /out/nfs-subdir-external-provisioner /nfs-subdir-external-provisioner
USER 0
ENTRYPOINT ["/nfs-subdir-external-provisioner"]
