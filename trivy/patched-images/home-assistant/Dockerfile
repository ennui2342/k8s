# Rebased 2026-08-08 onto upstream 2026.8 (was 2026.7.4) — upstream 2026.8
# scans at 2 CRITICAL + 96 HIGH (37 HIGH are Alpine OS-package CVEs, 2
# CRITICAL + 59 HIGH are lang-pkg/gobinary/rustbinary deps baked into the
# image) — an improvement over 2026.7.4 (2 CRITICAL + 110 HIGH at scan time)
# but not fully clean on its own. apk upgrade closes the Alpine-base gap
# (verified via local trivy 0.72.0 scan: Alpine/os-pkgs layer 0 CRITICAL +
# 0 HIGH after this patch).
# Changelog 2026.7.4->2026.8 reviewed (official release-notes "Backward-
# incompatible changes" section, https://www.home-assistant.io/blog/2026/08/05/release-20268/):
# AirNow, Gardena Bluetooth, Edifier Infrared, Ohme, Paperless-ngx, the
# battery_level removal on LG ThinQ/Neato/Romy/Shark IQ/SwitchBot Cloud/
# Template/TP-Link/Xiaomi Miio robot vacuums, ScreenLogic's polling-interval
# option, UniFi Protect's 7.1 requirement, and the Volvo On Call removal —
# none apply: grepped live in-pod .storage/core.config_entries lists only
# analytics, backup, cast, cloud, foxess_modbus, frigate, generic,
# google_assistant, google_translate, hacs, ipp, met, mobile_app, mqtt,
# radio_browser, shopping_list, sun, switch_as_x, tasmota,
# waste_collection_schedule, webostv, zeroconf — no overlap. The separate
# "default port" change (new installs of Home Assistant OS drop the :8123
# suffix) explicitly only affects new HAOS installs per the release notes;
# this deployment runs the plain Docker image with an existing YAML config,
# unaffected either way. custom_components in use (foxess_modbus 1.13.6,
# frigate 5.15.4, hacs 2.0.5, waste_collection_schedule 2.23.0) declare no
# min_ha_version pin.
# Residual 2 CRITICAL + 59 HIGH are Python/Go/Rust language deps baked into
# the image (lang-pkgs/gobinary/rustbinary trivy targets), not Alpine OS
# packages — out of scope for this apk-upgrade patch strategy, same residual
# class as every other frozen-rebuild entry in patched-images.yaml.
# NOTE: base image's Config.User is empty (defaults to root), so `USER root`
# below is a no-op but kept for parity with the established recipe pattern.
FROM homeassistant/home-assistant:2026.8
USER root
RUN apk update && apk upgrade --no-cache
