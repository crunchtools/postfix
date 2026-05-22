# postfix Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-05-21
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.0.0
> **Profile:** Container Image

UBI 10 Postfix SMTP router. Runs Postfix in the foreground as a front-door relay:
it accepts inbound mail on port 25 and forwards each message, by recipient domain,
to the appropriate backend mail container. It performs **no local delivery** — it
is purely a routing/relay tier. Deployed as `mail.crunchtools.com` on lotor.

---

## License

AGPL-3.0-or-later

## Versioning

Follow Semantic Versioning 2.0.0 (MAJOR.MINOR.PATCH). MAJOR for incompatible
routing/behavior changes, MINOR for backwards-compatible capability additions,
PATCH for fixes.

## Base Image

`registry.access.redhat.com/ubi10/ubi-minimal:latest` — single foreground
service (Postfix), so no systemd/`ubi-init` is required. Postfix is installed
from `ubi-10-appstream-rpms`, which is available in UBI without RHSM
registration.

## Registry

Published to `quay.io/crunchtools/postfix`.

- `latest` — most recent build from the default branch
- `<sha>` — git commit SHA for traceability

## RHSM Registration

Not required. The only package installed (`postfix`) ships in the UBI AppStream
repository, so no build-time `subscription-manager` registration is used.

## Containerfile Conventions

- Uses `Containerfile` (not Dockerfile)
- Required LABELs: `maintainer`, `description`, plus OCI labels
  (`org.opencontainers.image.source`, `.description`, `.licenses`)
- `microdnf install -y postfix` followed by `microdnf clean all` (ubi-minimal
  ships `microdnf`, not full `dnf`)
- Routing config (`main.cf`, `transport`) and TLS material are **mounted at
  runtime** under `/conf` and `/tls`, never baked into the image
- `EXPOSE 25`
- `ENTRYPOINT ["/entrypoint.sh"]` — applies mounted config, runs `postmap`,
  then `exec /usr/sbin/postfix start-fg`

## Packages Installed

postfix

## Testing

- **Build test**: CI builds the image from the Containerfile on every push and
  pull request to main/master.
- **Smoke test**: Container starts and `postfix start-fg` reaches a running
  state with a `main.cf`/`transport` and TLS cert/key mounted (verified before
  release). The image carries no deployment config; per-host config is
  version-controlled in the private host repo.
- **Security scan**: Recommended (Trivy or equivalent), not yet wired into CI.

## Quality Gates

1. **Build** — CI builds the Containerfile successfully (`podman build -f Containerfile .`).
2. **Constitution validation** — `validate-constitution.py` passes against this document.
3. **Smoke test** — `postfix check` succeeds and the router accepts SMTP on :25.
4. **Weekly rebuild** — cron job rebuilds every Monday 06:00 UTC to pick up base
   image security updates.

All gates must pass before merge or push to the registry.
