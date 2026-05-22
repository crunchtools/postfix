#!/bin/sh
set -e

# Apply mounted main.cf and transport map, then run postfix in foreground.
# Routing config is mounted at /conf so it is not baked into the image; this
# keeps the image generic and the per-deployment routing version-controlled
# alongside the host that mounts it.
cp /conf/main.cf /etc/postfix/main.cf
cp /conf/transport /etc/postfix/transport
# UBI's postfix ships the lmdb map type (postfix-lmdb), not Berkeley DB hash.
postmap lmdb:/etc/postfix/transport

# Postfix refuses to start if its spool/queue dirs aren't sane after a fresh
# config copy; `postfix check` repairs permissions and is non-fatal here.
postfix check || true

exec /usr/sbin/postfix start-fg
