# postfix

UBI 10 **Postfix SMTP router** for the crunchtools infrastructure. It runs as
`mail.crunchtools.com` on lotor: a front-door relay that accepts inbound mail on
port 25 and forwards each message, by recipient domain, to the appropriate
backend mail container. It does **no local delivery**.

> This image is a Postfix relay. Despite an earlier mislabeled registry repo
> (`postgres`), it has nothing to do with PostgreSQL.

## What it routes

| Recipient domain               | Backend transport        |
|--------------------------------|--------------------------|
| `rootsofthevalley.org`         | `smtp:[10.89.1.10]:25`   |
| `newsletter.crunchtools.com`   | `smtp:[10.89.1.11]:25`   |

Routing lives in [`config/transport`](config/transport); relay policy and TLS
settings live in [`config/main.cf`](config/main.cf).

## Design

The image is generic: routing config and TLS material are **mounted at runtime**,
not baked in.

| Mount              | Container path        | Purpose                          |
|--------------------|-----------------------|----------------------------------|
| `main.cf`          | `/conf/main.cf`       | Postfix relay configuration      |
| `transport`        | `/conf/transport`     | Domain → backend routing map     |
| `smtp.crt`         | `/tls/smtp.crt`       | STARTTLS certificate             |
| `smtp.key`         | `/tls/smtp.key`       | STARTTLS private key             |

`entrypoint.sh` copies the mounted config into `/etc/postfix`, runs `postmap`
on the transport map, then `exec`s `postfix start-fg`.

## Build

```bash
podman build -f Containerfile -t quay.io/crunchtools/postfix:latest .
```

CI (GitHub Actions) builds on every push/PR and pushes `latest` + the commit
SHA to `quay.io/crunchtools/postfix` from the default branch. A weekly cron
rebuild picks up base image security updates.

## Run (as deployed on lotor)

```bash
podman run -d --name mail.crunchtools.com --hostname mail.crunchtools.com \
  --network mail:ip=10.89.1.2 -p 0.0.0.0:25:25 --memory=512m \
  -v /srv/mail.crunchtools.com/config/main.cf:/conf/main.cf:ro,Z \
  -v /srv/mail.crunchtools.com/config/transport:/conf/transport:ro,Z \
  -v /srv/mail.crunchtools.com/config/smtp.crt:/tls/smtp.crt:ro,Z \
  -v /srv/mail.crunchtools.com/config/smtp.key:/tls/smtp.key:ro,Z \
  quay.io/crunchtools/postfix:latest
```

Managed by the `mail.crunchtools.com.service` systemd unit on lotor.

## Governance

This repo follows the [crunchtools constitution](https://github.com/crunchtools/constitution)
**Container Image** profile. See [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## License

AGPL-3.0-or-later
