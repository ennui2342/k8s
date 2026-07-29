# Cluster Hygiene Checklist

The explicit, mechanically-checkable standard for manifests in this repo — the k8s-repo
equivalent of a linter's rule set. **Not auto-loaded into every session's context** (unlike
`CLAUDE.md`) precisely so it can grow without taxing every unrelated conversation — it's
consulted explicitly, at specific checkpoints:

- The periodic fleet audit (`~/projects/agents/k8s/fleet-audit-prompt.md`) walks this file
  exhaustively against every matching manifest, every run.
- The nightly upgrade specialist (`~/projects/agents/k8s/nightly-upgrade-prompt.md`) checks any
  manifest it writes or edits against this file before committing.
- Any session (automated or interactive) about to write or edit a manifest should check it too —
  `CLAUDE.md` points here for exactly that reason.

This list starts short and is meant to grow: when the audit's research pass, the upgrade
specialist, or anyone in any session finds a new durable best practice worth enforcing
repo-wide, it gets added here as a new checkable rule — not left in a task or a Discord message.
A finding that isn't captured here doesn't survive past the run that found it — see
`feedback_boyscout_or_ticket` in this machine's memory for why that distinction matters.

## Confirmed rules

**Every CronJob must set `ttlSecondsAfterFinished`.** Confirmed live 2026-07-28: 6 of the 7
CronJobs in this repo had no `ttlSecondsAfterFinished` (only `syncthing/cronjob.yaml` did), so
completed Job pods never got cleaned up on their own. This isn't just tidiness —
`trivy/trivy.yaml`'s CronJob mounts a real RWO PVC (`trivy-cache-pvc`), and stale completed pods
from it ended up pinning that PVC and blocking a later run, caught mid-way through a nightly
automated update rather than by design. Every `CronJob.spec.jobTemplate.spec` (sibling of
`template:`, not inside it) must set:

```yaml
ttlSecondsAfterFinished: 604800
```

7 days — long enough to inspect a failed run's logs before it's swept, short enough that pods
don't accumulate indefinitely. `successfulJobsHistoryLimit`/`failedJobsHistoryLimit` (k8s
defaults: 3/1) are a different, complementary mechanism — they cap how many Job *objects* are
kept, not when the underlying pod's resources (including PVC mounts) actually get released.

## Starter items — not yet verified repo-wide as of 2026-07-29

Seeded so the first audit run has concrete starting points, not just a blank slate. Expect this
list to expand, and expect these items to be promoted into their own confirmed entries above
once audited and fixed repo-wide (or removed here if audit finds them already fine).

- Every container should set resource `requests`/`limits` — already known to be missing on at
  least `home-assistant/ha-deployment.yaml` (`resources: {}`), likely others. Matters more than
  usual here: this is a resource-constrained Pi cluster, not a cloud environment with headroom
  to spare.
- No orphaned PVCs (bound, but no owning workload *and* no manifest reference anywhere in this
  repo) — this is exactly the openhab situation from 2026-07-28, caught reactively by a usage
  alert rather than proactively. Should become a mechanical check, not something that only
  surfaces when a PVC happens to fill up.
- Every `imagePullPolicy: Never` entry should have an explicit comment explaining *why* it's
  still on the old pattern instead of the local registry (e.g. librarium/isfdb-adapter's
  documented "PRs not merged upstream yet" reason) — an unexplained one is probably just an
  unmigrated straggler, not a deliberate choice.
