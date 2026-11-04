#!/bin/sh
# wallabag 2.6.15 on Alpine 3.24 + PHP 8.4.27, built from upstream's OWN image recipe
# (github.com/wallabag/docker). First built 2026-10-24 (tm ae346cd4) on 2.6.14; rebased onto
# 2.6.15 on 2026-11-04 (reconcile-scanner tm 1a7ce485).
#
# Why a fork at all: upstream's published wallabag/wallabag:2.6.15 (2026-10-28, docker repo
# 19ba6d5) went BACK to Alpine 3.22 + PHP 8.2 (8355a02, "move back to alpine 3.22 and php 8.2"
# for the 2.6 line) and:
#   - ships its php.ini/php-fpm.conf under /etc/php81 (unused by php82) -- fixed on docker master
#     in debc360 *after* the 2.6.15 image was published, so the published image runs php-fpm
#     with stock Alpine config;
#   - leaves session.upload_progress enabled (CVE-2026-115560, PHP advisory 2026-10-23);
#   - scans 2 more HIGH (Alpine 3.22 OS layer) than this build.
# wallabag 2.6.15 itself officially supports PHP 8.4 (its CHANGELOG), so keep the php84 recipe.
#
# Pinned inputs (bump deliberately):
#   wallabag/docker dd7191fa6d1837df00518d3a3a422dc353af1f34  (master before the php82 move-back;
#                                                              Alpine 3.24 + php84 since 5d9cc5e)
#   + PR #484 61638de820c0ac97d62fe369a68ab4da8e2a1c6e        (PHP >= 8.4.27 build check,
#                                                              session.upload_progress off)
#   + cherry-picks from master, all independent of the php version:
#       7b16bab  Fix database ownership for PostgreSQL 15+ (entrypoint)
#       c970e66  Prepare 2.6.15 (WALLABAG_VERSION=2.6.15)
#       b8ccd8b  Default PHP memory_limit 256M
#
# Revert to the plain upstream image once wallabag publishes an image on PHP >= 8.4.27 (or with
# the php82 config-dir fix + upload_progress off and a clean OS layer); the reconcile-scanner
# watches upstream_image.
set -eu
TAG=192.168.0.8:30500/wallabag:2.6.15-php8.4.27-$(date +%Y%m%d)
W=$(mktemp -d)
G="git -C $W -c user.name=build -c user.email=build@localhost"
git clone -q https://github.com/wallabag/docker "$W"
$G checkout -q dd7191fa6d1837df00518d3a3a422dc353af1f34
$G fetch -q origin 61638de820c0ac97d62fe369a68ab4da8e2a1c6e
$G diff dd7191fa6d1837df00518d3a3a422dc353af1f34 61638de820c0ac97d62fe369a68ab4da8e2a1c6e | $G apply
$G commit -qam "PR #484"
$G cherry-pick -x 7b16bab7814d33aba4ae6c4287e35c7e72af5b26 c970e665d6d8ff7747c68d130bd8e5be954d385c b8ccd8b0a72720dea9895d7560f17cc81ef8f39a
docker build --pull --platform linux/arm64 -t "$TAG" "$W"
docker push "$TAG"
rm -rf "$W"
