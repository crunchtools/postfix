# postfix Constitution

> **Version:** 1.1.0
> **Ratified:** 2026-05-21
> **Amended:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.21.0
> **Profile:** Container Image

This file holds what is specific to postfix. The fleet rules and the Container
Image profile (license, versioning, LABELs, the RHSM secret-mount pattern,
systemd conventions, registry, testing and quality gates) apply at the
inherited version and are checked against this repo's files by
`constitution.yml`. They are not restated here.

## Purpose

UBI 10 Postfix SMTP router, deployed as `mail.crunchtools.com`. A front-door
relay: it accepts inbound mail on port 25 and forwards each message, by
recipient domain, to the backend mail container for that domain. It performs
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

## Packages and Services

- **Packages:** postfix.
- **Port:** 25 (`EXPOSE 25`).
- **Entrypoint:** `/entrypoint.sh`, not `/sbin/init`.

## Runtime Configuration

The image is generic and carries no deployment config. Routing and TLS are
mounted at runtime, never baked in:

| Mount | Container path | Purpose |
|-------|----------------|---------|
| `main.cf` | `/conf/main.cf` | Postfix relay configuration |
| `transport` | `/conf/transport` | Domain-to-backend routing map |
| `smtp.crt` | `/tls/smtp.crt` | STARTTLS certificate |
| `smtp.key` | `/tls/smtp.key` | STARTTLS private key |

`entrypoint.sh` copies the mounted config into `/etc/postfix`, runs
`postmap lmdb:` on the transport map (UBI's postfix ships the lmdb map type,
not Berkeley DB hash), runs a non-fatal `postfix check` to repair spool
permissions, then `exec`s `postfix start-fg`. The live config is
version-controlled in a private host repo.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-05-21 | Initial constitution-compliant postfix SMTP router |
| 1.1.0 | 2026-10-02 | Manifest under constitution v1.18.0: profile restatement removed, image specifics kept |
