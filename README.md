# postfix

UBI 10 **Postfix SMTP router** for the crunchtools infrastructure. It runs as
`mail.crunchtools.com` on lotor: a front-door relay that accepts inbound mail on
port 25 and forwards each message, by recipient domain, to the appropriate
backend mail container. It does **no local delivery**.

Outbound mail from our own sites is **DKIM-signed** on the way through, by an
`opendkim` milter running alongside postfix.

> This image is a Postfix relay. Despite an earlier mislabeled registry repo
> (`postgres`), it has nothing to do with PostgreSQL.

## What it routes (current deployment)

| Recipient domain               | Backend transport             |
|--------------------------------|--------------------------------|
| `rootsofthevalley.org`         | `smtp:[<backend-container-ip>]:25` |
| `newsletter.crunchtools.com`   | `smtp:[<backend-container-ip>]:25` |

The real transport map (with actual backend IPs) lives with the rest of the
private deployment config, not in this repo — see Design below.

## Design

The image is **generic and carries no deployment config**. Routing
(`main.cf`, `transport`) and TLS material are **mounted at runtime**, not baked
in. The live, version-controlled config for `mail.crunchtools.com` lives in the
private host repo (`fatherlinux/lotor.dc3.crunchtools.com-srv`) under
`mail.crunchtools.com/config/`, alongside every other service on that host.

| Mount              | Container path        | Purpose                          |
|--------------------|-----------------------|----------------------------------|
| `main.cf`          | `/conf/main.cf`       | Postfix relay configuration      |
| `transport`        | `/conf/transport`     | Domain → backend routing map     |
| `smtp.crt`         | `/tls/smtp.crt`       | STARTTLS certificate             |
| `smtp.key`         | `/tls/smtp.key`       | STARTTLS private key             |
| `opendkim.conf`    | `/conf/opendkim.conf` | DKIM signer configuration        |
| `keytable`         | `/conf/keytable`      | Domain → selector → key file     |
| `signingtable`     | `/conf/signingtable`  | Which `From:` domains get signed |
| `internalhosts`    | `/conf/internalhosts` | Which clients may have mail signed |
| `dkim/`            | `/dkim`               | Private signing keys, read-only  |

`entrypoint.sh` copies the mounted config into `/etc/postfix`, runs `postmap`
on the transport map, starts `opendkim` if a signer config is mounted, then
`exec`s `postfix start-fg`.

### DKIM signing

The signer is optional: with no `/conf/opendkim.conf` mounted this is the plain
relay it has always been. When the config *is* mounted it is mandatory — a
signer that will not start takes the container down rather than quietly sending
unsigned mail.

Two gates decide what gets signed, and both have to say yes:

- **`signingtable`** — which `From:` domains we sign at all.
- **`internalhosts`** — which clients are allowed to have their mail signed.
  Keep it to the backend containers that legitimately send as our domains. A
  relay that signs anything claiming to be `From:` one of our domains hands a
  stranger our reputation.

Private keys stay on the host, `root`-owned and `0400`, mounted read-only at
`/dkim`. The entrypoint copies them into the container's writable layer owned
by the `opendkim` user, which is what lets the signer run unprivileged while
the host keys stay locked down.

`opendkim` logs to syslog, so mount the host's socket (`-v /dev/log:/dev/log`)
if you want to see why a message was or was not signed. Without it the signer
is silent and postfix's own log will not tell you.

## Test

```bash
./test/boot-test.sh <image-ref>
```

Starts the image the way production starts it, with a throwaway key, and
asserts that postfix answers on `:25`, that opendkim is up, that mail from a
listed client for a listed domain comes out signed, and that mail fails to be
signed when either gate says no. CI runs this before anything is pushed.

## Build

```bash
podman build -f Containerfile -t quay.io/crunchtools/postfix:latest .
```

CI builds each pull request once, runs the boot test against the pushed
digest, and on merge copies that tested digest to `main`; a `v*` tag copies it
to the version tags and `latest` (constitution `container-release.yml`). A
weekly rebuild, gated the same way, picks up base image and EPEL security
updates.

`opendkim` is not in any UBI 10 repository, so the build adds EPEL 10 — with
its GPG key imported first, so the packages are verified.

## Run (as deployed on lotor)

```bash
podman run -d --name mail.crunchtools.com --hostname mail.crunchtools.com \
  --network mail:ip=<container-ip> -p 0.0.0.0:25:25 --memory=512m \
  -v /srv/mail.crunchtools.com/config/main.cf:/conf/main.cf:ro,Z \
  -v /srv/mail.crunchtools.com/config/transport:/conf/transport:ro,Z \
  -v /srv/mail.crunchtools.com/config/smtp.crt:/tls/smtp.crt:ro,Z \
  -v /srv/mail.crunchtools.com/config/smtp.key:/tls/smtp.key:ro,Z \
  -v /srv/mail.crunchtools.com/config/opendkim.conf:/conf/opendkim.conf:ro,Z \
  -v /srv/mail.crunchtools.com/config/keytable:/conf/keytable:ro,Z \
  -v /srv/mail.crunchtools.com/config/signingtable:/conf/signingtable:ro,Z \
  -v /srv/mail.crunchtools.com/config/internalhosts:/conf/internalhosts:ro,Z \
  -v /srv/mail.crunchtools.com/config/dkim:/dkim:ro,Z \
  -v /dev/log:/dev/log \
  quay.io/crunchtools/postfix:main
```

Managed by the `mail.crunchtools.com.service` systemd unit on lotor.

## Tags

| Tag | What it is |
|-----|------------|
| `main` | The newest tested build of the default branch. **Use this one.** The weekly errata rebuild of `main` is how this image gets CVE fixes between releases. |
| `latest` | The newest stable release, per [constitution](https://github.com/crunchtools/constitution) 1.33.0. It moves only when a `v*` tag is cut, so it lags `main` on errata. |
| `sha-<sha>` | A specific commit's tested build, for pinning. |

`latest` used to mean "the newest build of `main`". It stopped on 2026-11-07,
after that reading put an unreleased build of another image into production
unattended (RT#1559).

## Governance

This repo follows the [crunchtools constitution](https://github.com/crunchtools/constitution)
**Container Image** profile. See [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## License

AGPL-3.0-or-later
