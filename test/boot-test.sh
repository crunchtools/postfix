#!/usr/bin/env bash
# Boot test for the postfix + opendkim relay image.
#
# Starts the image the way production starts it, with a throwaway DKIM key, and
# proves the three things that matter:
#
#   1. postfix answers on :25 and opendkim is up and listening
#   2. mail from a listed client, for a listed domain, comes out signed
#   3. mail that should NOT be signed isn't — neither a domain missing from the
#      signing table nor a client missing from InternalHosts
#
# (3) is the forgery gate. A relay that signs anything claiming to be
# From: us would let a stranger borrow our reputation.
#
# This is also what catches a build that shipped without opendkim at all (EPEL
# mirror outage — container-image profile, 2026-10-22); a "did it start" check
# would not.
#
# Usage: test/boot-test.sh <image-ref>
set -euo pipefail

IMAGE="${1:?usage: boot-test.sh <image-ref>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CTR="postfix-boot-test-$$"
WORK="$(mktemp -d)"
PORT=12525

cleanup() {
    podman rm -f "$CTR" >/dev/null 2>&1 || true
    rm -rf -- "$WORK"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- throwaway signing material -------------------------------------------
mkdir -p "$WORK/dkim"
# Generated with the image's own opendkim-genkey, so the test depends on
# nothing being installed on the runner and exercises the same tool that
# produces the production keys.
podman run --rm -v "$WORK/dkim:/out:Z" --entrypoint opendkim-genkey "$IMAGE" \
    --directory=/out --selector=boottest --domain=crunchtools.com --bits=2048
mv "$WORK/dkim/boottest.private" "$WORK/dkim/crunchtools.com.private"
rm -f "$WORK/dkim/boottest.txt"
chmod 0400 "$WORK/dkim/crunchtools.com.private"

cat > "$WORK/opendkim.conf" <<'EOF'
Syslog                  yes
SyslogSuccess           yes
Mode                    s
Canonicalization        relaxed/simple
OversignHeaders         From
SubDomains              no
UserID                  opendkim
PidFile                 /run/opendkim/opendkim.pid
Socket                  inet:8891@127.0.0.1
KeyTable                /etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
InternalHosts           /etc/opendkim/InternalHosts
RequireSafeKeys         yes
Background              yes
EOF

cat > "$WORK/keytable" <<'EOF'
crunchtools crunchtools.com:boottest:/etc/opendkim/keys/crunchtools.com.private
EOF

cat > "$WORK/signingtable" <<'EOF'
*@crunchtools.com crunchtools
EOF

# Only loopback is trusted to have its mail signed, so the in-container client
# is signed and the host-side client (case 3b) is not.
cat > "$WORK/internalhosts" <<'EOF'
127.0.0.1
::1
EOF

# Relay config mirroring production, except the backend is a dead port so the
# message stays in the queue where postcat can read the signed headers.
cat > "$WORK/main.cf" <<'EOF'
myhostname = mail.crunchtools.com
mydomain = crunchtools.com
myorigin = $myhostname
inet_interfaces = all
inet_protocols = ipv4
mydestination =
local_transport = error:local delivery disabled
local_recipient_maps =
alias_maps =
alias_database =
relay_domains = boottest.invalid
transport_maps = lmdb:/etc/postfix/transport
mynetworks = 127.0.0.0/8, [::1]/128
smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_milters = inet:127.0.0.1:8891
non_smtpd_milters = $smtpd_milters
milter_protocol = 6
milter_default_action = accept
maillog_file = /dev/stdout
EOF

printf 'boottest.invalid\tsmtp:[127.0.0.1]:9\n' > "$WORK/transport"

# --- start it the way production does --------------------------------------
podman run -d --name "$CTR" --hostname mail.crunchtools.com \
    -p "127.0.0.1:${PORT}:25" \
    -v "$WORK/main.cf:/conf/main.cf:ro,Z" \
    -v "$WORK/transport:/conf/transport:ro,Z" \
    -v "$WORK/opendkim.conf:/conf/opendkim.conf:ro,Z" \
    -v "$WORK/keytable:/conf/keytable:ro,Z" \
    -v "$WORK/signingtable:/conf/signingtable:ro,Z" \
    -v "$WORK/internalhosts:/conf/internalhosts:ro,Z" \
    -v "$WORK/dkim:/dkim:ro,Z" \
    -v "$HERE/smtp-send.sh:/smtp-send.sh:ro,Z" \
    "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
    podman exec "$CTR" sh -c 'exec 3<>/dev/tcp/127.0.0.1/25' 2>/dev/null && break
    sleep 1
done

# --- 1. both daemons are up ------------------------------------------------
podman exec "$CTR" sh -c 'exec 3<>/dev/tcp/127.0.0.1/25' 2>/dev/null \
    || { podman logs "$CTR" >&2; fail "postfix is not answering on :25"; }

# pidfile + kill -0 rather than pgrep: ubi-minimal has no procps-ng.
podman exec "$CTR" sh -c 'kill -0 "$(cat /run/opendkim/opendkim.pid)"' 2>/dev/null \
    || { podman logs "$CTR" >&2; fail "opendkim is not running"; }

podman exec "$CTR" sh -c 'exec 3<>/dev/tcp/127.0.0.1/8891' 2>/dev/null \
    || { podman logs "$CTR" >&2; fail "opendkim is not listening on 127.0.0.1:8891"; }

# --- helpers ---------------------------------------------------------------
# Queue IDs already claimed by an earlier send. Kept in a file, not a variable:
# new_queue_id runs inside $( ), so a variable assignment would be lost with
# the subshell and every send would be matched against the first message.
: > "$WORK/seen"

queue_ids() {
    podman exec "$CTR" sh -c 'mailq | awk "/^[0-9A-F]/ {print \$1}"' | tr -d '*!'
}

# Wait for a queue ID not yet claimed, claim it, and echo it.
new_queue_id() {
    local id
    for _ in $(seq 1 25); do
        for id in $(queue_ids); do
            grep -qxF "$id" "$WORK/seen" && continue
            echo "$id" >> "$WORK/seen"
            echo "$id"
            return 0
        done
        sleep 1
    done
    return 1
}

# Echo the queued message. Kept separate from the grep so that a postcat
# failure fails the test, rather than reading as "no signature" and letting the
# negative assertions below pass without having looked at anything.
message_of() {
    podman exec "$CTR" postcat -q "$1"
}

signature_in() {
    printf '%s\n' "$1" | grep '^DKIM-Signature:' || true
}

# --- 2. a listed client, a listed domain: signed ---------------------------
podman exec "$CTR" /smtp-send.sh wordpress@crunchtools.com sink@boottest.invalid \
    || { podman logs "$CTR" >&2; fail "relay rejected a message from a trusted client"; }

QID="$(new_queue_id)" || { podman logs "$CTR" >&2; fail "message never reached the queue"; }
MSG="$(message_of "$QID")" || fail "could not read queued message $QID"
SIG="$(signature_in "$MSG")"
[ -n "$SIG" ] \
    || { echo "$MSG" >&2; podman logs "$CTR" >&2; \
         fail "message from a trusted client was not signed"; }
case "$SIG" in
    *d=crunchtools.com*) ;;
    *) fail "signature is not for d=crunchtools.com: $SIG" ;;
