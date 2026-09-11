# Rebased 2026-09-11 onto upstream 2026.9 (was 2026.8) — upstream 2026.9
# scans at 7 CRITICAL + 147 HIGH (3 CRITICAL + 71 HIGH are Alpine 3.24.1
# OS-package CVEs, 4 CRITICAL + 76 HIGH are lang-pkg/gobinary/rustbinary
# deps baked into the image) — an improvement over 2026.8 (2 CRITICAL + 96
# HIGH at prior scan time, though the task's live re-scan reported 7
# CRITICAL + 146 HIGH for 2026.8 at this later scan time — Alpine's rolling
# 3.24 repo moved under both tags between scans) but not fully clean on its
# own. apk upgrade closes the Alpine-base gap (verified via local trivy
# 0.74.0 scan: Alpine/os-pkgs layer 0 CRITICAL + 0 HIGH after this patch).
# Changelog 2026.8->2026.9 reviewed (official release-notes "Backward-
# incompatible changes" section, https://www.home-assistant.io/blog/2026/09/02/release-20269/):
# Flexit Nordic (BACnet) fireplace-mode switch removal, KNX expose
# send-on-init timing change, LLM tool names gaining a domain prefix,
# Persistent Notification's update_type changing from "added" to "updated"
# on edit, UniFi Protect smart-detection switches + the 7.2.105 minimum,
# Update entity install/skip/clear now requiring an admin context, the
# Vacuum base entity's battery_level property removal, and Z-Wave JS lock
# user/credential actions now requiring an admin context — none apply:
# grepped live in-pod .storage/core.config_entries lists only analytics,
# backup, cast, cloud, foxess_modbus, frigate, generic, go2rtc,
# google_assistant, google_translate, hacs, ipp, met, mobile_app, mqtt,
# radio_browser, shopping_list, sun, switch_as_x, tasmota, tuya,
# waste_collection_schedule, webostv — no overlap (no knx/flexit/
# unifiprotect/zwave_js/conversation entries at all). Also grepped
# automations.yaml/scripts.yaml for persistent_notification update_type
# triggers and update.install/update.skip/update.clear_skipped service
# calls — none found; the only non-admin user (Home Assistant Content) is
# system-read-only anyway. custom_components in use (foxess_modbus 1.15.0,
# frigate unversioned, hacs 2.0.5, waste_collection_schedule 2.32.0)
# declare no min_ha_version pin. The release's "Modernizing Modbus" work
# (new Fronius/Sofar/Flexit Modbus-native integrations) is purely additive
# and doesn't touch the YAML-based Modbus integration or foxess_modbus.
# Residual 4 CRITICAL + 76 HIGH are Python/Go/Rust language deps baked into
# the image (lang-pkgs/gobinary/rustbinary trivy targets), not Alpine OS
# packages — out of scope for this apk-upgrade patch strategy, same residual
# class as every other frozen-rebuild entry in patched-images.yaml.
# NOTE: base image's Config.User is empty (defaults to root), so `USER root`
# below is a no-op but kept for parity with the established recipe pattern.
FROM homeassistant/home-assistant:2026.9
USER root
RUN apk update && apk upgrade --no-cache
