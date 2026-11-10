# Rebased 2026-11-10 onto upstream 2026.11 (was 2026.10; task 348ef1bf,
# reconcile-scanner: plain 2026.11 scans at 1 CRITICAL + 42 HIGH vs
# 2026.10's 8 CRITICAL + 121 HIGH — better but not clean). apk upgrade closes
# the Alpine-base gap again (see trivy/patched-images.yaml's entry for the
# local trivy before/after os-pkgs counts).
# Changelog 2026.10->2026.11 reviewed (official release-notes "Backward-
# incompatible changes" section, https://www.home-assistant.io/blog/2026/11/04/release-202611/).
# Applicable-in-principle items, all checked live and needing no edit:
# - HACS -> built-in Marketplace: HA auto-migrates HACS on first start and
#   DELETES custom_components/hacs + its files (one-way). Installed content
#   (foxess_modbus, waste_collection_schedule, frigate, the foxess charge-
#   period card) stays installed; /hacsfiles/ resource paths keep working
#   (configuration.yaml's YAML-mode lovelace resource still uses it — a repair
#   will suggest /local/community/, cosmetic). No integration_entities('hacs')
#   templates anywhere. Pre-upgrade backup of custom_components + .storage at
#   /config/bak/pre-2026.11-hacs-storage-20261110.tgz in case of rollback.
# - Entity naming rework / Tuya child channel devices: display-name only,
#   entity IDs unchanged; no friendly_name templates in automations/scripts.
# - Sun/calendar trigger signed offset: the one sun.sunrise trigger sets an
#   explicit offset_type (still honored, PR #184855); the other is legacy
#   `trigger: sun` with an already-signed offset.
# - MQTT entities without unique_id lose device config: the only YAML MQTT
#   entity has a unique_id.
# - Auth client-id check for public/Tailscale IPs: access is via domain names.
# - Python deps folder: container env is unaffected.
# - Ring entity removals: no `ring` config entry (front_door_* come from
#   ring-mqtt via MQTT discovery). No telegram/smtp/nanoleaf/unifiprotect/
#   zwave/matter/etc. in core.config_entries (now also includes esphome).
# Previous rebase (2026-10-08 onto 2026.10, task c920a827): see git history
# and patched-images.yaml's reason field for the 2026.9->2026.10 review.
# NOTE: base image's Config.User is empty (defaults to root), so `USER root`
# below is a no-op but kept for parity with the established recipe pattern.
FROM homeassistant/home-assistant:2026.11
USER root
RUN apk update && apk upgrade --no-cache
