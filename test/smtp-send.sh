#!/usr/bin/env bash
# Minimal SMTP client over bash's /dev/tcp, so the boot test can submit a
# message from inside the relay container (127.0.0.1, an InternalHost) without
# needing python or a mail client in the image.
#
# Usage: smtp-send.sh <from> <to>
set -euo pipefail
FROM="${1:?usage: smtp-send.sh <from> <to>}"
TO="${2:?usage: smtp-send.sh <from> <to>}"

exec 3<>/dev/tcp/127.0.0.1/25

# Read one SMTP reply, following continuation lines ("250-foo" then "250 bar").
reply() {
    local line code=""
    while IFS= read -r -t 10 -u 3 line; do
        line="${line%$'\r'}"
        code="${line:0:3}"
        [ "${line:3:1}" = "-" ] || break
    done
    echo "$code"
}

expect() {
    local want="$1" got
    got="$(reply)"
    case "$got" in
        "$want"*) ;;
        *) echo "expected $want, got '$got'" >&2; exit 1 ;;
    esac
}

send() { printf '%s\r\n' "$1" >&3; }

expect 220
send "EHLO boot-test.invalid";    expect 250
send "MAIL FROM:<${FROM}>";       expect 250
send "RCPT TO:<${TO}>";           expect 250
send "DATA";                      expect 354
printf 'From: %s\r\nTo: %s\r\nSubject: boot test\r\n\r\nboot test body\r\n.\r\n' "$FROM" "$TO" >&3
expect 250
send "QUIT"
exec 3<&-
