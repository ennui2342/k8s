# Rebased 2026-10-08 onto upstream 2026.10 (was 2026.9; task c920a827,
# reconcile-scanner: plain 2026.10 scans at 5 CRITICAL + 160 HIGH vs
# 2026.9's 7 CRITICAL + 175 HIGH — better but not clean). apk upgrade closes
# the Alpine-base gap again (see trivy/patched-images.yaml's entry for the
# local trivy 0.75.0 before/after os-pkgs counts).
# Changelog 2026.9->2026.10 reviewed (official release-notes "Backward-
# incompatible changes" section, https://www.home-assistant.io/blog/2026/10/07/release-202610/):
# Authentication legacy-mode removal (usernames now always normalized),
# easyEnergy/EnergyZero sensor renames, EnergyFlip API move, Google Sheets
# empty-worksheet result, Google Wifi uptime deprecation, IoTaWatt reactive
# power unit, Libre Hardware Monitor >= 0.9.5, Linode/Tank Utility disabled,
# Mealie >= 3.2, MQTT mqtt.publish/mqtt.dump now admin-only for user-context
# calls, OpenEVSE status states, Proxmox VE uptime timestamp, Rejseplanen API
# 2.0, Sofar meterless sensors, State conditions combining `for` with
# attribute/list/other-entity state now failing validation, Synology DSM
# reboot/shutdown admin-only, Telegram bot download allowlist, Teslemetry
# streaming entities, UniFi Network reconfigure, UpCloud polling interval,
# Xbox Game Pass sensor — none apply: live .storage/auth_provider.homeassistant
# has a single, already-normalized username and configuration.yaml sets no
# auth_providers; live .storage/core.config_entries (analytics, backup, cast,
# cloud, foxess_modbus, frigate, generic, go2rtc, google_assistant,
# google_translate, hacs, ipp, met, mobile_app, mqtt, radio_browser,
# shopping_list, sun, switch_as_x, tasmota, tuya, waste_collection_schedule,
# webostv) has none of the affected integrations besides mqtt, whose
# mqtt.publish calls are all in automations.yaml (run without user context,
# unaffected) and the only non-admin user is the system-generated read-only
# "Home Assistant Content" user; a YAML walk of automations/scripts/scenes/
# configuration found no state condition combining `for` with attribute,
# a state list, or another entity's state. Developer-side changes
# (DeviceEntry.config_entries enforcement, modbus.get_hub deprecation) only
# log warnings for custom integrations until 2027.10, so foxess_modbus
# 1.15.0 / hacs 2.0.5 / waste_collection_schedule 2.32.0 / frigate keep
# working. Residual CRITICAL/HIGH are Python/Go/Rust language deps baked into
# the image (lang-pkgs/gobinary/rustbinary trivy targets), not Alpine OS
# packages — out of scope for this apk-upgrade patch strategy, same residual
# class as every other frozen-rebuild entry in patched-images.yaml.
# NOTE: base image's Config.User is empty (defaults to root), so `USER root`
# below is a no-op but kept for parity with the established recipe pattern.
FROM homeassistant/home-assistant:2026.10
USER root
RUN apk update && apk upgrade --no-cache
