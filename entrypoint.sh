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

# DKIM signing is optional: without a mounted /conf/opendkim.conf the image is
# the plain relay it has always been. When the config is present the milter is
# mandatory — a failure here must stop the container rather than quietly send
# unsigned mail.
if [ -f /conf/opendkim.conf ]; then
    cp /conf/opendkim.conf /etc/opendkim.conf
    cp /conf/keytable /etc/opendkim/KeyTable
    cp /conf/signingtable /etc/opendkim/SigningTable
    # opendkim signs only for clients listed here. Without it opendkim falls
    # back to 127.0.0.1 and silently signs nothing, since every real client
    # reaches this relay over the network — so it is required, not optional.
    cp /conf/internalhosts /etc/opendkim/InternalHosts

    # The host keeps the private keys root-owned and 0400 and mounts /dkim
    # read-only. Copying them into the container's writable layer is what lets
    # opendkim run as its own unprivileged user instead of root.
    install -d -m 0700 -o opendkim -g opendkim /etc/opendkim/keys
    for key in /dkim/*.private; do
        [ -e "$key" ] || continue
        install -m 0400 -o opendkim -g opendkim "$key" "/etc/opendkim/keys/$(basename "$key")"
    done

    install -d -m 0755 -o opendkim -g opendkim /run/opendkim

    # opendkim daemonizes; set -e fails the container if it will not start.
    opendkim -x /etc/opendkim.conf
fi

# Postfix refuses to start if its spool/queue dirs aren't sane after a fresh
# config copy; `postfix check` repairs permissions and is non-fatal here.
postfix check || true

exec /usr/sbin/postfix start-fg
