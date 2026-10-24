# Patch built 2026-10-24 (tm 844e4ee3) for the website StatefulSet's php container, when it
# moved off php:7.0-fpm (EOL) to PHP 8.4 for PHP2Shell (CVE-2026-109618/-109619; fixed in
# 8.4.27). Resolves the one HIGH fixable CVE left in the upstream php:8.4.27-fpm Debian 13.7
# (trixie) base:
#   libbrotli1   1.1.0-2+b7 -> 1.1.0-2+deb13u1   (CVE-2026-111497, out-of-bounds write in decoder)
# Plain trixie-security dist-upgrade of already-installed packages — same recipe as the other
# frozen-rebuild forks. PHP itself is untouched (8.4.27 from the upstream image).
# Rebuild: docker build --pull --no-cache --platform linux/arm64 \
#   -t 192.168.0.8:30500/php:8.4.27-fpm-patched-$(date +%Y%m%d) . && docker push <that tag>
FROM php:8.4.27-fpm
RUN apt-get update \
    && apt-get -y --only-upgrade dist-upgrade \
    && rm -rf /var/lib/apt/lists/*
