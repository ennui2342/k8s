# Rebased 2026-08-19 onto upstream postgres:18.6-trixie (was postgres:18, which
# had resolved to Docker Hub's 18.4-1.pgdg13+1 build as last pulled) — tm task
# b54084fa. Resolves 1 HIGH fixable CVE:
#   CVE-2026-53615 (libblkid, Integer Overflow or Wraparound in
#   libblkid/src/partitions/dos.c) — libblkid1/util-linux/mount/login
#   2.41-5 -> 2.41.5-0+deb13u1 (Debian 13.6 trixie-security).
#
# postgres:18.6-trixie (the newest tag on the 18.x line, Docker Hub rebuilt
# 2026-08-15) already includes the Debian 13.6 trixie-security apt source in
# its sources.list, but the layer itself was baked before the util-linux
# security update was published there — confirmed live via `apt-cache policy
# libblkid1` inside the image: Candidate 2.41.5-0+deb13u1 was already
# resolvable from trixie-security, just not yet installed. A same-base apt
# upgrade closes the gap without waiting on Docker Hub to rebuild the tag
# again (verified live: libblkid1 2.41-5 -> 2.41.5-0+deb13u1 after apt-get
# upgrade).
#
# Postgres 18.4 -> 18.6 (18.5 was never released — pulled pre-ship due to a
# regression) reviewed via the official release notes
# (https://www.postgresql.org/docs/18/release-18-6.html): none of its listed
# manual-action items apply to this deployment —
#   - output_plugin_libraries whitelist (CVE-2026-6471): no logical
#     replication slots or custom output plugins in use (pg_replication_slots
#     is empty)
#   - pgp_sym_decrypt cipher rejection (CVE-2026-14663): pgcrypto extension
#     isn't installed (only plpgsql, confirmed via pg_extension)
#   - GIN index reltuples corruption / btree_gist / ltree reindex notes:
#     no GIN indexes and neither extension is installed
#   - COPY-without-terminator syntax change only affects test scripts that
#     intentionally exercise failing COPY ... FROM STDIN commands, not
#     runtime app behavior
# Pure OS-package patch-level bump plus a postgres bugfix/security point
# release, no config or schema changes needed; dump/restore not required for
# an 18.x-line upgrade.
FROM postgres:18.6-trixie
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
