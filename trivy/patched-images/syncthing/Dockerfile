# Frozen-rebuild patch of lscr.io/linuxserver/syncthing.
#
# Base: v2.1.3-ls228 (build 2026-08-15) — the newest LinuxServer build; no
# newer -lsNNN tag has been published since, so a plain tag bump can't pick up
# the Alpine 3.23 openssl fix.
#
# Resolves CVE-2026-14456 (HIGH) — openssl DoS via unbounded memory growth in
# the QUIC server. Fixed package: libssl3 / libcrypto3 3.5.8-r0, already
# published to the alpine v3.23/main repo (verified via `apk policy`). This is
# a pure OS-package patch-level bump via `apk upgrade` on the same Alpine 3.23
# base — the syncthing binary (v2.1.3) and the LinuxServer s6-overlay
# entrypoint/CMD are untouched, so there is no config or behaviour change.
#
# Rebuild + repush with a new -lsNNN base + tag suffix whenever LinuxServer
# ships a newer build, or drop this fork entirely once their rebuild picks up
# openssl >= 3.5.8-r0 (reconcile-scanner tracks this).
FROM lscr.io/linuxserver/syncthing:v2.1.3-ls228

RUN apk --no-cache -U upgrade
