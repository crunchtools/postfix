# postfix Constitution

> **Version:** 1.2.0
> **Ratified:** 2026-05-21
> **Amended:** 2026-11-03
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.39.1
> **Profile:** Container Image

This file holds what is specific to postfix. The fleet rules and the Container
Image profile (license, versioning, LABELs, the RHSM secret-mount pattern,
systemd conventions, registry, testing and quality gates) apply at the
inherited version and are checked against this repo's files by
`constitution.yml`. They are not restated here.

## Purpose

UBI 10 Postfix SMTP router with DKIM signing, deployed as
`mail.crunchtools.com`. A front-door relay: it accepts inbound mail on port 25,
signs outbound mail from our own domains with an `opendkim` milter, and forwards
each message, by recipient domain, to the backend mail container for that
domain. It performs
**no local delivery**. Published as `quay.io/crunchtools/postfix`. Despite an
earlier mislabeled registry repo (`postgres`), it has nothing to do with
PostgreSQL.

## Parent Image

`registry.access.redhat.com/ubi10/ubi-minimal:latest`. Postfix is a single
foreground process, so the image needs neither systemd nor `ubi-init`, and is
not part of the ubi10-core cascade. `postfix` comes from
`ubi-10-appstream-rpms`; no RHSM registration. ubi-minimal ships `microdnf`,
so packages install with `microdnf install` / `microdnf clean all` rather
than `dnf`.

`opendkim` is in no UBI 10 repository — not BaseOS, AppStream or CodeReady —
so the build adds EPEL 10. Its GPG key is imported before the release package
is installed, so every EPEL package is signature-verified. Each install is its
own command in the `&&` chain, so a failed one (an EPEL mirror outage) fails
the build rather than shipping an image with no signer.

## Packages and Services

- **Packages:** postfix (UBI AppStream); opendkim, opendkim-tools (EPEL 10).
- **Port:** 25 (`EXPOSE 25`).
- **Entrypoint:** `/entrypoint.sh`, not `/sbin/init`.
- **Processes:** two. `opendkim` daemonizes first and postfix runs in the
  foreground as PID 1. Because the image is multi-service, the Container Image
  profile's boot test is required, not optional: `test/boot-test.sh`.

## Runtime Configuration

The image is generic and carries no deployment config. Routing and TLS are
mounted at runtime, never baked in:

| Mount | Container path | Purpose |
|-------|----------------|---------|
| `main.cf` | `/conf/main.cf` | Postfix relay configuration |
| `transport` | `/conf/transport` | Domain-to-backend routing map |
| `smtp.crt` | `/tls/smtp.crt` | STARTTLS certificate |
| `smtp.key` | `/tls/smtp.key` | STARTTLS private key |
| `opendkim.conf` | `/conf/opendkim.conf` | DKIM signer configuration |
| `keytable` | `/conf/keytable` | Domain-to-selector-to-key map |
| `signingtable` | `/conf/signingtable` | Which `From:` domains get signed |
| `internalhosts` | `/conf/internalhosts` | Which clients may have mail signed |
| `dkim/` | `/dkim` | Private signing keys, read-only |

`entrypoint.sh` copies the mounted config into `/etc/postfix`, runs
`postmap lmdb:` on the transport map (UBI's postfix ships the lmdb map type,
not Berkeley DB hash), starts `opendkim` if a signer config is mounted, runs a
non-fatal `postfix check` to repair spool permissions, then `exec`s
`postfix start-fg`. The live config is version-controlled in a private host
repo.

## DKIM Signing

Signing is optional at the image level and mandatory once configured: with no
`/conf/opendkim.conf` the image is the plain relay, and with one a signer that
will not start takes the container down rather than sending unsigned mail.

Two gates decide what is signed, and both must agree — `signingtable` for the
`From:` domain and `internalhosts` for the client. The second is the forgery
gate; opendkim's default of `127.0.0.1` alone would mean signing nothing on a
relay whose clients all arrive over the network, so `entrypoint.sh` requires
the file rather than letting that default stand.

Private keys stay on the host, `root`-owned and `0400`, mounted read-only.
`entrypoint.sh` copies them into the container's writable layer owned by the
`opendkim` user, which is what lets the signer run unprivileged without
loosening the host permissions. Keys are never baked into the image and never
committed.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-05-21 | Initial constitution-compliant postfix SMTP router |
| 1.1.0 | 2026-10-02 | Manifest under constitution v1.18.0: profile restatement removed, image specifics kept |
| 1.2.0 | 2026-11-03 | DKIM signing: opendkim from EPEL 10, signer mounts, two signing gates, boot test now required (RT#1548) |
