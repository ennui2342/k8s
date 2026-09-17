# Rebased 2026-09-17 onto upstream telegraf:1.40 (was 1.39.2) — tm task
# cf849a1f. reconcile-scanner found telegraf:1.40 scans at 2 CRITICAL + 7
# HIGH vs 1.39.2's 3 CRITICAL + 23 HIGH — an improvement, not a full
# resolution, so this rebases the existing fork rather than dropping it.
# Changelog 1.39.2->1.39.3->1.40.0 reviewed (official GitHub release
# notes): the only Breaking Changes in that range are removed/changed
# behavior in inputs.aerospike, inputs.cisco_telemetry_mdt,
# inputs.kafka_consumer, inputs.openstack, inputs.procstat, inputs.sflow,
# inputs.tail, and outputs.amon — none of which this deployment's config
# uses (verified via repo grep of monitoring/telegraf.yaml). This
# config only uses [agent], outputs.influxdb (x2), inputs.statsd,
# inputs.mqtt_consumer, processors.regex, and inputs.snmp, none of which
# appear in any Breaking Changes / migration notes across this range.
# The 1.39.3 release also bumped the vendored rclone dep to 1.75.0 (fixes
# CVE-2026-49980, needed 1.74.3+) and grpc to 1.82.1 (fixes
# GHSA-hrxh-6v49-42gf) — the exact two Go-module CVEs this fork's prior
# residual called out as out-of-scope for an apt-upgrade-only strategy;
# see patched-images.yaml for the actual post-build scan residual, since
# new Go deps may introduce different findings.
FROM telegraf:1.40
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
