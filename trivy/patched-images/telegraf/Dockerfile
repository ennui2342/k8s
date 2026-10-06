# Patch built 2026-10-06 (tm task 47c6484c-557c-4169-a319-d4b407d3c23f).
# Resolves 1 HIGH fixable CVE in the Debian 12.15 (bookworm) base:
#   CVE-2026-103111 (pcre2 out-of-bounds write via crafted regular expression)
#   libpcre2-8-0 10.42-1+deb12u1 -> 10.42-1+deb12u2
# telegraf:1.40.1 is still the newest upstream tag (Docker Hub last rebuilt
# 2026-09-21, digest sha256:90da3a5b... identical to what was running), and its
# layer predates the bookworm-security pcre2 update — confirmed live via
# `apt-cache policy libpcre2-8-0` inside the image (Installed deb12u1,
# Candidate deb12u2). Same-base apt upgrade, telegraf binary unchanged (still
# 1.40.1), no config or behaviour change. Revert to plain telegraf:1.40.x once
# upstream rebuilds with libpcre2-8-0 >= 10.42-1+deb12u2.
FROM telegraf:1.40.1
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
