# Shared minimal utility image for this repo's lightweight CronJobs (health-monitor,
# pvc-usage-monitor, nas-monitor, trivy's notify container, syncthing's conflict
# monitor, linkding's task-sync) — see CLAUDE.md's "Monitoring & Alerting" section
# for the incident that prompted this: these CronJobs each independently ran
# `apk add`/`apk update && apk upgrade` fresh on every single invocation (no
# persistent package cache), which meant real disk writes on whatever node the
# pod happened to land on every 15-30 minutes. Confirmed live 2026-07-27: this was
# the actual root cause of a "flapping NodeHighIOWait" alert on k8s-2 (a Pi-class
# node whose entire root filesystem is a single, already-79%-full eMMC/SD card) —
# several of these jobs landing on the same node at the same :00/:30 minute mark
# and each reinstalling packages from scratch was what spiked local disk
# utilization to 73.7%, not the NFS server (which was confirmed idle at the same
# moment).
#
# Base is alpine/k8s, not plain alpine, specifically so kubectl comes bundled
# already matching the k3s server version — needed by health-monitor and
# pvc-usage-monitor. Rebuild + reimport (see RUNBOOK.md's image workflow) when the
# k3s version bumps (to keep kubectl in sync) or when the weekly CVE scan flags
# this image — it gets scanned like any other cluster-wide image, no special
# handling needed.
FROM alpine/k8s:1.32.13

RUN apk add --no-cache openssh-client curl jq python3 py3-yaml
