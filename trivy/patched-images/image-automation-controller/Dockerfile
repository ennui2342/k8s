# Resolves CVE-2026-45447 (HIGH): openssl Heap Use-After-Free in PKCS7_verify()
# in the Alpine 3.23.4 base -> fix: openssl 3.5.7-r0.
FROM ghcr.io/fluxcd/image-automation-controller:v1.1.2
USER root
RUN apk update && apk upgrade --no-cache
USER 65534:65534
