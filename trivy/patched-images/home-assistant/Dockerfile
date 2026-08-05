# Rebased 2026-08-05 onto upstream 2026.7.4 (was 2026.5.3) — upstream itself
# improved the Alpine 3.24.1 base layer from 2 CRITICAL + 20 HIGH (2026.5.3)
# down to 0 CRITICAL + 35 HIGH of *Alpine-package* CVEs at scan time (net
# reduction once apk upgrade closes it, see below), but wasn't fully clean.
# apk upgrade closes the remaining Alpine-base gap (verified via local trivy
# 0.70.0 scan: Alpine layer 0 CRITICAL + 0 HIGH after this patch).
# Changelog 2026.5->2026.6->2026.7 reviewed (official release-notes blog
# "Backward-incompatible changes" sections for both 2026.6 and 2026.7):
# none of the listed breaking changes apply to this deployment — no
# HDMI-CEC/ESPHome/ONVIF/Shelly/SmartThings/Tuya/Velux/IronOS/BSB-LAN/
# iCloud/Rabbit Air/Reolink/StarLine/Tesla*/Tractive/Z-Wave JS integrations
# in use; no legacy `platform: template` YAML (removed in 2026.6, deprecated
# since 2025.12) anywhere in configuration.yaml/automations.yaml/scripts.yaml
# (grepped live in-pod); the only `zone`-flavored automations here use
# `trigger: zone`/`condition: zone` (coordinate-based enter/leave), unaffected
# by 2026.7's zone-entity person-count/`in_zones` state recalculation.
# custom_components in use (foxess_modbus 1.13.6, frigate 5.15.4, hacs,
# waste_collection_schedule 2.23.0) declare no min_ha_version pin.
# Residual 2 CRITICAL + ~76 HIGH are Python/Go/Rust language deps baked into
# the image (python-pkg + gobinary + rustbinary trivy targets), not Alpine
# OS packages — out of scope for this apk-upgrade patch strategy, same class
# of residual as every other frozen-rebuild entry in patched-images.yaml.
# NOTE: base image's Config.User is empty (defaults to root), so `USER root`
# below is a no-op but kept for parity with the established recipe pattern.
FROM homeassistant/home-assistant:2026.7.4
USER root
RUN apk update && apk upgrade --no-cache