esac

# --- 3a. a domain outside the signing table: not signed --------------------
podman exec "$CTR" /smtp-send.sh someone@elsewhere.invalid sink@boottest.invalid \
    || fail "relay rejected the unsigned-domain test message"

QID_DOMAIN="$(new_queue_id)" || fail "unsigned-domain message never reached the queue"
MSG_DOMAIN="$(message_of "$QID_DOMAIN")" || fail "could not read queued message $QID_DOMAIN"
[ -z "$(signature_in "$MSG_DOMAIN")" ] \
    || fail "mail from a domain outside the signing table was signed"

# --- 3b. a client outside InternalHosts: not signed ------------------------
# Submitted from the host, which is not loopback inside the container. This is
# the case that stops a stranger getting our signature on forged From: mail.
python3 - "$PORT" <<'EOF'
import smtplib, sys
msg = ("From: wordpress@crunchtools.com\r\n"
       "To: sink@boottest.invalid\r\n"
       "Subject: forged boot test\r\n\r\nbody\r\n")
with smtplib.SMTP("127.0.0.1", int(sys.argv[1]), timeout=30) as s:
    s.sendmail("wordpress@crunchtools.com", ["sink@boottest.invalid"], msg)
EOF

QID_FORGED="$(new_queue_id)" || fail "untrusted-client message never reached the queue"
MSG_FORGED="$(message_of "$QID_FORGED")" || fail "could not read queued message $QID_FORGED"
[ -z "$(signature_in "$MSG_FORGED")" ] \
    || fail "mail from a client outside InternalHosts was signed — forgery gate is open"

echo "PASS: relay signs crunchtools.com for trusted clients, and signs nothing else"
