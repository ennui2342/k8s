#!/bin/sh
# wallabag 2.6.14 on Alpine 3.24 + PHP 8.4.27, built from upstream's OWN image recipe
# (github.com/wallabag/docker), 2026-10-24, tm ae346cd4.
#
# Why: the published wallabag/wallabag:2.6.14 (= :latest, 2025-10-07) is Alpine 3.19 + PHP 8.1,
# EOL and unfixable for PHP2Shell (CVE-2026-109618/-109619). Upstream's master Dockerfile moved
# to Alpine 3.24 + php84 in June 2026 (5d9cc5e, CI-tested on sqlite/mariadb/postgres), but no
# image has been published from it. PR #484 (open, CI green) adds a PHP >= 8.4.27 build check
# and disables session.upload_progress (PHP advisory 2026-10-23, CVE-2026-115560).
#
# Pinned inputs (bump deliberately):
#   wallabag/docker master    dd7191fa6d1837df00518d3a3a422dc353af1f34
#   wallabag/docker PR #484   61638de820c0ac97d62fe369a68ab4da8e2a1c6e (applied as a diff)
#
# Revert to the plain upstream image once wallabag publishes a 2.6.14+ image on PHP >= 8.4.27
# (watch github.com/wallabag/docker issues #480/#481); the reconcile-scanner watches upstream_image.
set -eu
TAG=192.168.0.8:30500/wallabag:2.6.14-php8.4.27-$(date +%Y%m%d)
W=$(mktemp -d)
git clone -q https://github.com/wallabag/docker "$W"
git -C "$W" checkout -q dd7191fa6d1837df00518d3a3a422dc353af1f34
git -C "$W" fetch -q origin 61638de820c0ac97d62fe369a68ab4da8e2a1c6e
git -C "$W" diff dd7191fa6d1837df00518d3a3a422dc353af1f34 61638de820c0ac97d62fe369a68ab4da8e2a1c6e | git -C "$W" apply
docker build --pull --platform linux/arm64 -t "$TAG" "$W"
docker push "$TAG"
rm -rf "$W"
