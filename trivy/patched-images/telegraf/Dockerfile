# Rebased 2026-08-06 onto upstream telegraf:1.39.2 (was 1.38.3) — tm task
# 013a3379. Upstream's own Debian 12.15 base layer is already clean at this
# tag (0 CRITICAL + 0 HIGH fixable, verified via local trivy 0.70.0 scan with
# --ignore-unfixed), an improvement over 1.38.3's 5 CRITICAL + 44 HIGH. The
# apt upgrade below is a no-op today against that clean base but is kept so
# any future OS-package regression on this line is closed automatically on
# the next rebuild, same as every other frozen-rebuild recipe here.
# Residual: 1 CRITICAL (github.com/rclone/rclone CVE-2026-49980, fixed in
# 1.74.3) + 1 HIGH (google.golang.org/grpc GHSA-hrxh-6v49-42gf, fixed in
# 1.82.1), both Go module deps baked into the telegraf binary itself, not
# Debian OS packages — out of scope for this apt-upgrade patch strategy,
# same residual class as the flux-controller and home-assistant forks.
# Changelog 1.38.3->1.39.0->1.39.1->1.39.2 reviewed (official GitHub release
# notes): no breaking changes apply to this deployment's config — no
# gnmi_listener/azure_monitor/kafka_consumer/opcua/system/tail/aerospike/
# openweathermap/openstack/amon plugins in use; this config only uses
# [agent], outputs.influxdb (x2), inputs.statsd, inputs.mqtt_consumer,
# processors.regex, and inputs.snmp, none of which appear in any Breaking
# Changes / migration notes across this range.
FROM telegraf:1.39.2
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
