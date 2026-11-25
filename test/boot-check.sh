#!/bin/bash
# Boot gate, run INSIDE the image (the `boot-gate` check in sdlc.toml's
# [tool.sdlc.ci]). The command runtime drops every capability, and postfix will
# not start that way (`postfix check` cannot chown its queue dirs, master
# cannot setuid), so this cannot send mail through the relay. It proves what
# does hold without caps: both daemons and their libraries are in the image
# (the EPEL-outage case, container-image profile 2026-10-22), the entrypoint
# parses, the relay config and the opendkim config parse, lmdb maps build, a
# key generates, and opendkim starts and listens on :8891.
# NOT covered: postfix answering on :25, a trusted client's mail being signed,
# and the two forgery-gate cases (domain not in the signing table, client not in
# InternalHosts). Those still need test/boot-test.sh on a host with podman.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'kill "${ODPID:-}" 2>/dev/null || true; rm -rf -- "$WORK"' EXIT

echo "entrypoint parses"
sh -n /entrypoint.sh || fail "entrypoint.sh does not parse"

echo "binaries and shared libraries"
for b in postfix postconf postmap postcat opendkim opendkim-genkey; do
    p="$(command -v "$b")" || fail "missing $b (a build that lost opendkim ships no signer)"
    if ldd "$p" 2>&1 | grep -q "not found"; then
        ldd "$p" | grep "not found" >&2; fail "unresolved libraries for $b"
    fi
done
for d in master smtpd qmgr cleanup pickup trivial-rewrite smtp local; do
    p="/usr/libexec/postfix/$d"
    test -x "$p" || fail "missing postfix daemon $d"
    if ldd "$p" 2>&1 | grep -q "not found"; then
        ldd "$p" | grep "not found" >&2; fail "unresolved libraries for $d"
    fi
done
postconf -m | grep -qx lmdb || fail "postfix has no lmdb map type"
id opendkim >/dev/null || fail "no opendkim user"
test -d /etc/opendkim/keys || fail "no /etc/opendkim/keys"
test -d /var/spool/postfix/maildrop || fail "no postfix spool"

echo "relay config parses and its transport map builds"
mkdir "$WORK/pf"
cp /etc/postfix/master.cf "$WORK/pf/"
cat > "$WORK/pf/main.cf" <<EOT
myhostname = mail.example.invalid
mydomain = example.invalid
myorigin = \$myhostname
inet_interfaces = all
inet_protocols = ipv4
mydestination =
local_transport = error:local delivery disabled
local_recipient_maps =
alias_maps =
alias_database =
relay_domains = boottest.invalid
transport_maps = lmdb:$WORK/pf/transport
mynetworks = 127.0.0.0/8, [::1]/128
smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_milters = inet:127.0.0.1:8891
non_smtpd_milters = \$smtpd_milters
milter_protocol = 6
milter_default_action = accept
maillog_file = /dev/stdout
EOT
printf 'boottest.invalid\tsmtp:[127.0.0.1]:9\n' > "$WORK/pf/transport"
postmap -c "$WORK/pf" "lmdb:$WORK/pf/transport" || fail "postmap could not build an lmdb map"
test -s "$WORK/pf/transport.lmdb" || fail "postmap built no lmdb file"
# postconf warns on a bad or unknown parameter and still exits 0, so read stderr.
warn="$(postconf -c "$WORK/pf" -n 2>&1 >/dev/null)" || fail "postconf rejected the relay config"
[ -z "$warn" ] || fail "postconf warned about the relay config: $warn"

echo "opendkim config parses, a key generates, opendkim starts and listens"
(cd "$WORK" && opendkim-genkey --directory="$WORK" --selector=boottest \
    --domain=example.invalid --bits=2048) || fail "opendkim-genkey failed"
mv "$WORK/boottest.private" "$WORK/example.invalid.private"
chmod 0400 "$WORK/example.invalid.private"
echo "example example.invalid:boottest:$WORK/example.invalid.private" > "$WORK/keytable"
echo "*@example.invalid example" > "$WORK/signingtable"
printf '127.0.0.1\n::1\n' > "$WORK/internalhosts"
conf() {
    cat <<EOT
Mode                    s
Canonicalization        relaxed/simple
OversignHeaders         From
SubDomains              no
Socket                  inet:8891@127.0.0.1
KeyTable                $WORK/keytable
SigningTable            refile:$WORK/signingtable
InternalHosts           $WORK/internalhosts
RequireSafeKeys         yes
EOT
}
# Production's directives. UserID needs setuid and Background forks, so they are
# only parsed here (-n), not run.
{ conf; printf 'Syslog yes\nSyslogSuccess yes\nUserID opendkim\nPidFile /run/opendkim/opendkim.pid\nBackground yes\n'; } > "$WORK/prod.conf"
opendkim -n -x "$WORK/prod.conf" || fail "opendkim rejected the production config"
conf > "$WORK/run.conf"
opendkim -f -x "$WORK/run.conf" >"$WORK/opendkim.log" 2>&1 &
ODPID=$!
up=
for _ in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/8891) 2>/dev/null; then up=1; break; fi
    kill -0 "$ODPID" 2>/dev/null || break
    sleep 0.5
done
[ -n "$up" ] || { cat "$WORK/opendkim.log" >&2; fail "opendkim is not listening on 127.0.0.1:8891"; }

echo "boot gate passed"
